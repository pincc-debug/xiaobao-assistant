import XCTest
import CoreGraphics
@testable import Assistant

/// 开始上课 card pickers open beside the card: right by default, left when the right side doesn't fit,
/// shifted inward vertically, never overlapping the card.
final class DropdownSidePlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let panel = CGSize(width: 280, height: 220)

    func testOpensOnTheRightByDefaultWithFirstRowLevelWithTrigger() {
        let card = CGRect(x: 400, y: 200, width: 320, height: 480)
        let r = DropdownSidePlacement.frame(card: card, rowMidY: 300, panelSize: panel, firstRowCenter: 43, screen: screen)
        XCTAssertFalse(r.left)
        XCTAssertEqual(r.frame.minX, card.maxX + 8)
        XCTAssertEqual(r.frame.maxY - 43, 300, "first row centre sits on the trigger row centre")
        XCTAssertFalse(r.frame.intersects(card))
    }

    func testFlipsLeftWhenTheRightSideDoesNotFit() {
        let card = CGRect(x: 1100, y: 200, width: 320, height: 480)
        let r = DropdownSidePlacement.frame(card: card, rowMidY: 300, panelSize: panel, firstRowCenter: 43, screen: screen)
        XCTAssertTrue(r.left)
        XCTAssertEqual(r.frame.maxX, card.minX - 8)
        XCTAssertFalse(r.frame.intersects(card))
    }

    func testExactFitOnTheRightStaysRight() {
        let card = CGRect(x: 1440 - 8 - 280 - 320, y: 200, width: 320, height: 480)
        let r = DropdownSidePlacement.frame(card: card, rowMidY: 300, panelSize: panel, firstRowCenter: 43, screen: screen)
        XCTAssertFalse(r.left)
        XCTAssertEqual(r.frame.maxX, screen.maxX)
    }

    func testClampsInsideTheBottomEdge() {
        let card = CGRect(x: 400, y: 0, width: 320, height: 480)
        let r = DropdownSidePlacement.frame(card: card, rowMidY: 40, panelSize: panel, firstRowCenter: 43, screen: screen)
        XCTAssertEqual(r.frame.minY, screen.minY)
        XCTAssertEqual(r.frame.height, panel.height)
    }

    func testClampsInsideTheTopEdge() {
        let card = CGRect(x: 400, y: 500, width: 320, height: 400)
        let r = DropdownSidePlacement.frame(card: card, rowMidY: 890, panelSize: panel, firstRowCenter: 43, screen: screen)
        XCTAssertEqual(r.frame.maxY, screen.maxY)
    }

    func testNeverOverlapsTheCardWhenNeitherSideFits() {
        let narrow = CGRect(x: 0, y: 0, width: 700, height: 900)
        let card = CGRect(x: 250, y: 200, width: 320, height: 480)
        let r = DropdownSidePlacement.frame(card: card, rowMidY: 300, panelSize: panel, firstRowCenter: 43, screen: narrow)
        XCTAssertTrue(r.left, "more room on the left (250) than on the right (130)")
        XCTAssertFalse(r.frame.intersects(card))
    }

    func testOffscreenOrUnknownScreenDefaultsRight() {
        let card = CGRect(x: -30000, y: -30000, width: 320, height: 480)
        let r = DropdownSidePlacement.frame(card: card, rowMidY: -29800, panelSize: panel, firstRowCenter: 43, screen: .infinite)
        XCTAssertFalse(r.left)
        XCTAssertEqual(r.frame.minX, card.maxX + 8)
    }

    /// 知识库 is row 2 of the settings group; its side panel's first row is levelled with that row, not row 3.
    func testKnowledgePanelAnchorsToSecondRow() throws {
        XCTAssertEqual(StartCard.rowOrder, ["课程", "知识库", "开播方式"])
        let kb = try XCTUnwrap(StartCard.rowCenter("知识库"))
        XCTAssertEqual(kb, 44 + 0.5 + 22)
        XCTAssertLessThan(kb, try XCTUnwrap(StartCard.rowCenter("开播方式")))
        let card = CGRect(x: 400, y: 200, width: 320, height: 480)
        let groupTop: CGFloat = 250   // distance from card top to the group (any value: the anchor is relative)
        let rowMidY = card.maxY - (groupTop + kb)
        let r = DropdownSidePlacement.frame(card: card, rowMidY: rowMidY, panelSize: panel, firstRowCenter: DropdownSidePlacement.headerHeight + 20, screen: screen)
        XCTAssertEqual(r.frame.maxY - (DropdownSidePlacement.headerHeight + 20), rowMidY, "panel first row centre == 知识库 row centre")
    }
}
