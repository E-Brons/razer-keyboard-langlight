import Foundation

public enum DeviceError: Error, CustomStringConvertible, Equatable {
    case notConnected
    case disconnected
    case timeout
    case busy
    case status(UInt8)

    public var description: String {
        switch self {
        case .notConnected: return "keyboard not connected"
        case .disconnected: return "link lost while request was pending"
        case .timeout: return "no response from keyboard"
        case .busy: return "keyboard busy"
        case .status(let s): return "keyboard replied: \(Status(rawValue: s)?.description ?? "status \(s)")"
        }
    }
}

public enum DeviceEvent {
    case connected
    case disconnected
    /// A notification that did not match the request in flight.
    case notification(Response)
}

/// Request/response layer over a Transport. Requests are queued and sent one at a time.
@MainActor
public final class RazerDevice {
    public var timeout: TimeInterval = 2
    /// How often a "busy" reply is retried before giving up.
    public var busyRetries = 3
    public var busyDelay: TimeInterval = 0.2
    /// Wait for continuation chunks of a response this long before delivering what we have.
    public var partialFlushDelay: TimeInterval = 0.1

    private let transport: Transport
    private var txid: UInt8 = 0x40
    private var queue: [Request] = []
    private var inflight: Request?
    private var assembler = ResponseAssembler()
    private var handlers: [Int: (DeviceEvent) -> Void] = [:]
    private var nextToken = 0

    private final class Request {
        let command: Command, data: [UInt8]
        let continuation: CheckedContinuation<Response, Error>
        var txid: UInt8 = 0
        var attempts = 0
        init(_ c: Command, _ d: [UInt8], _ k: CheckedContinuation<Response, Error>) {
            command = c; data = d; continuation = k
        }
    }

    public init(transport: Transport) {
        self.transport = transport
        transport.onReadyChanged = { [weak self] ready in
            MainActor.assumeIsolated { self?.readyChanged(ready) }
        }
        transport.onNotify = { [weak self] data in
            MainActor.assumeIsolated { self?.received(data) }
        }
    }

    public var isConnected: Bool { transport.isReady }

    public func connect() { transport.start() }

    public func disconnect() {
        transport.stop()
        failAll(.disconnected)
    }

    /// Subscribe to connection and notification events. Returns a token for `unregister`.
    @discardableResult
    public func register(_ handler: @escaping (DeviceEvent) -> Void) -> Int {
        nextToken += 1
        handlers[nextToken] = handler
        return nextToken
    }

    public func unregister(_ token: Int) { handlers[token] = nil }

    /// Suspend until the link is up, or throw `.timeout`.
    public func waitReady(timeout: TimeInterval) async throws {
        if isConnected { return }
        let deadline = Date().addingTimeInterval(timeout)
        while !isConnected {
            if Date() > deadline { throw DeviceError.timeout }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: requests

    /// Send a command and return the reply; throws unless the status is ok.
    @discardableResult
    public func write(_ command: Command, _ data: [UInt8] = []) async throws -> Response {
        let r = try await raw(command, data)
        guard r.isOK else { throw r.status == .busy ? DeviceError.busy : DeviceError.status(r.statusByte) }
        return r
    }

    /// Send a command and return the reply whatever its status.
    public func raw(_ command: Command, _ data: [UInt8] = []) async throws -> Response {
        guard transport.isReady else { throw DeviceError.notConnected }
        return try await withCheckedThrowingContinuation { k in
            queue.append(Request(command, data, k))
            pump()
        }
    }

    /// Run a getter and return its payload bytes.
    public func read(_ command: Command) async throws -> [UInt8] {
        try await write(command).payload
    }

    public func setStaticColor(r: UInt8, g: UInt8, b: UInt8) async throws {
        try await write(.setEffect, [0x01, 0x00, 0x00, 0x01, r, g, b])
    }

    /// Current effect as raw payload bytes (layout not fully decoded; see docs/protocol.md).
    public func getEffect() async throws -> [UInt8] { try await read(.get83) }

    // MARK: internals

    private func pump() {
        guard inflight == nil, !queue.isEmpty else { return }
        send(queue.removeFirst())
    }

    private func send(_ req: Request) {
        txid = txid &+ 1
        req.txid = txid
        req.attempts += 1
        inflight = req
        assembler = ResponseAssembler()
        do {
            try transport.write(Frame.encode(txid: req.txid, command: req.command, data: req.data))
        } catch {
            finish(req, .failure(error))
            return
        }
        let id = req.txid
        after(timeout) { [weak self] in
            guard let self, let cur = self.inflight, cur === req, cur.txid == id else { return }
            self.finish(cur, .failure(DeviceError.timeout))
        }
    }

    private func finish(_ req: Request, _ result: Result<Response, Error>) {
        if inflight === req { inflight = nil }
        assembler = ResponseAssembler()
        req.continuation.resume(with: result)
        pump()
    }

    private func received(_ data: Data) {
        let wasPartial = assembler.isPartial
        if let resp = assembler.feed(data) {
            deliver(resp)
        } else if assembler.isPartial && !wasPartial {
            after(partialFlushDelay) { [weak self] in
                if let resp = self?.assembler.flush() { self?.deliver(resp) }
            }
        }
    }

    private func deliver(_ resp: Response) {
        guard let req = inflight, req.txid == resp.txid else {
            emit(.notification(resp))
            return
        }
        if resp.status == .busy && req.attempts <= busyRetries {
            inflight = nil
            after(busyDelay) { [weak self] in
                guard let self else { return }
                self.queue.insert(req, at: 0)
                self.pump()
            }
            return
        }
        finish(req, .success(resp))
    }

    private func readyChanged(_ ready: Bool) {
        if ready {
            emit(.connected)
        } else {
            failAll(.disconnected)
            emit(.disconnected)
        }
    }

    private func failAll(_ error: DeviceError) {
        let pending = (inflight.map { [$0] } ?? []) + queue
        inflight = nil; queue = []
        assembler = ResponseAssembler()
        for r in pending { r.continuation.resume(throwing: error) }
    }

    private func emit(_ e: DeviceEvent) {
        for h in handlers.values { h(e) }
    }

    private func after(_ s: TimeInterval, _ f: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { MainActor.assumeIsolated(f) }
    }
}
