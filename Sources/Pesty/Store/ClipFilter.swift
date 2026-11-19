import Foundation

/// Pure filtering and counting rules for the Paste Bar's strip.
///
/// The strip is narrowed in three layers, in this order: the selected source
/// (history or a pinboard), the content-type filter, then the text query.
/// Keeping those rules here instead of inside `ClipboardStore` makes them
/// directly unit-testable without touching the on-disk store singleton.
enum ClipFilter {
    /// Applies the active type filter and search query, in that order.
    ///
    /// The query keeps its existing semantics: trimmed, lowercased, and matched
    /// as a substring of `ClipItem.searchableText`.
    static func applying(type: ClipType?, searchText: String, to items: [ClipItem]) -> [ClipItem] {
        var result = items
        if let type {
            result = result.filter { $0.type == type }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return result }
        return result.filter { $0.searchableText.contains(query) }
    }

    /// Number of clips per content type in one collection. Drives the filter
    /// chips' disabled state: a type the collection has never held cannot be
    /// selected into a dead end.
    static func typeCounts(in items: [ClipItem]) -> [ClipType: Int] {
        var counts: [ClipType: Int] = [:]
        for item in items {
            counts[item.type, default: 0] += 1
        }
        return counts
    }

    /// Every type the collection currently holds, in `ClipType.allCases` order.
    static func availableTypes(in items: [ClipItem]) -> [ClipType] {
        let counts = typeCounts(in: items)
        return ClipType.allCases.filter { counts[$0, default: 0] > 0 }
    }

    /// The next stop for the keyboard shortcut (⌘⇧F): All, then each type the
    /// collection actually contains, then All again - empty types are skipped
    /// rather than landing on a filter with nothing to show.
    static func nextTypeFilter(after current: ClipType?, available: [ClipType]) -> ClipType? {
        guard !available.isEmpty else { return nil }
        let order: [ClipType?] = [nil] + available.map(Optional.some)
        guard let index = order.firstIndex(of: current) else { return available[0] }
        return order[(index + 1) % order.count]
    }
}
