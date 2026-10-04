import XCTest
import AppKit
@testable import Clipr

@MainActor
final class ReviewRowMenuTests: XCTestCase {
    private func actions(readOnly: Bool = false, inEditor: Bool = false, log: @escaping (String) -> Void = { _ in }) -> NSMenu {
        RowMenu.makeMenu(RowMenu.imageActions(
            isReadOnly: readOnly, isInEditor: inEditor,
            onEdit: { log("edit") }, onRetake: { log("retake") }, onReplace: { log("replace") }
        ))
    }

    /// What choosing the item does: its own target/action (`performActionForItem` needs a running app).
    private func choose(_ item: NSMenuItem) {
        _ = (item.target as AnyObject?)?.perform(item.action, with: item)
    }

    func testImageActionsOrderAndTitles() {
        let menu = actions()
        XCTAssertEqual(menu.items.map(\.title), ["Edit Image…", "", "Retake Screenshot…", "Replace with File…"])
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertFalse(menu.autoenablesItems, "enabled state comes from the rules, not the responder chain")
        XCTAssertTrue(menu.items.filter { !$0.isSeparatorItem }.allSatisfy(\.isEnabled))
    }

    func testRetakeAndReplaceDisabledWhenReadOnlyOrInEditor() {
        for menu in [actions(readOnly: true), actions(inEditor: true)] {
            XCTAssertTrue(menu.items[0].isEnabled, "the editor can always be opened")
            XCTAssertFalse(menu.items[2].isEnabled)
            XCTAssertFalse(menu.items[3].isEnabled)
        }
    }

    func testItemsRunTheirActions() {
        var calls: [String] = []
        let menu = actions { calls.append($0) }
        for index in [0, 2, 3] { choose(menu.items[index]) }
        XCTAssertEqual(calls, ["edit", "retake", "replace"])
    }

    func testSizesCheckCurrentAndSet() {
        var chosen: ImageSize?
        let menu = RowMenu.makeMenu(RowMenu.sizes(current: .medium, isReadOnly: false) { chosen = $0 })
        XCTAssertEqual(menu.items.map(\.title), ["Small", "Medium", "Large", "Full"])
        XCTAssertEqual(menu.items.map(\.state), [.off, .on, .off, .off])
        choose(menu.items[2])
        XCTAssertEqual(chosen, .large)
    }

    func testSizesDisabledWhenReadOnly() {
        let menu = RowMenu.makeMenu(RowMenu.sizes(current: .full, isReadOnly: true) { _ in })
        XCTAssertTrue(menu.items.allSatisfy { !$0.isEnabled })
    }

    func testSubmenu() {
        let menu = RowMenu.makeMenu([.submenu("Image Size", enabled: true, RowMenu.sizes(current: .full, isReadOnly: false) { _ in })])
        XCTAssertEqual(menu.items.first?.title, "Image Size")
        XCTAssertEqual(menu.items.first?.submenu?.items.count, 4)
    }
}
