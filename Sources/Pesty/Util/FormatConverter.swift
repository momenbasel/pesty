import AppKit

/// Converts rich clips for the "Clean Formatting" and "Markdown" paste
/// options. HTML is preferred as the source when the clip carried it —
/// browser copies often have no RTF at all — with RTF as the fallback.
enum FormatConverter {
    /// Above this, skip rich conversion entirely and let the caller fall back
    /// to plain text. The HTML importer runs synchronously on the main thread
    /// at paste time; a pathological clip must not hitch the paste.
    private static let maxRichSourceBytes = 1_000_000

    static func canConvert(_ item: ClipItem) -> Bool {
        withinLimit(item.htmlData) || withinLimit(item.rtfData)
    }

    private static func withinLimit(_ data: Data?) -> Bool {
        guard let data else { return false }
        return !data.isEmpty && data.count <= maxRichSourceBytes
    }

    private static func attributed(for item: ClipItem) -> NSAttributedString? {
        // The importer loads no subresources, so the HTML goes in as captured;
        // the timeout only bounds the document load itself.
        if let html = item.htmlData, withinLimit(html),
           let s = NSAttributedString(html: html,
                                      options: [.timeout: 2.0],
                                      documentAttributes: nil) {
            return s
        }
        if let rtf = item.rtfData, withinLimit(rtf),
           let s = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            return s
        }
        return nil
    }

    /// Strips fonts, sizes, and colors while keeping the structure people
    /// mean when they say "formatting": bold, italic, underline,
    /// strikethrough, and links — everything else becomes the system font.
    static func cleanedRTF(for item: ClipItem) -> Data? {
        guard let source = attributed(for: item) else { return nil }
        let base = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let out = NSMutableAttributedString(string: source.string)
        let full = NSRange(location: 0, length: out.length)
        out.addAttribute(.font, value: base, range: full)

        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attrs, range, _ in
            if let font = attrs[.font] as? NSFont {
                var kept: NSFontDescriptor.SymbolicTraits = []
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.bold) { kept.insert(.bold) }
                if traits.contains(.italic) { kept.insert(.italic) }
                if !kept.isEmpty,
                   let styled = NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(kept),
                                       size: base.pointSize) {
                    out.addAttribute(.font, value: styled, range: range)
                }
            }
            if let underline = attrs[.underlineStyle] {
                out.addAttribute(.underlineStyle, value: underline, range: range)
            }
            if let strike = attrs[.strikethroughStyle] {
                out.addAttribute(.strikethroughStyle, value: strike, range: range)
            }
            if let link = attrs[.link] {
                out.addAttribute(.link, value: link, range: range)
            }
        }
        return out.rtf(from: full)
    }

    /// Walks the attributed runs producing Markdown for bold, italic, and
    /// links. Markers never wrap line breaks — each line segment inside a
    /// styled run is marked separately so the output stays valid Markdown.
    static func markdown(for item: ClipItem) -> String? {
        guard let source = attributed(for: item) else { return nil }
        var out = ""
        let text = source.string as NSString

        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attrs, range, _ in
            let chunk = text.substring(with: range)
            guard !chunk.isEmpty else { return }

            let traits = (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            var marker = ""
            if traits.contains(.bold) { marker += "**" }
            if traits.contains(.italic) { marker += "*" }
            let linkTarget: String? = (attrs[.link] as? URL)?.absoluteString
                ?? attrs[.link] as? String

            // Split on newlines, keeping empty segments so blank lines survive.
            let segments = chunk.components(separatedBy: "\n")
            for (index, segment) in segments.enumerated() {
                if index > 0 { out += "\n" }
                guard !segment.isEmpty else { continue }
                // Markers hug the visible text; whitespace stays outside them.
                let leading = segment.prefix(while: { $0 == " " || $0 == "\t" })
                let trailing = String(segment.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())
                let core = segment.dropFirst(leading.count).dropLast(trailing.count)
                guard !core.isEmpty else { out += segment; continue }

                var rendered = String(core)
                if let linkTarget, rendered.trimmingCharacters(in: .whitespaces) != linkTarget {
                    rendered = "[\(rendered)](\(linkTarget))"
                }
                if !marker.isEmpty {
                    rendered = "\(marker)\(rendered)\(String(marker.reversed()))"
                }
                out += String(leading) + rendered + trailing
            }
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
