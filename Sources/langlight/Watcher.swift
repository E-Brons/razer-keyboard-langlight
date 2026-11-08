import Foundation
import RazerBLE

/// Keeps the keyboard color in sync with input source + Caps Lock.
@MainActor
final class Watcher {
    private let device: RazerDevice
    private let palette: Palette
    let log: (String) -> Void
    private var applied: RGB?
    private var busy = false

    init(device: RazerDevice, palette: Palette, log: @escaping (String) -> Void) {
        self.device = device; self.palette = palette; self.log = log
    }

    func start() {
        device.register { [weak self] event in
            // Keyboard forgets its color across sleep/reconnect, so re-apply.
            if case .connected = event { self?.forceApply() }
            if case .disconnected = event { self?.applied = nil }
        }
        InputSourceMonitor.observe { [weak self] in MainActor.assumeIsolated { self?.apply() } }
        CapsLockMonitor.poll { [weak self] in MainActor.assumeIsolated { self?.apply() } }
        device.connect()
        apply()
    }

    func forceApply() { applied = nil; apply() }

    func apply() {
        guard !busy, device.isConnected else { return }
        let kind = InputSourceMonitor.current()
        let target = color(kind: kind, capsLock: CapsLockMonitor.isOn(), palette: palette)
        guard target != applied else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await device.setStaticColor(r: target.r, g: target.g, b: target.b)
                applied = target
                log("input \(kind.map { "\($0)" } ?? "unknown") -> \(target)")
            } catch {
                log("set \(target) failed: \(error)")
                applied = nil
            }
        }
    }
}
