import Foundation
import Carbon

enum InputSourceMonitor {
    /// nil when the query fails.
    static func current() -> InputKind? {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        var id: String?
        if let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) {
            id = Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
        }
        var langs: [String] = []
        if let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) {
            langs = Unmanaged<CFArray>.fromOpaque(p).takeUnretainedValue() as? [String] ?? []
        }
        return classify(id: id, languages: langs)
    }

    static func observe(_ handler: @escaping () -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { _ in handler() }
    }
}
