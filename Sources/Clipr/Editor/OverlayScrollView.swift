import SwiftUI

/// A vertically-scrolling, fixed-width container whose scrollbar always uses the "overlay"
/// style (thin, floats over content, auto-hides when not actively scrolling) — regardless of
/// the user's system-wide "Show scroll bars" preference. A plain SwiftUI `ScrollView` +
/// `.scrollIndicators(.hidden)` doesn't override that preference — it controls the underlying
/// NSScrollView's scroller style directly, underneath whatever the SwiftUI modifier does; this
/// sets that style explicitly on its own NSScrollView instance, which does override it.
struct OverlayScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hosting
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        ])
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        (scrollView.documentView as? NSHostingView<Content>)?.rootView = content
    }
}
