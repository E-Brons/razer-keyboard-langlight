import Foundation

public struct RGB: Equatable, CustomStringConvertible {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    public init?(hex s: String) {
        let h = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff))
    }

    public var description: String { String(format: "%02X%02X%02X", r, g, b) }
}

/// What the current input source is, as far as colors are concerned.
public enum InputKind: Equatable {
    case hebrew, english, other
}

/// Colors per rule; defaults match the project spec.
public struct Palette: Equatable {
    public var hebrew = RGB(0x00, 0xff, 0x00)      // A: green
    public var english = RGB(0xff, 0x00, 0x80)     // B: magenta (blue channel reduced; the LEDs render FF00FF as blue)
    public var englishCaps = RGB(0x00, 0x00, 0xff) // C: blue
    public var other = RGB(0xff, 0x00, 0x00)       // D: red
    public init() {}
}

/// Pure color rule. `kind == nil` means the input-source query failed.
public func color(kind: InputKind?, capsLock: Bool, palette: Palette = Palette()) -> RGB {
    switch kind {
    case .hebrew?: return palette.hebrew
    case .english?: return capsLock ? palette.englishCaps : palette.english
    case .other?, nil: return palette.other
    }
}

/// Classify an input source from its ID and language list.
public func classify(id: String?, languages: [String]) -> InputKind? {
    guard id != nil || !languages.isEmpty else { return nil }
    let lang = languages.first?.lowercased() ?? ""
    if lang.hasPrefix("he") || lang.hasPrefix("iw") || (id?.localizedCaseInsensitiveContains("hebrew") ?? false) {
        return .hebrew
    }
    if lang.hasPrefix("en") { return .english }
    return .other
}
