import XCTest
import SwiftUI
@testable import Clipr

final class TextStyleSwiftUIHelpersTests: XCTestCase {
    func testTextAlignmentMapsEachCase() {
        XCTAssertEqual(swiftUITextAlignment(.left), .leading)
        XCTAssertEqual(swiftUITextAlignment(.center), .center)
        XCTAssertEqual(swiftUITextAlignment(.right), .trailing)
    }

    func testFrameAlignmentCombinesBothAxes() {
        XCTAssertEqual(swiftUIFrameAlignment(horizontal: .left, vertical: .top), .topLeading)
        XCTAssertEqual(swiftUIFrameAlignment(horizontal: .center, vertical: .middle), .center)
        XCTAssertEqual(swiftUIFrameAlignment(horizontal: .right, vertical: .bottom), .bottomTrailing)
    }
}
