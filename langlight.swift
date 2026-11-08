// langlight — set Razer keyboard (BLE, Razer protocol 3.0) static color per active input source.
//
// Usage:
//   langlight set RRGGBB                 one-shot: set static color and exit
//   langlight watch [--en RRGGBB] [--he RRGGBB]   follow input source changes
//
// Protocol (reverse-engineered from Synapse logs):
//   service 52401523-f97c-7f90-0e7f-6c6f4e36db1c, write ...1524, notify ...1525
//   header (8 bytes): txid, dataLen (3 bytes LE), class 0x10, cmd 0x03, 0x01, 0x00
//   data: 01 (static) 00 00 01 (1 color) R G B

import Foundation
import CoreBluetooth
import Carbon

let serviceUUID = CBUUID(string: "52401523-F97C-7F90-0E7F-6C6F4E36DB1C")
let writeUUID = CBUUID(string: "52401524-F97C-7F90-0E7F-6C6F4E36DB1C")
let notifyUUID = CBUUID(string: "52401525-F97C-7F90-0E7F-6C6F4E36DB1C")

func log(_ s: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write("[\(ts)] \(s)\n".data(using: .utf8)!)
}

func parseHex(_ s: String) -> [UInt8]? {
    let h = s.hasPrefix("#") ? String(s.dropFirst()) : s
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return [UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
}

final class RazerLink: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var txid: UInt8 = 0x40
    private var pendingColor: [UInt8]?
    var onReady: (() -> Void)?
    var onWritten: (() -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.ensureConnected() }
    }

    var isReady: Bool { writeChar != nil && peripheral?.state == .connected }

    private var pendingRaw: ([UInt8], [UInt8])?

    func setColor(_ rgb: [UInt8]) {
        pendingColor = rgb
        flush()
    }

    // cmd = [class, id, sub1, sub2]
    func sendRaw(_ cmd: [UInt8], _ data: [UInt8]) {
        pendingRaw = (cmd, data)
        flush()
    }

    private func flush() {
        guard pendingColor != nil || pendingRaw != nil, let p = peripheral, let c = writeChar, p.state == .connected else {
            ensureConnected()
            return
        }
        var cmd: [UInt8] = [0x10, 0x03, 0x01, 0x00]
        var data: [UInt8]
        if let raw = pendingRaw {
            (cmd, data) = raw
            pendingRaw = nil
        } else {
            data = [0x01, 0x00, 0x00, 0x01] + pendingColor!
        }
        let rgb = Array(data.suffix(3))
        pendingColor = nil
        txid = txid &+ 1
        let header: [UInt8] = [txid, UInt8(data.count), 0x00, 0x00] + cmd
        let type: CBCharacteristicWriteType = c.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        p.writeValue(Data(header), for: c, type: type)
        // Synapse sends the payload in 20-byte chunks after the header.
        for start in stride(from: 0, to: data.count, by: 20) {
            p.writeValue(Data(data[start..<min(start + 20, data.count)]), for: c, type: type)
        }
        log("sent " + (header + data).map { String(format: "%02x", $0) }.joined(separator: " "))
        _ = rgb
        if type == .withoutResponse {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.onWritten?() }
        }
    }

    private func ensureConnected() {
        guard central.state == .poweredOn else { return }
        if let p = peripheral, p.state == .connected || p.state == .connecting { return }
        let found = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
        guard let p = found.first else {
            log("Razer BLE keyboard not connected to this Mac; waiting")
            return
        }
        log("found \(p.name ?? "?") \(p.identifier)")
        peripheral = p
        writeChar = nil
        p.delegate = self
        central.connect(p)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        log("bluetooth state \(c.state.rawValue)")
        if c.state == .poweredOn { ensureConnected() }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([serviceUUID])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        log("connect failed: \(error?.localizedDescription ?? "?")")
        peripheral = nil
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        log("disconnected")
        writeChar = nil
        peripheral = nil
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == serviceUUID }) else {
            log("Razer service not found"); return
        }
        p.discoverCharacteristics([writeUUID, notifyUUID], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for c in s.characteristics ?? [] {
            if c.uuid == writeUUID { writeChar = c }
            if c.uuid == notifyUUID { p.setNotifyValue(true, for: c) }
        }
        guard writeChar != nil else { log("write characteristic not found"); return }
        log("ready")
        onReady?()
        flush()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let v = c.value else { return }
        if ProcessInfo.processInfo.environment["LL_DEBUG"] != nil {
            log("notify " + v.map { String(format: "%02x", $0) }.joined(separator: " "))
        }
        guard v.count >= 8 else { return }
        let status = ["?", "busy", "ok", "failure", "timeout", "not supported", "profile not supported", "target not supported"]
        let st = Int(v[7])
        log("response tx=\(v[0]) status=\(st < status.count ? status[st] : String(st))")
        if v[0] == txid {
            if v.count > 8 { log("payload " + v.dropFirst(8).map { String(format: "%02x", $0) }.joined(separator: " ")) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.onWritten?() }
        }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        if let error { log("write error: \(error.localizedDescription)") }
    }
}

