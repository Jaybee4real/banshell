import AppKit
import Foundation

let cliCommands: Set<String> = ["setpin", "arm", "disarm", "drill", "watch", "install",
                                "uninstall", "status", "sensors", "version", "help", "preview"]

let arguments = CommandLine.arguments
if arguments.count > 1, cliCommands.contains(arguments[1]) {
    runCLI(arguments[1])
} else {
    try? FileManager.default.createDirectory(at: Paths.supportDir, withIntermediateDirectories: true)
    let lockDescriptor = open(Paths.lockFile.path, O_CREAT | O_RDWR, 0o600)
    if lockDescriptor < 0 || flock(lockDescriptor, LOCK_EX | LOCK_NB) != 0 {
        let launchedByLaunchd = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == launchdLabel
        if !launchedByLaunchd {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.jaybee.banshell.showSettings"), object: nil,
                userInfo: nil, deliverImmediately: true)
        }
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
