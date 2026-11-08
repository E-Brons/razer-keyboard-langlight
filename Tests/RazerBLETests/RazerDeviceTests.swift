import XCTest
@testable import RazerBLE

final class FakeTransport: Transport {
    var isReady = true
    var onReadyChanged: ((Bool) -> Void)?
    var onNotify: ((Data) -> Void)?
    var written: [[Data]] = []
    var autoReply: ((UInt8) -> Data)?
    var autoReplies: ((UInt8) -> [Data])?
    var failWrites = false
    func start() {}
    func stop() {}

    func write(_ chunks: [Data]) throws {
        if failWrites { throw DeviceError.notConnected }
        written.append(chunks)
        let txid = chunks[0][chunks[0].startIndex]
        if let replies = autoReplies?(txid) ?? autoReply.map({ [$0(txid)] }) {
            DispatchQueue.main.async { replies.forEach { self.onNotify?($0) } }
        }
    }

    static func reply(_ txid: UInt8, status: UInt8 = 2, payload: [UInt8] = []) -> Data {
        Data([txid, UInt8(payload.count), 0, 0, 0, 0, 0, status] + payload)
    }
}

@MainActor
final class RazerDeviceTests: XCTestCase {
    func make(timeout: TimeInterval = 0.3) -> (RazerDevice, FakeTransport) {
        let t = FakeTransport()
        let d = RazerDevice(transport: t)
        d.timeout = timeout
        d.busyDelay = 0.01
        return (d, t)
    }

    func testSetStaticColorWritesExpectedBytes() async throws {
        let (d, t) = make()
        t.autoReply = { FakeTransport.reply($0) }
        try await d.setStaticColor(r: 1, g: 2, b: 3)
        XCTAssertEqual(t.written.count, 1)
        XCTAssertEqual([UInt8](t.written[0][1]), [1, 0, 0, 1, 1, 2, 3])
        XCTAssertEqual(Array([UInt8](t.written[0][0])[4...]), [0x10, 3, 1, 0])
    }

    func testReadReturnsPayload() async throws {
        let (d, t) = make()
        t.autoReply = { FakeTransport.reply($0, payload: [9, 8]) }
        let p = try await d.read(.get85)
        XCTAssertEqual(p, [9, 8])
    }

    func testErrorStatusThrows() async {
        let (d, t) = make()
        t.autoReply = { FakeTransport.reply($0, status: 7) }
        do { try await d.write(.setEffect); XCTFail() } catch {
            XCTAssertEqual(error as? DeviceError, .status(7))
        }
    }

    func testRawReturnsNonOKWithoutThrowing() async throws {
        let (d, t) = make()
        t.autoReply = { FakeTransport.reply($0, status: 5) }
        let r = try await d.raw(.setEffect)
        XCTAssertEqual(r.status, .notSupported)
    }

    func testTimeout() async {
        let (d, _) = make(timeout: 0.05)
        do { _ = try await d.raw(.get80); XCTFail() } catch {
            XCTAssertEqual(error as? DeviceError, .timeout)
        }
    }

    func testNotConnectedThrowsImmediately() async {
        let (d, t) = make()
        t.isReady = false
        do { _ = try await d.raw(.get80); XCTFail() } catch {
            XCTAssertEqual(error as? DeviceError, .notConnected)
        }
    }

    func testBusyIsRetriedThenSucceeds() async throws {
        let (d, t) = make()
        var calls = 0
        t.autoReply = { calls += 1; return FakeTransport.reply($0, status: calls < 3 ? 1 : 2) }
        try await d.write(.setEffect)
        XCTAssertEqual(calls, 3)
    }

    func testBusyGivesUpAfterRetries() async {
        let (d, t) = make()
        d.busyRetries = 1
        t.autoReply = { FakeTransport.reply($0, status: 1) }
        do { try await d.write(.setEffect); XCTFail() } catch {
            XCTAssertEqual(error as? DeviceError, .busy)
        }
    }

    func testRequestsAreSerialized() async throws {
        let (d, t) = make()
        // Reply only after both writes could have been issued; the second must not be sent before the first reply.
        var maxOutstanding = 0, outstanding = 0
        t.autoReply = { txid in
            outstanding += 1; maxOutstanding = max(maxOutstanding, outstanding)
            outstanding -= 1
            return FakeTransport.reply(txid)
        }
        async let a: Response = d.write(.setEffect, [1])
        async let b: Response = d.write(.setEffect, [2])
        _ = try await (a, b)
        XCTAssertEqual(t.written.count, 2)
        XCTAssertEqual(maxOutstanding, 1)
        XCTAssertEqual([UInt8](t.written[0][1]), [1])
        XCTAssertEqual([UInt8](t.written[1][1]), [2])
    }

    func testDisconnectFailsPendingRequests() async {
        let (d, t) = make(timeout: 2)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            t.onReadyChanged?(false)
        }
        do { _ = try await d.raw(.get80); XCTFail() } catch {
            XCTAssertEqual(error as? DeviceError, .disconnected)
        }
    }

    func testEventsReachHandlers() async throws {
        let (d, t) = make()
        var events: [String] = []
        let token = d.register { e in
            switch e {
            case .connected: events.append("up")
            case .disconnected: events.append("down")
            case .notification(let r): events.append("n\(r.txid)")
            }
        }
        t.onReadyChanged?(true)
        t.onReadyChanged?(false)
        t.onNotify?(FakeTransport.reply(0x7f))   // unsolicited
        d.unregister(token)
        t.onReadyChanged?(true)
        XCTAssertEqual(events, ["up", "down", "n127"])
    }

    func testUnsolicitedDoesNotCompleteInflight() async throws {
        let (d, t) = make()
        var n = 0
        d.register { if case .notification = $0 { n += 1 } }
        t.autoReplies = { txid in [FakeTransport.reply(txid &+ 50), FakeTransport.reply(txid)] }
        try await d.write(.setEffect)
        XCTAssertEqual(n, 1)
    }

    func testWriteFailureSurfaces() async {
        let (d, t) = make()
        t.failWrites = true
        do { try await d.write(.setEffect); XCTFail() } catch {
            XCTAssertEqual(error as? DeviceError, .notConnected)
        }
    }

    func testSplitResponseReassembledByDevice() async throws {
        let (d, t) = make()
        t.autoReplies = { txid in [Data([txid, 3, 0, 0, 0, 0, 0, 2, 1]), Data([2, 3])] }
        let p = try await d.read(.get82)
        XCTAssertEqual(p, [1, 2, 3])
    }
}
