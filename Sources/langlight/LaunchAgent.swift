import Foundation

enum LaunchAgent {
    static let label = "local.langlight"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var logPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/langlight.log").path
    }

    static func plist(executable: String, extraArgs: [String]) -> String {
        let argv = ([executable, "watch"] + extraArgs).map { "        <string>\($0)</string>" }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
        \(argv)
            </array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><true/>
            <key>ProcessType</key><string>Interactive</string>
            <key>StandardErrorPath</key><string>\(logPath)</string>
            <key>StandardOutPath</key><string>\(logPath)</string>
        </dict>
        </plist>

        """
    }

    @discardableResult
    private static func launchctl(_ a: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = a
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus
    }

    static func install(extraArgs: [String]) throws {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
        let exePath = exe.hasPrefix("/") ? exe : FileManager.default.currentDirectoryPath + "/" + exe
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plist(executable: exePath, extraArgs: extraArgs).write(to: plistURL, atomically: true, encoding: .utf8)
        let domain = "gui/\(getuid())"
        launchctl(["bootout", "\(domain)/\(label)"])
        guard launchctl(["bootstrap", domain, plistURL.path]) == 0 else {
            throw NSError(domain: "langlight", code: 1, userInfo: [NSLocalizedDescriptionKey: "launchctl bootstrap failed"])
        }
        print("installed \(plistURL.path); log: \(logPath)")
    }

    static func uninstall() {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
        print("uninstalled")
    }
}
