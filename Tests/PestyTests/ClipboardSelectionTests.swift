import XCTest
@testable import Pesty

@MainActor
final class ClipboardSelectionTests: XCTestCase {
    private func withStore(_ body: (ClipboardStore, [ClipItem]) -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesty-selection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(baseDirectory: directory)
        let items = (0..<4).map { ClipItem(type: .text, text: "Clip \($0)") }
        for item in items.reversed() { store.addCaptured(item) }
        body(store, items)
    }

    func testClickKeepsCardInPlaceAndArrowNavigationResumesScrolling() throws {
        try withStore { store, items in
            store.select(items[1].id)
            XCTAssertEqual(store.selectedID, items[1].id)
            XCTAssertTrue(store.selectionIsPointerDriven)

            store.moveSelection(by: 1)
            XCTAssertEqual(store.selectedID, items[2].id)
            XCTAssertFalse(store.selectionIsPointerDriven)
        }
    }

    func testModifiedClicksPreserveMultiSelectionWithoutScrolling() throws {
        try withStore { store, items in
            store.select(items[0].id)
            store.extendSelection(to: items[2].id)
            XCTAssertEqual(store.multiSelectedIDs, Set(items.prefix(3).map(\.id)))
            XCTAssertTrue(store.selectionIsPointerDriven)

            store.toggleSelection(items[1].id)
            XCTAssertEqual(store.multiSelectedIDs, Set([items[0].id, items[2].id]))
            XCTAssertTrue(store.selectionIsPointerDriven)

            store.moveSelection(by: 1)
            XCTAssertEqual(store.selectedID, items[3].id)
            XCTAssertTrue(store.multiSelectedIDs.isEmpty)
            XCTAssertFalse(store.selectionIsPointerDriven)
        }
    }

    func testProgrammaticSelectionResumesScrollingAfterClick() throws {
        try withStore { store, items in
            store.select(items[2].id)
            store.selectFirst()
            XCTAssertEqual(store.selectedID, items[0].id)
            XCTAssertFalse(store.selectionIsPointerDriven)

            store.select(items[3].id)
            store.selectedID = items[1].id
            XCTAssertFalse(store.selectionIsPointerDriven)
        }
    }
}
