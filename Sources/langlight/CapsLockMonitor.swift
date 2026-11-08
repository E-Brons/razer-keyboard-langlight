import Foundation
import CoreGraphics

enum CapsLockMonitor {
    /// Reads the modifier state without an event tap, so no Input Monitoring permission is needed.
    static func isOn() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

    /// Polls ~5 Hz; there is no change notification without an event tap.
    static func poll(_ handler: @escaping () -> Void) {
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in handler() }
    }
}
