import XCTest
@testable import Pesty

@MainActor
final class ClipComposerTests: XCTestCase {
    private func boldRTF(_ string: String) -> Data {
        let attributed = NSAttributedString(
            string: string,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        return attributed.rtf(from: NSRange(location: 0, length: attributed.length))!
    }

    func testTextClipsJoinIntoOnePlainStep() {
        let steps = ClipComposer.steps(for: [
            ClipItem(type: .text, text: "first"),
            ClipItem(type: .link, text: "https://example.com"),
            ClipItem(type: .color, colorHex: "#5B8DEF")
        ])

        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps.first?.type, .text)
        XCTAssertEqual(steps.first?.text, "first\nhttps://example.com\n#5B8DEF")
        XCTAssertNil(steps.first?.rtfData)
    }

    func testFormattingSurvivesNextToPlainText() throws {
        let steps = ClipComposer.steps(for: [
            ClipItem(type: .richText, text: "bold", rtfData: boldRTF("bold")),
            ClipItem(type: .text, text: "plain")
        ])

        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps.first?.type, .richText)
        XCTAssertEqual(steps.first?.text, "bold\nplain")
        let rich = try XCTUnwrap(steps.first?.rtfData.flatMap {
            NSAttributedString(rtf: $0, documentAttributes: nil)
        })
        XCTAssertEqual(rich.string, "bold\nplain")
        let traits: (Int) -> NSFontDescriptor.SymbolicTraits = { index in
            (rich.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?
                .fontDescriptor.symbolicTraits ?? []
        }
        XCTAssertTrue(traits(0).contains(.bold))
        XCTAssertFalse(traits(5).contains(.bold))
    }

    func testMixedSelectionPastesInStepsWithTextSetApart() {
        let image = ClipItem(type: .image, imageFileName: "shot.png")
        let steps = ClipComposer.steps(for: [
            ClipItem(type: .text, text: "one"),
            ClipItem(type: .text, text: "two"),
            image,
            ClipItem(type: .text, text: "three")
        ])

        XCTAssertEqual(steps.map(\.type), [.text, .image, .text])
        XCTAssertEqual(steps[0].text, "one\ntwo\n")
        XCTAssertEqual(steps[1], image)
        XCTAssertEqual(steps[2].text, "\nthree")
    }

    func testImagesNeverMerge() {
        let first = ClipItem(type: .image, imageFileName: "a.png")
        let second = ClipItem(type: .image, imageFileName: "b.png")

        XCTAssertEqual(ClipComposer.steps(for: [first, second]), [first, second])
    }

    func testNeighbouringFilesBecomeOneFileList() {
        let report = ClipItem(type: .file, text: "report.pdf", fileURLs: ["file:///tmp/report.pdf"])
        let notes = ClipItem(type: .file, text: "notes.txt", fileURLs: ["file:///tmp/notes.txt"])
        let image = ClipItem(type: .image, imageFileName: "shot.png")

        let together = ClipComposer.steps(for: [report, notes])
        XCTAssertEqual(together.count, 1)
        XCTAssertEqual(together.first?.type, .file)
        XCTAssertEqual(together.first?.fileURLs, ["file:///tmp/report.pdf", "file:///tmp/notes.txt"])
        XCTAssertEqual(together.first?.text, "report.pdf, notes.txt")

        XCTAssertEqual(ClipComposer.steps(for: [report, image, notes]), [report, image, notes])
    }

    func testPlainTextKeepsOnlyWhatHasText() {
        let items = [
            ClipItem(type: .richText, text: "bold", rtfData: boldRTF("bold")),
            ClipItem(type: .image, imageFileName: "shot.png"),
            ClipItem(type: .file, text: "report.pdf", fileURLs: ["file:///tmp/report.pdf"])
        ]

        let steps = ClipComposer.steps(for: items, format: .plainText)
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps.first?.type, .text)
        XCTAssertEqual(steps.first?.text, "bold\n/tmp/report.pdf")
        XCTAssertNil(steps.first?.rtfData)

        let images = [ClipItem(type: .image, imageFileName: "a.png"),
                      ClipItem(type: .image, imageFileName: "b.png")]
        XCTAssertTrue(ClipComposer.steps(for: images, format: .plainText).isEmpty)
    }

    func testMarkdownConvertsEachClipAndFallsBackToItsText() {
        let steps = ClipComposer.steps(for: [
            ClipItem(type: .richText, text: "bold", rtfData: boldRTF("bold")),
            ClipItem(type: .text, text: "plain")
        ], format: .markdown)

        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps.first?.text, "**bold**\nplain")
    }

    func testSeveralStepsAreCopiedAsSeparatePasteboardItems() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("pesty.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let steps = [
            ClipItem(type: .text, text: "caption\n"),
            ClipItem(type: .file, text: "report.pdf", fileURLs: ["file:///tmp/report.pdf"])
        ]

        let before = pasteboard.changeCount
        XCTAssertNotEqual(PasteService.copy(steps, to: pasteboard), before)

        let items = pasteboard.pasteboardItems ?? []
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.string(forType: .string), "caption\n")
        XCTAssertEqual(items.last?.string(forType: .fileURL), "file:///tmp/report.pdf")
    }

    func testOneStepIsCopiedLikeAnyOtherClip() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("pesty.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let steps = ClipComposer.steps(for: [
            ClipItem(type: .text, text: "one"),
            ClipItem(type: .text, text: "two")
        ])

        PasteService.copy(steps, to: pasteboard)

        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "one\ntwo")
    }
}
