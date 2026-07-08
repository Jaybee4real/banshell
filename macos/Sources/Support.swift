import CryptoKit
import Foundation

let banshellVersion = "1.1.0"
let launchdLabel = "com.jaybee.banshell"

struct Config: Codable {
    var pinSaltHex: String
    var pinHashHex: String
    var armHour: Int
    var armMinute: Int
    var autoArmDaily: Bool
    var lidDeltaDegrees: Double
    var exitDelaySeconds: Int
    var entryDelaySeconds: Int
    var lidTrigger: Bool
    var powerTrigger: Bool
    var inputTrigger: Bool

    static var defaults: Config {
        Config(pinSaltHex: "", pinHashHex: "", armHour: 23, armMinute: 0,
               autoArmDaily: true, lidDeltaDegrees: 3.0, exitDelaySeconds: 30,
               entryDelaySeconds: 15, lidTrigger: true, powerTrigger: true, inputTrigger: true)
    }

    var hasPin: Bool { !pinHashHex.isEmpty }
}

struct AlarmState: Codable {
    var armed: Bool
    var triggered: Bool
    var lastAutoArmDay: String?
    var reason: String?
}

enum Paths {
    static let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Banshell")
    static let configFile = supportDir.appendingPathComponent("config.json")
    static let stateFile = supportDir.appendingPathComponent("state.json")
    static let lockFile = supportDir.appendingPathComponent(".lock")
    static let logFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/banshell.log")
    static let agentPlist = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(launchdLabel).plist")
}

func logLine(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    print("[\(stamp)] \(message)")
    fflush(stdout)
}

func loadConfig() -> Config? {
    guard let data = try? Data(contentsOf: Paths.configFile) else { return nil }
    return try? JSONDecoder().decode(Config.self, from: data)
}

func saveConfig(_ config: Config) {
    try? FileManager.default.createDirectory(at: Paths.supportDir, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(config) else { return }
    try? data.write(to: Paths.configFile, options: .atomic)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.configFile.path)
}

func loadState() -> AlarmState {
    guard let data = try? Data(contentsOf: Paths.stateFile),
          let state = try? JSONDecoder().decode(AlarmState.self, from: data) else {
        return AlarmState(armed: false, triggered: false, lastAutoArmDay: nil, reason: nil)
    }
    return state
}

func saveState(_ state: AlarmState) {
    try? FileManager.default.createDirectory(at: Paths.supportDir, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(state) else { return }
    try? data.write(to: Paths.stateFile, options: .atomic)
}

extension Data {
    init?(hexString: String) {
        let chars = Array(hexString)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        for index in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(chars[index...index + 1]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        self.init(bytes)
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

func hashPin(_ pin: String, saltHex: String) -> String {
    let salt = Data(hexString: saltHex) ?? Data()
    let digest = SHA256.hash(data: salt + Data(pin.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

func verifyPin(_ attempt: String, config: Config) -> Bool {
    hashPin(attempt, saltHex: config.pinSaltHex) == config.pinHashHex
}

func randomSaltHex() -> String {
    var bytes = [UInt8](repeating: 0, count: 16)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes).hexString
}

func readSecret(_ prompt: String) -> String {
    print(prompt, terminator: "")
    fflush(stdout)
    var oldTerm = termios()
    tcgetattr(STDIN_FILENO, &oldTerm)
    var newTerm = oldTerm
    newTerm.c_lflag &= ~tcflag_t(ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &newTerm)
    let line = readLine() ?? ""
    tcsetattr(STDIN_FILENO, TCSANOW, &oldTerm)
    print("")
    return line
}

@discardableResult
func runProcess(_ path: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return -1
    }
}

func binaryPath() -> String {
    let argumentZero = CommandLine.arguments[0]
    if argumentZero.hasPrefix("/") { return argumentZero }
    let cwd = FileManager.default.currentDirectoryPath
    return URL(fileURLWithPath: cwd).appendingPathComponent(argumentZero).standardizedFileURL.path
}

func sudoersReady() -> Bool {
    runProcess("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "disablesleep", "1"]) == 0
}

var sudoersRule: String {
    "\(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1\n"
}

var sudoersCommand: String {
    """
    echo '\(sudoersRule.trimmingCharacters(in: .newlines))' | sudo tee /etc/sudoers.d/banshell >/dev/null
    sudo chmod 440 /etc/sudoers.d/banshell
    sudo visudo -cf /etc/sudoers.d/banshell   # must print "parsed OK"; if not, sudo rm it immediately
    """
}

private func appleScriptEscaped(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

enum SudoersInstallResult {
    case installed
    case cancelled
    case failed(String)
}

func installSudoersRuleWithPrompt() -> SudoersInstallResult {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("banshell-sudoers-\(getpid())")
    do {
        try sudoersRule.write(to: tempURL, atomically: true, encoding: .utf8)
    } catch {
        return .failed("could not write temp file: \(error.localizedDescription)")
    }
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let shell = "/usr/sbin/visudo -cf '\(tempURL.path)' && /usr/bin/install -o root -g wheel -m 440 '\(tempURL.path)' /etc/sudoers.d/banshell"
    let source = "do shell script \"\(appleScriptEscaped(shell))\" with administrator privileges"
    var errorInfo: NSDictionary?
    guard let script = NSAppleScript(source: source) else { return .failed("could not build script") }
    script.executeAndReturnError(&errorInfo)
    if let errorInfo {
        let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
        if code == -128 { return .cancelled }
        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error"
        return .failed(message)
    }
    return .installed
}