func currentInputSource() -> (id: String, isHebrew: Bool) {
    let src = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    var id = "?"
    if let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) {
        id = Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }
    var langs: [String] = []
    if let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) {
        langs = Unmanaged<CFArray>.fromOpaque(p).takeUnretainedValue() as? [String] ?? []
    }
    let hebrew = langs.first.map { $0.hasPrefix("he") || $0.hasPrefix("iw") } ?? false
        || id.localizedCaseInsensitiveContains("hebrew")
    return (id, hebrew)
}

// MARK: - main

var args = Array(CommandLine.arguments.dropFirst())
let mode = args.first ?? "watch"
let link = RazerLink()

switch mode {
case "set":
    guard args.count >= 2, let rgb = parseHex(args[1]) else {
        print("usage: langlight set RRGGBB"); exit(2)
    }
    link.onWritten = { exit(0) }
    link.setColor(rgb)
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { log("timeout"); exit(1) }

case "raw":
    // langlight raw 06 04 00 18 ff 00 00   (class id sub1 sub2 data...)
    let bytes = args.dropFirst().compactMap { UInt8($0, radix: 16) }
    guard bytes.count >= 4 else { print("usage: langlight raw CLASS ID SUB1 SUB2 [DATA...]"); exit(2) }
    link.onWritten = { exit(0) }
    link.sendRaw(Array(bytes.prefix(4)), Array(bytes.dropFirst(4)))
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { log("timeout"); exit(1) }

case "watch":
    var en: [UInt8] = [0x00, 0x60, 0xff]
    var he: [UInt8] = [0xff, 0x40, 0x00]
    var i = 1
    while i < args.count {
        if args[i] == "--en", i + 1 < args.count, let c = parseHex(args[i + 1]) { en = c; i += 1 }
        else if args[i] == "--he", i + 1 < args.count, let c = parseHex(args[i + 1]) { he = c; i += 1 }
        i += 1
    }
    var lastApplied: [UInt8]?
    func apply(force: Bool = false) {
        let s = currentInputSource()
        let rgb = s.isHebrew ? he : en
        if !force && rgb == lastApplied { return }
        log("input source \(s.id) -> \(s.isHebrew ? "Hebrew" : "English")")
        lastApplied = rgb
        link.setColor(rgb)
    }
    // Re-apply whenever the link (re)connects, e.g. after keyboard sleep.
    link.onReady = { lastApplied = nil; apply(force: true) }
    DistributedNotificationCenter.default().addObserver(
        forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
        object: nil, queue: .main) { _ in apply() }
    apply(force: true)

default:
    print("usage: langlight set RRGGBB | langlight watch [--en RRGGBB] [--he RRGGBB]")
    exit(2)
}

RunLoop.main.run()
