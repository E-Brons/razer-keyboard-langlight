import XCTest
@testable import RazerBLE

final class FrameTests: XCTestCase {
    func testEncodeStaticColor() {
        let chunks = Frame.encode(txid: 0x41, command: .setEffect, data: [1, 0, 0, 1, 0xff, 0x00, 0x80])
        XCTAssertEqual(chunks.map { [UInt8]($0) }, [
            [0x41, 0x07, 0x00, 0x00, 0x10, 0x03, 0x01, 0x00],
            [1, 0, 0, 1, 0xff, 0x00, 0x80],
        ])
    }

    func testEncodeNoPayloadIsHeaderOnly() {
        XCTAssertEqual(Frame.encode(txid: 1, command: .get85, data: []).count, 1)
    }

    func testPayloadSplitInto20ByteChunks() {
        let chunks = Frame.encode(txid: 1, command: .setEffect, data: [UInt8](repeating: 7, count: 45))
        XCTAssertEqual(chunks.map(\.count), [8, 20, 20, 5])
        XCTAssertEqual([UInt8](chunks[0])[1], 45)
    }

    func testLengthIsThreeBytesLE() {
        let h = [UInt8](Frame.encode(txid: 1, command: .setEffect, data: [UInt8](repeating: 0, count: 300))[0])
        XCTAssertEqual(Array(h[1...3]), [0x2c, 0x01, 0x00])
    }

    func testCommandFromBytes() {
        XCTAssertEqual(Command(bytes: [0x10, 3, 1, 0]), .setEffect)
        XCTAssertNil(Command(bytes: [1, 2, 3]))
    }

    func testStatusNames() {
        XCTAssertEqual(Status(rawValue: 2), .ok)
        XCTAssertEqual(Status.targetNotSupported.description, "target not supported")
        XCTAssertNil(Status(rawValue: 99))
    }
}

final class AssemblerTests: XCTestCase {
    func testSingleNotificationNoPayload() {
        var a = ResponseAssembler()
        let r = a.feed(Data([0x41, 0, 0, 0, 0, 0, 0, 2]))
        XCTAssertEqual(r?.txid, 0x41)
        XCTAssertEqual(r?.status, .ok)
        XCTAssertEqual(r?.payload, [])
    }

    func testStalePaddingTruncatedToDeclaredLength() {
        var a = ResponseAssembler()
        let r = a.feed(Data([0x43, 0x04, 0, 0, 0, 0, 0, 2, 0x37, 0x32, 0x30, 0x31, 0x39, 0x34]))
        XCTAssertEqual(r?.payload, [0x37, 0x32, 0x30, 0x31])
    }

    func testContinuationChunks() {
        var a = ResponseAssembler()
        XCTAssertNil(a.feed(Data([9, 0x05, 0, 0, 0, 0, 0, 2, 1, 2])))
        XCTAssertTrue(a.isPartial)
        let r = a.feed(Data([3, 4, 5]))
        XCTAssertEqual(r?.payload, [1, 2, 3, 4, 5])
        XCTAssertFalse(a.isPartial)
    }

    func testShortFragmentWithoutHeaderIgnored() {
        var a = ResponseAssembler()
        XCTAssertNil(a.feed(Data([1, 2, 3])))
        XCTAssertFalse(a.isPartial)
    }

    func testFlushDeliversPartial() {
        var a = ResponseAssembler()
        _ = a.feed(Data([9, 0x05, 0, 0, 0, 0, 0, 2, 1]))
        XCTAssertEqual(a.flush()?.payload, [1])
        XCTAssertNil(a.flush())
    }

    func testStatusByteKept() {
        var a = ResponseAssembler()
        let r = a.feed(Data([1, 0, 0, 0, 0, 0, 0, 7]))
        XCTAssertEqual(r?.status, .targetNotSupported)
        XCTAssertFalse(r!.isOK)
    }
}
