import XCTest
@testable import Pesty

final class ClipUndoStackTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func placement(_ item: ClipItem, index: Int,
                           before predecessor: ClipItem? = nil,
                           after successor: ClipItem? = nil) -> ClipPlacement {
        ClipPlacement(container: .history, index: index, item: item,
                      predecessorID: predecessor?.id, successorID: successor?.id)
    }

    func testBulkDeletionComesBackAsOneEntryNewestFirst() {
        var stack = ClipUndoStack()
        let a = ClipItem(type: .text, text: "a")
        let b = ClipItem(type: .text, text: "b")
        let c = ClipItem(type: .text, text: "c")
        stack.push([placement(a, index: 0)], at: start)
        stack.push([placement(b, index: 1), placement(c, index: 2)], at: start.addingTimeInterval(1))

        let first = stack.pop(at: start.addingTimeInterval(2))
        XCTAssertEqual(first?.placements.map(\.item.id), [b.id, c.id])
        XCTAssertEqual(stack.pop(at: start.addingTimeInterval(2))?.placements.first?.item.id, a.id)
        XCTAssertNil(stack.pop(at: start.addingTimeInterval(2)))
        XCTAssertTrue(stack.isEmpty)
    }

    func testEntriesExpireAfterFiveMinutes() {
        var stack = ClipUndoStack()
        let item = ClipItem(type: .image, imageFileName: "shot.png")
        stack.push([placement(item, index: 0)], at: start)
        XCTAssertEqual(stack.nextExpiration, start.addingTimeInterval(300))
        XCTAssertTrue(stack.retainsImageFile(named: "shot.png"))

        XCTAssertTrue(stack.removeExpired(at: start.addingTimeInterval(299)).isEmpty)
        XCTAssertNil(stack.pop(at: start.addingTimeInterval(300)))
        let expired = stack.removeExpired(at: start.addingTimeInterval(300))
        XCTAssertEqual(expired.first?.placements.first?.item.id, item.id)
        XCTAssertFalse(stack.retainsImageFile(named: "shot.png"))
        XCTAssertNil(stack.nextExpiration)
    }

    func testRemoveAllHandsBackEverything() {
        var stack = ClipUndoStack()
        stack.push([placement(ClipItem(type: .text, text: "x"), index: 0)], at: start)
        stack.push([placement(ClipItem(type: .text, text: "y"), index: 0)], at: start)
        XCTAssertEqual(stack.removeAll().count, 2)
        XCTAssertTrue(stack.isEmpty)
    }

    func testRestorationIndexPrefersPredecessorThenSuccessorThenIndex() {
        let a = ClipItem(type: .text, text: "a")
        let b = ClipItem(type: .text, text: "b")
        let c = ClipItem(type: .text, text: "c")
        let gone = placement(b, index: 1, before: a, after: c)

        XCTAssertEqual(gone.restorationIndex(in: [a, c]), 1)
        XCTAssertEqual(gone.restorationIndex(in: [c, a]), 2)
        XCTAssertEqual(gone.restorationIndex(in: [c]), 0)
        XCTAssertEqual(gone.restorationIndex(in: []), 0)
        XCTAssertEqual(placement(b, index: 7).restorationIndex(in: [a, c]), 2)
    }
}
