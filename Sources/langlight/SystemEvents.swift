import AppKit

enum SystemEvents {
    /// Calls `handler` on wake from sleep, screen unlock and session activation.
    static func observe(_ handler: @escaping (String) -> Void) {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in handler("wake") }
        ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in handler("session active") }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in handler("unlock") }
    }
}
