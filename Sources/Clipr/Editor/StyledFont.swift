import Cocoa

/// Bold/italic composed via `NSFontManager` symbolic traits on top of the system font, rather
/// than hardcoding a specific bold/italic font name — keeps this in sync with whatever the
/// regular-weight system font actually is.
func styledFont(_ style: TextStyle) -> NSFont {
    let base = NSFont.systemFont(ofSize: max(style.fontSize, 6))
    var traits: NSFontTraitMask = []
    if style.bold { traits.insert(.boldFontMask) }
    if style.italic { traits.insert(.italicFontMask) }
    guard traits != [] else { return base }
    return NSFontManager.shared.convert(base, toHaveTrait: traits)
}
