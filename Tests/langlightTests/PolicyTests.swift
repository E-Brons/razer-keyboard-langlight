import XCTest
@testable import langlight

final class PolicyTests: XCTestCase {
    let p = Palette()

    func testDefaultColors() {
        XCTAssertEqual(p.hebrew.description, "FFFF00")
        XCTAssertEqual(p.english.description, "FF00FF")
        XCTAssertEqual(p.englishCaps.description, "0000FF")
        XCTAssertEqual(p.other.description, "FF0000")
    }

    func testEveryCombination() {
        XCTAssertEqual(color(kind: .hebrew, capsLock: false), p.hebrew)
        XCTAssertEqual(color(kind: .hebrew, capsLock: true), p.hebrew)   // caps only matters for English
        XCTAssertEqual(color(kind: .english, capsLock: false), p.english)
        XCTAssertEqual(color(kind: .english, capsLock: true), p.englishCaps)
        XCTAssertEqual(color(kind: .other, capsLock: false), p.other)
        XCTAssertEqual(color(kind: .other, capsLock: true), p.other)
        XCTAssertEqual(color(kind: nil, capsLock: false), p.other)
        XCTAssertEqual(color(kind: nil, capsLock: true), p.other)
    }

    func testCustomPalette() {
        var q = Palette(); q.hebrew = RGB(1, 2, 3)
        XCTAssertEqual(color(kind: .hebrew, capsLock: false, palette: q), RGB(1, 2, 3))
    }

    func testClassify() {
        XCTAssertEqual(classify(id: "com.apple.keylayout.Hebrew", languages: ["he"]), .hebrew)
        XCTAssertEqual(classify(id: "x", languages: ["iw"]), .hebrew)
        XCTAssertEqual(classify(id: "com.apple.keylayout.Hebrew-QWERTY", languages: []), .hebrew)
        XCTAssertEqual(classify(id: "com.apple.keylayout.ABC", languages: ["en"]), .english)
        XCTAssertEqual(classify(id: "com.apple.keylayout.US", languages: ["en-US"]), .english)
        XCTAssertEqual(classify(id: "com.apple.keylayout.Russian", languages: ["ru"]), .other)
        XCTAssertNil(classify(id: nil, languages: []))
    }

    func testHexParsing() {
        XCTAssertEqual(RGB(hex: "#FF8000"), RGB(255, 128, 0))
        XCTAssertEqual(RGB(hex: "00ff7f"), RGB(0, 255, 127))
        XCTAssertNil(RGB(hex: "FFF"))
        XCTAssertNil(RGB(hex: "GGGGGG"))
    }

    func testLaunchAgentPlist() {
        let s = LaunchAgent.plist(executable: "/x/langlight", extraArgs: ["--he", "FFAA00"])
        XCTAssertTrue(s.contains("<string>local.langlight</string>"))
        XCTAssertTrue(s.contains("<string>/x/langlight</string>"))
        XCTAssertTrue(s.contains("<string>--he</string>"))
        XCTAssertTrue(s.contains("<key>KeepAlive</key><true/>"))
        XCTAssertNoThrow(try PropertyListSerialization.propertyList(from: Data(s.utf8), format: nil))
    }
}
