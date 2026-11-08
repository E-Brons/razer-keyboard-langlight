import Foundation
import CoreBluetooth

public let razerServiceUUID = CBUUID(string: "52401523-F97C-7F90-0E7F-6C6F4E36DB1C")
public let razerWriteUUID = CBUUID(string: "52401524-F97C-7F90-0E7F-6C6F4E36DB1C")
public let razerNotifyUUID = CBUUID(string: "52401525-F97C-7F90-0E7F-6C6F4E36DB1C")

/// Talks to a keyboard that is already connected to this Mac (paired in System Settings).
public final class CoreBluetoothTransport: NSObject, Transport, CBCentralManagerDelegate, CBPeripheralDelegate {
    public var onReadyChanged: ((Bool) -> Void)?
    public var onNotify: ((Data) -> Void)?
    public var log: (String) -> Void = { _ in }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var timer: Timer?
    private var wasReady = false

    public override init() { super.init() }

    public var isReady: Bool { writeChar != nil && peripheral?.state == .connected }

    public func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.ensureConnected() }
    }

    public func stop() {
        timer?.invalidate(); timer = nil
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil; writeChar = nil
        updateReady()
    }

    public func write(_ chunks: [Data]) throws {
        guard let p = peripheral, let c = writeChar, p.state == .connected else { throw DeviceError.notConnected }
        let type: CBCharacteristicWriteType = c.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        for chunk in chunks { p.writeValue(chunk, for: c, type: type) }
    }

    private func updateReady() {
        let now = isReady
        if now != wasReady { wasReady = now; onReadyChanged?(now) }
    }

    private func ensureConnected() {
        guard central.state == .poweredOn else { return }
        if let p = peripheral, p.state == .connected || p.state == .connecting { return }
        guard let p = central.retrieveConnectedPeripherals(withServices: [razerServiceUUID]).first else {
            log("Razer BLE keyboard not connected to this Mac; waiting")
            return
        }
        log("found \(p.name ?? "?") \(p.identifier)")
        peripheral = p
        writeChar = nil
        p.delegate = self
        central.connect(p)
    }

    public func centralManagerDidUpdateState(_ c: CBCentralManager) {
        log("bluetooth state \(c.state.rawValue)")
        if c.state == .poweredOn { ensureConnected() } else { writeChar = nil; updateReady() }
    }

    public func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([razerServiceUUID])
    }

    public func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        log("connect failed: \(error?.localizedDescription ?? "?")")
        peripheral = nil
    }

    public func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        log("disconnected")
        writeChar = nil
        peripheral = nil
        updateReady()
    }

    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == razerServiceUUID }) else {
            log("Razer service not found"); return
        }
        p.discoverCharacteristics([razerWriteUUID, razerNotifyUUID], for: s)
    }

    public func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for c in s.characteristics ?? [] {
            if c.uuid == razerWriteUUID { writeChar = c }
            if c.uuid == razerNotifyUUID { p.setNotifyValue(true, for: c) }
        }
        guard writeChar != nil else { log("write characteristic not found"); return }
        log("ready")
        updateReady()
    }

    public func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        if let v = c.value { onNotify?(v) }
    }

    public func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        if let error { log("write error: \(error.localizedDescription)") }
    }
}
