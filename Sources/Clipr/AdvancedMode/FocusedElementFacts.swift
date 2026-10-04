import CoreGraphics

/// What Accessibility said about the focused element when a typing burst was checked — read once
/// in `ClickDescriber`, decided on here, so the decision is a pure function that can be tested.
struct FocusedElementFacts: Equatable {
    /// The app that owns the element (and so receives the keys). Nil when it couldn't be found.
    var bundleID: String?
    var role: String?
    var subrole: String?
    /// Nil when the size couldn't be read.
    var size: CGSize?
    /// Web content only (`AXDOMClassList`); empty elsewhere.
    var domClassList: [String]
    /// Title/description/placeholder/help, as `ClickDescriber` reports it for the caption.
    var label: String?
    /// Any role/subrole read failed for a reason other than "unsupported" (timeout, invalid element…).
    var readFailed = false
}
