import XCTest
@testable import Pesty

@MainActor
final class KeyboardSelectionTests: XCTestCase {
    /// A store on a scratch directory holding five clips, with the bar just
    /// presented: `clips` is in strip order and the first one is selected.
    private func makeStore() -> (store: ClipboardStore, clips: [ClipItem]) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PestyTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let store = ClipboardStore(baseDirectory: directory)
        let clips = ["a", "b", "c", "d", "e"].map { ClipItem(type: .text, text: $0) }
        for clip in clips.reversed() { store.addCaptured(clip) }
        store.prepareForBarPresentation()
        return (store, clips)
    }

    private func ids(_ clips: ArraySlice<ClipItem>) -> Set<UUID> {
        Set(clips.map(\.id))
    }

    func testShiftArrowGrowsThenShrinksBackToTheAnchor() {
        let (store, clips) = makeStore()

        store.extendSelection(by: 1)
        XCTAssertEqual(store.multiSelectedIDs, ids(clips[0...1]))
        store.extendSelection(by: 1)
        XCTAssertEqual(store.multiSelectedIDs, ids(clips[0...2]))
        XCTAssertEqual(store.selectedID, clips[2].id)

        store.extendSelection(by: -1)
        XCTAssertEqual(store.multiSelectedIDs, ids(clips[0...1]))
        store.extendSelection(by: -1)
        XCTAssertTrue(store.multiSelectedIDs.isEmpty)
        XCTAssertEqual(store.effectiveSelectionIDs, [clips[0].id])
    }

    func testShiftArrowCrossesTheAnchor() {
        let (store, clips) = makeStore()
        store.moveSelection(by: 2)

        store.extendSelection(by: -1)
        XCTAssertEqual(store.multiSelectedIDs, ids(clips[1...2]))
        store.extendSelection(by: 1)
        XCTAssertTrue(store.multiSelectedIDs.isEmpty)
        XCTAssertEqual(store.selectedID, clips[2].id)
        store.extendSelection(by: 1)
        XCTAssertEqual(store.multiSelectedIDs, ids(clips[2...3]))
    }

    func testShiftArrowStopsAtTheEndsOfTheStrip() {
        let (store, clips) = makeStore()

        store.extendSelection(by: -1)
        XCTAssertTrue(store.multiSelectedIDs.isEmpty)
        XCTAssertEqual(store.selectedID, clips[0].id)

        for _ in 0..<10 { store.extendSelection(by: 1) }
        XCTAssertEqual(store.multiSelectedIDs, ids(clips[0...4]))
        XCTAssertEqual(store.selectedID, clips[4].id)
    }

    func testPlainArrowReturnsToASingleSelection() {
        let (store, clips) = makeStore()
        store.extendSelection(by: 1)
        store.extendSelection(by: 1)

        store.moveSelection(by: 1)
        XCTAssertTrue(store.multiSelectedIDs.isEmpty)
        XCTAssertEqual(store.selectedID, clips[3].id)

        // The clip the arrow landed on is the new anchor.
        store.extendSelection(by: -1)
        XCTAssertEqual(store.multiSelectedIDs, ids(clips[2...3]))
    }

    func testAnchorStartsOverWhenTheBarIsPresentedAgain() {
        let (store, clips) = makeStore()
        store.moveSelection(by: 3)

        store.prepareForBarPresentation()
        store.extendSelection(by: 1)
        XCTAssertEqual(store.multiSelectedIDs, ids(clips[0...1]))
    }

    func testSelectedItemsComeInStripOrderNotClickOrder() {
        let (store, clips) = makeStore()

        store.toggleSelection(clips[3].id)
        store.toggleSelection(clips[1].id)
        XCTAssertEqual(store.selectedItems.map(\.id), [clips[0].id, clips[1].id, clips[3].id])

        store.clearMultiSelection()
        XCTAssertEqual(store.selectedItems.map(\.id), [clips[1].id])
    }

    func testPromotingASelectionKeepsItsOrderAtTheFront() {
        let (store, clips) = makeStore()

        store.promoteCopiedItems([clips[2], clips[4]])
        XCTAssertEqual(store.history.map(\.text), ["c", "e", "a", "b", "d"])
    }
}
