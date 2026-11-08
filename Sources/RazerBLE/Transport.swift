import Foundation

/// Byte pipe to the keyboard. CoreBluetooth in production, a fake in tests.
/// All callbacks must be delivered on the main thread.
public protocol Transport: AnyObject {
    var isReady: Bool { get }
    /// Called when the link becomes usable (true) or is lost (false).
    var onReadyChanged: ((Bool) -> Void)? { get set }
    /// Called for every notification from the keyboard.
    var onNotify: ((Data) -> Void)? { get set }
    /// Start connecting; keeps retrying until the keyboard shows up.
    func start()
    func stop()
    /// Write the chunks in order, without waiting for acknowledgement.
    func write(_ chunks: [Data]) throws
}
