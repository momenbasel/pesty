import XCTest
@testable import Pesty

final class ClipFilterTests: XCTestCase {
    private func item(_ type: ClipType,
                      text: String? = nil,
                      sourceAppName: String? = nil,
                      fileURLs: [String] = []) -> ClipItem {
        ClipItem(type: type, text: text, fileURLs: fileURLs, sourceAppName: sourceAppName)
    }

    private var mixed: [ClipItem] {
        [
            item(.text, text: "Notes about the github release"),
            item(.richText, text: "Formatted notes"),
            item(.link, text: "https://github.com/momenbasel/pesty"),
            item(.image, sourceAppName: "Screenshot"),
            item(.file, fileURLs: ["file:///tmp/Q3-Report.pdf"]),
            item(.color, text: "#5B8DEF"),
            item(.text, text: "Another note")
        ]
    }

    func testNilTypeKeepsEveryClipType() {
        XCTAssertEqual(ClipFilter.applying(type: nil, searchText: "", to: mixed).count, 7)
    }

    func testTypeFilterNarrowsToSingleTypeInOriginalOrder() {
        let result = ClipFilter.applying(type: .text, searchText: "", to: mixed)
        XCTAssertEqual(result.map(\.type), [.text, .text])
        XCTAssertEqual(result.map(\.text), ["Notes about the github release", "Another note"])
    }

    func testTypeFilterAppliesBeforeSearch() {
        // "github" matches a text clip and a link clip, but the type filter
        // must narrow first so only the link survives.
        XCTAssertEqual(ClipFilter.applying(type: nil, searchText: "github", to: mixed).count, 2)
        let result = ClipFilter.applying(type: .link, searchText: "github", to: mixed)
        XCTAssertEqual(result.map(\.type), [.link])
    }

    func testSearchRemainsTrimmedAndCaseInsensitiveWithinAType() {
        let result = ClipFilter.applying(type: .text, searchText: "  NOTES  ", to: mixed)
        XCTAssertEqual(result.map(\.text), ["Notes about the github release"])
    }

    func testSearchStillMatchesMetadataForTheFilteredType() {
        // File clips are findable by file name/extension, as before.
        let result = ClipFilter.applying(type: .file, searchText: "pdf", to: mixed)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.type, .file)
    }

    func testFilterAndSearchCanBothProduceNoResults() {
        XCTAssertTrue(ClipFilter.applying(type: .image, searchText: "notes", to: mixed).isEmpty)
        XCTAssertTrue(ClipFilter.applying(type: .text, searchText: "nothing-like-this", to: mixed).isEmpty)
        XCTAssertTrue(ClipFilter.applying(type: .color, searchText: "", to: []).isEmpty)
    }

    func testTypeCountsCountsEachClipType() {
        let counts = ClipFilter.typeCounts(in: mixed)
        XCTAssertEqual(counts[.text], 2)
        XCTAssertEqual(counts[.richText], 1)
        XCTAssertEqual(counts[.link], 1)
        XCTAssertEqual(counts[.image], 1)
        XCTAssertEqual(counts[.file], 1)
        XCTAssertEqual(counts[.color], 1)
        XCTAssertEqual(counts.count, ClipType.allCases.count)
    }

    func testTypeCountsOfEmptyCollectionIsEmpty() {
        XCTAssertTrue(ClipFilter.typeCounts(in: []).isEmpty)
        XCTAssertTrue(ClipFilter.availableTypes(in: []).isEmpty)
    }

    func testAvailableTypesPreserveCanonicalOrderAndSkipMissingTypes() {
        let items = [
            item(.color, text: "#FFFFFF"),
            item(.image),
            item(.color, text: "#000000")
        ]
        XCTAssertEqual(ClipFilter.availableTypes(in: items), [.image, .color])
    }

    func testNextTypeFilterWalksAllAvailableTypesThenWraps() {
        let available: [ClipType] = [.text, .image, .file]
        XCTAssertEqual(ClipFilter.nextTypeFilter(after: nil, available: available), .text)
        XCTAssertEqual(ClipFilter.nextTypeFilter(after: .text, available: available), .image)
        XCTAssertEqual(ClipFilter.nextTypeFilter(after: .image, available: available), .file)
        XCTAssertNil(ClipFilter.nextTypeFilter(after: .file, available: available))
    }

    func testNextTypeFilterSkipsTypesWithoutClips() {
        // .richText has no clips in this collection, so it is skipped.
        XCTAssertEqual(ClipFilter.nextTypeFilter(after: .text, available: [.text, .image]), .image)
    }

    func testNextTypeFilterRecoversWhenCurrentTypeIsNoLongerAvailable() {
        // The selected type's last clip was deleted while it was filtering.
        XCTAssertEqual(ClipFilter.nextTypeFilter(after: .color, available: [.text, .image]), .text)
    }

    func testNextTypeFilterWithoutAnyClipsIsAll() {
        XCTAssertNil(ClipFilter.nextTypeFilter(after: .text, available: []))
    }
}
