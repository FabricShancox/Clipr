import SwiftUI

/// Dark palette lifted from the "Screenshot Editor Redesign" Claude Design project (Origin
/// Studio color tokens, dark theme) — kept as plain `Color` constants rather than an asset
/// catalog since the editor doesn't otherwise need one.
enum EditorColors {
    static let s0 = Color(red: 0x14 / 255.0, green: 0x1A / 255.0, blue: 0x21 / 255.0)
    static let s1 = Color(red: 0x1C / 255.0, green: 0x25 / 255.0, blue: 0x2E / 255.0)
    static let s2 = Color(red: 0x28 / 255.0, green: 0x32 / 255.0, blue: 0x3D / 255.0)
    static let t1 = Color.white
    static let t2 = Color(red: 0x91 / 255.0, green: 0x9E / 255.0, blue: 0xAB / 255.0)
    static let line = Color(red: 145 / 255.0, green: 158 / 255.0, blue: 171 / 255.0).opacity(0.16)
    static let accent = Color(red: 0x33 / 255.0, green: 0x99 / 255.0, blue: 0xFF / 255.0)
    static let accent12 = Color(red: 0x33 / 255.0, green: 0x99 / 255.0, blue: 0xFF / 255.0).opacity(0.12)
    static let success = Color(red: 0x4C / 255.0, green: 0xAF / 255.0, blue: 0x50 / 255.0)
}
