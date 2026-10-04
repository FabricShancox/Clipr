import Foundation

/// What Accessibility reported under a click, reduced to the fields captions need.
struct ClickTarget: Equatable {
    var role: String?
    var subrole: String?
    var label: String?
    /// For menu items: titles from the menu bar item down to the clicked item.
    var menuPath: [String] = []
}
