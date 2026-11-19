import AppKit

/// Turns a multi-clip selection into the pasteboard writes that deliver it.
///
/// Neighbouring clips that fit in one write are merged: text joins with a
/// line break and files become one file list, so each run is a single paste.
/// An image always stands alone. A result with more than one step has to be
/// pasted one step at a time, because no single pasteboard write carries
/// text and images in a form every app accepts.
enum ClipComposer {
    static let separator = "\n"

    private enum Kind {
        case text, file, image
    }

    /// A clip's text, with its formatting when it is to be kept.
    private struct Fragment {
        var text: String
        var rtf: Data?
    }

    /// The writes that deliver `items`, in order. The converting formats
    /// always produce one text step and leave out clips with no text form.
    static func steps(for items: [ClipItem], format: PasteFormat = .original) -> [ClipItem] {
        switch format {
        case .original:
            return originalSteps(for: items)
        case .plainText:
            return [textStep(items.compactMap { item in
                item.plainText.map { Fragment(text: $0) }
            })].compactMap { $0 }
        case .cleanFormatting:
            return [textStep(items.compactMap { item in
                item.plainText.map { Fragment(text: $0, rtf: FormatConverter.cleanedRTF(for: item)) }
            })].compactMap { $0 }
        case .markdown:
            return [textStep(items.compactMap { item in
                item.plainText.map { Fragment(text: FormatConverter.markdown(for: item) ?? $0) }
            })].compactMap { $0 }
        }
    }

    private static func kind(of item: ClipItem) -> Kind {
        switch item.type {
        case .text, .richText, .link, .color: return .text
        case .file: return .file
        case .image: return .image
        }
    }

    private static func originalSteps(for items: [ClipItem]) -> [ClipItem] {
        var runs: [(kind: Kind, items: [ClipItem])] = []
        for item in items {
            let kind = kind(of: item)
            if kind != .image, runs.last?.kind == kind {
                runs[runs.count - 1].items.append(item)
            } else {
                runs.append((kind, [item]))
            }
        }
        return runs.enumerated().compactMap { index, run in
            let follows = index > 0
            let precedes = index < runs.count - 1
            // A lone clip with nothing to join or separate goes out untouched.
            if run.items.count == 1, run.kind != .text || (!follows && !precedes) {
                return run.items[0]
            }
            switch run.kind {
            case .image:
                return run.items[0]
            case .file:
                return ClipItem(type: .file,
                                text: run.items.compactMap(\.text).joined(separator: ", "),
                                fileURLs: run.items.flatMap(\.fileURLs))
            case .text:
                // Pasted one after another, text would run straight into the
                // image or file next to it; a line break keeps them apart.
                return textStep(run.items.compactMap { item in
                    item.plainText.map { Fragment(text: $0, rtf: item.rtfData) }
                }, leadingBreak: follows, trailingBreak: precedes)
            }
        }
    }

    /// One text clip out of several. It stays plain unless a fragment brings
    /// formatting, in which case the plain fragments ride along in the
    /// system font.
    private static func textStep(_ fragments: [Fragment],
                                 leadingBreak: Bool = false,
                                 trailingBreak: Bool = false) -> ClipItem? {
        guard !fragments.isEmpty else { return nil }
        let text = (leadingBreak ? separator : "")
            + fragments.map(\.text).joined(separator: separator)
            + (trailingBreak ? separator : "")
        guard fragments.contains(where: { $0.rtf != nil }) else {
            return ClipItem(type: .text, text: text)
        }

        let plain: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        let lineBreak = NSAttributedString(string: separator, attributes: plain)
        let rich = NSMutableAttributedString()
        if leadingBreak { rich.append(lineBreak) }
        for (index, fragment) in fragments.enumerated() {
            if index > 0 { rich.append(lineBreak) }
            rich.append(fragment.rtf.flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }
                ?? NSAttributedString(string: fragment.text, attributes: plain))
        }
        if trailingBreak { rich.append(lineBreak) }
        return ClipItem(type: .richText,
                        text: text,
                        rtfData: rich.rtf(from: NSRange(location: 0, length: rich.length)))
    }
}
