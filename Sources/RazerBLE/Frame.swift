import Foundation

/// Four-byte command selector: class, id, sub1, sub2.
public struct Command: Equatable, CustomStringConvertible {
    public var cls: UInt8, id: UInt8, sub1: UInt8, sub2: UInt8

    public init(_ cls: UInt8, _ id: UInt8, _ sub1: UInt8, _ sub2: UInt8) {
        self.cls = cls; self.id = id; self.sub1 = sub1; self.sub2 = sub2
    }

    public init?(bytes: [UInt8]) {
        guard bytes.count == 4 else { return nil }
        self.init(bytes[0], bytes[1], bytes[2], bytes[3])
    }

    public var bytes: [UInt8] { [cls, id, sub1, sub2] }
    public var description: String { hex(bytes) }

    /// Set lighting effect (static color, custom mode, ...).
    public static let setEffect = Command(0x10, 0x03, 0x01, 0x00)
    /// Getters known to exist; reply layouts are documented in docs/protocol.md.
    public static let get80 = Command(0x10, 0x80, 0x00, 0x00)
    public static let get81 = Command(0x10, 0x81, 0x00, 0x00)
    public static let get82 = Command(0x10, 0x82, 0x00, 0x00)
    public static let get83 = Command(0x10, 0x83, 0x00, 0x00)
    public static let get85 = Command(0x10, 0x85, 0x00, 0x00)
}

/// Response status byte (header byte 7).
public enum Status: UInt8, CustomStringConvertible {
    case unknown = 0, busy, ok, failure, timeout, notSupported, profileNotSupported, targetNotSupported

    public var description: String {
        switch self {
        case .unknown: return "unknown"
        case .busy: return "busy"
        case .ok: return "ok"
        case .failure: return "failure"
        case .timeout: return "timeout"
        case .notSupported: return "not supported"
        case .profileNotSupported: return "profile not supported"
        case .targetNotSupported: return "target not supported"
        }
    }
}

public struct Response: Equatable {
    public var txid: UInt8
    public var statusByte: UInt8
    public var payload: [UInt8]
    /// Full 8-byte header, kept so undecoded fields stay visible.
    public var header: [UInt8]

    public var status: Status? { Status(rawValue: statusByte) }
    public var isOK: Bool { status == .ok }
}

public func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

public enum Frame {
    public static let headerSize = 8
    public static let chunkSize = 20

    /// Request = one header write, then the payload in 20-byte writes.
    public static func encode(txid: UInt8, command: Command, data: [UInt8]) -> [Data] {
        let n = data.count
        let header: [UInt8] = [txid, UInt8(n & 0xff), UInt8((n >> 8) & 0xff), UInt8((n >> 16) & 0xff)] + command.bytes
        var out = [Data(header)]
        for s in stride(from: 0, to: n, by: chunkSize) {
            out.append(Data(data[s..<min(s + chunkSize, n)]))
        }
        return out
    }
}

/// Reassembles a response that may arrive as a header notification plus continuation chunks.
public struct ResponseAssembler {
    private var header: [UInt8]?
    private var payload: [UInt8] = []

    public init() {}

    public var isPartial: Bool { header != nil }

    /// Feed one notification. Returns a response once the declared payload length is reached.
    public mutating func feed(_ data: Data) -> Response? {
        let v = [UInt8](data)
        if header == nil {
            guard v.count >= Frame.headerSize else { return nil }
            header = Array(v[0..<Frame.headerSize])
            payload = Array(v.dropFirst(Frame.headerSize))
        } else {
            payload += v
        }
        return payload.count >= expected ? take() : nil
    }

    /// Emit whatever has been collected (used when the declared length never arrives).
    public mutating func flush() -> Response? { header == nil ? nil : take() }

    private var expected: Int {
        guard let h = header else { return 0 }
        return Int(h[1]) | Int(h[2]) << 8 | Int(h[3]) << 16
    }

    private mutating func take() -> Response {
        let h = header!
        // The firmware pads notifications with stale buffer bytes; keep only the declared length.
        let body = Array(payload.prefix(max(expected, 0)))
        let r = Response(txid: h[0], statusByte: h[7], payload: body, header: h)
        header = nil; payload = []
        return r
    }
}
