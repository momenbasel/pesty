import XCTest
@testable import Pesty

final class BarPresentationTests: XCTestCase {
    func testBottomDockDoesNotLiftPanelAndResizeKeepsBottomEdge() {
        let screen = CGRect(x: -1440, y: -900, width: 1440, height: 900)
        let visible = CGRect(x: -1440, y: -820, width: 1440, height: 796)
        let bounds = BarResizeGeometry.presentationBounds(screenFrame: screen, visibleFrame: visible)
        XCTAssertEqual(bounds, CGRect(x: -1440, y: -900, width: 1440, height: 876))
        let panel = BarResizeGeometry.panelFrame(for: 430, in: bounds)
        XCTAssertEqual(panel.minY, screen.minY)
        let resize = BarResizeSession(initialPanelHeight: panel.height,
                                      initialScreenY: panel.maxY, visibleFrame: bounds)
        XCTAssertEqual(resize.frame(atScreenY: panel.maxY + 100).minY, screen.minY)
        XCTAssertEqual(resize.frame(atScreenY: panel.maxY + 100).height, 530)
    }

    func testSideDockAndHiddenDockKeepFullWidthAndMenuBarClearance() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for visible in [CGRect(x: 80, y: 0, width: 1360, height: 876),
                        CGRect(x: 0, y: 0, width: 1360, height: 876),
                        CGRect(x: 0, y: 1, width: 1440, height: 875)] {
            XCTAssertEqual(BarResizeGeometry.presentationBounds(screenFrame: screen, visibleFrame: visible),
                           CGRect(x: 0, y: 0, width: 1440, height: 876))
        }
    }
}
