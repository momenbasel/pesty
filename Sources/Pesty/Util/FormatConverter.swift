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

    /// Removes every element that could make the HTML importer touch the
    /// network. `NSAttributedString(html:)` is WebKit-backed and will fetch
    /// remote subresources — `<img src="http...">` tracking pixels included —
    /// synchronously, on the main thread, at paste time. That would break the
    /// app's no-network-calls promise and stall the paste, so the offending
    /// elements are dropped wholesale before conversion: the converters only
    /// keep text plus bold/italic/underline/links, and images, scripts, and
    /// stylesheets aren't representable in the output anyway.
    private static func sanitizedHTML(_ data: Data) -> Data? {
        guard let raw = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16) else { return nil }
        var html = raw

        func drop(_ pattern: String) {
            html = html.replacingOccurrences(of: pattern, with: "",
                                             options: [.regularExpression, .caseInsensitive])
        }

        // Container elements go with their entire contents…
        for tag in ["script", "style", "iframe", "object", "picture", "svg", "video", "audio"] {
            drop("<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)\\s*>")
            // …and any unbalanced leftovers of the same tags.
            drop("<\(tag)\\b[^>]*/?>")
            drop("</\(tag)\\s*>")
        }
        // Void/self-closing elements that reference external resources.
        for tag in ["img", "source", "embed", "link"] {
            drop("<\(tag)\\b[^>]*/?>")
        }
        // Neutralize CSS url(...) in surviving style attributes
        // (background images are fetched too).
        html = html.replacingOccurrences(of: "url\\s*\\([^)]*\\)", with: "none",
                                         options: [.regularExpression, .caseInsensitive])
        return html.data(using: .utf8)
    }

    private static func attributed(for item: ClipItem) -> NSAttributedString? {
        if let html = item.htmlData, withinLimit(html),
           let safe = sanitizedHTML(html),
           let s = NSAttributedString(html: safe,
                                      // Belt-and-braces alongside the stripping
                                      // above: never let the importer wait on a
                                      // (now nonexistent) subresource load.
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
