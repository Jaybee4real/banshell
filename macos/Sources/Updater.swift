import AppKit
import Foundation

let updateRepo = "Jaybee4real/banshell"
let macInstallerAsset = "Banshell-macOS-Installer.pkg"

struct ReleaseInfo {
    let version: String
    let assetURL: URL
    let notes: String
}

enum UpdateOutcome {
    case upToDate
    case available(ReleaseInfo)
    case failed(String)
}

func parseVersion(_ text: String) -> [Int] {
    text.trimmingCharacters(in: CharacterSet(charactersIn: "v "))
        .split(separator: ".")
        .map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
}

func versionIsNewer(_ candidate: String, than current: String) -> Bool {
    let candidateParts = parseVersion(candidate)
    let currentParts = parseVersion(current)
    for index in 0..<max(candidateParts.count, currentParts.count) {
        let left = index < candidateParts.count ? candidateParts[index] : 0
        let right = index < currentParts.count ? currentParts[index] : 0
        if left != right { return left > right }
    }
    return false
}

final class Updater: NSObject, URLSessionDownloadDelegate {
    static let shared = Updater()
    private var checking = false
    private var downloadingVersion: String?
    private var downloadPercent = 0
    private var pendingVersion = ""
    private var pendingAutoInstall = false
    private var readyRelease: ReleaseInfo?
    private var readyInstaller: (url: URL, version: String)?
    var onStatusChange: (() -> Void)?

    private lazy var downloadSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    var statusText: String? {
        if let readyInstaller { return "Install v\(readyInstaller.version) & Restart" }
        if let readyRelease { return "Download & Install v\(readyRelease.version)" }
        if let downloadingVersion { return "Downloading v\(downloadingVersion)… \(downloadPercent)%" }
        return nil
    }

    func actOnStatus() {
        if let readyInstaller {
            runInstaller(at: readyInstaller.url, version: readyInstaller.version)
        } else if let release = readyRelease {
            readyRelease = nil
            downloadSilent(release, autoInstall: true)
        }
    }

    private func notifyStatus() {
        DispatchQueue.main.async { self.onStatusChange?() }
    }

    func fetchLatest() -> UpdateOutcome {
        guard let url = URL(string: "https://api.github.com/repos/\(updateRepo)/releases/latest") else {
            return .failed("bad url")
        }
        var request = URLRequest(url: url)
        request.setValue("BANSHELL-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        var outcome: UpdateOutcome = .failed("no response")
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            if let error {
                outcome = .failed(error.localizedDescription)
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                outcome = .failed("malformed response")
                return
            }
            let notes = json["body"] as? String ?? ""
            let assets = json["assets"] as? [[String: Any]] ?? []
            guard let asset = assets.first(where: { ($0["name"] as? String) == macInstallerAsset }),
                  let urlString = asset["browser_download_url"] as? String,
                  let assetURL = URL(string: urlString) else {
                outcome = .failed("no macOS installer attached to the latest release")
                return
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            if versionIsNewer(version, than: banshellVersion) {
                outcome = .available(ReleaseInfo(version: version, assetURL: assetURL, notes: notes))
            } else {
                outcome = .upToDate
            }
        }.resume()
        semaphore.wait()
        return outcome
    }

    func checkForUpdates(silent: Bool) {
        guard !checking else { return }
        checking = true
        DispatchQueue.global(qos: .utility).async {
            let outcome = self.fetchLatest()
            DispatchQueue.main.async {
                self.checking = false
                switch outcome {
                case .upToDate:
                    if !silent { self.showInfo("You're up to date", "BANSHELL v\(banshellVersion) is the latest version.") }
                case .available(let info):
                    if silent { self.handleSilentAvailable(info) } else { self.promptUpdate(info) }
                case .failed(let message):
                    if silent {
                        logLine("update check failed: \(message)")
                    } else {
                        self.showInfo("Couldn't check for updates", message)
                    }
                }
            }
        }
    }

    private func promptUpdate(_ info: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = "Update available: v\(info.version)"
        var body = "You have v\(banshellVersion). Install v\(info.version) now? BANSHELL will briefly restart."
        let trimmedNotes = info.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            body += "\n\nWhat's new:\n" + String(trimmedNotes.prefix(500))
        }
        alert.informativeText = body
        alert.addButton(withTitle: "Install & Restart")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        downloadSilent(info, autoInstall: true)
    }

    private func handleSilentAvailable(_ info: ReleaseInfo) {
        let config = loadConfig() ?? Config.defaults
        guard config.autoDownloadOn else {
            readyRelease = info
            notifyStatus()
            logLine("update v\(info.version) available — download off, waiting for user")
            return
        }
        downloadSilent(info, autoInstall: config.autoInstallOn)
    }

    private func downloadSilent(_ info: ReleaseInfo, autoInstall: Bool) {
        downloadingVersion = info.version
        downloadPercent = 0
        pendingVersion = info.version
        pendingAutoInstall = autoInstall
        readyRelease = nil
        readyInstaller = nil
        notifyStatus()
        downloadSession.downloadTask(with: info.assetURL).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let percent = Int(totalBytesWritten * 100 / totalBytesExpectedToWrite)
        guard percent != downloadPercent else { return }
        downloadPercent = percent
        notifyStatus()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Banshell-\(pendingVersion).pkg")
        try? FileManager.default.removeItem(at: destination)
        let moved = (try? FileManager.default.moveItem(at: location, to: destination)) != nil
        let version = pendingVersion
        let autoInstall = pendingAutoInstall
        DispatchQueue.main.async {
            self.downloadingVersion = nil
            guard moved else {
                logLine("update download failed to save")
                self.notifyStatus()
                return
            }
            if autoInstall {
                self.runInstaller(at: destination, version: version)
            } else {
                self.readyInstaller = (destination, version)
                logLine("update v\(version) downloaded — install off, waiting for user")
                self.notifyStatus()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async {
            self.downloadingVersion = nil
            logLine("update download failed: \(error.localizedDescription)")
            self.notifyStatus()
        }
    }

    private func runInstaller(at path: URL, version: String) {
        let shell = "/usr/sbin/installer -pkg '\(path.path)' -target /"
        let source = "do shell script \"\(appleScriptEscaped(shell))\" with administrator privileges"
        logLine("installing update v\(version)")
        DispatchQueue.global(qos: .userInitiated).async {
            var errorInfo: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
                if code != -128 {
                    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "install failed"
                    DispatchQueue.main.async { self.showInfo("Update failed", message) }
                }
            }
        }
    }

    private func showInfo(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
