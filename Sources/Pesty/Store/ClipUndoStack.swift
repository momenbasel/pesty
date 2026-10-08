import Foundation

/// Where a deleted clip sat, so Undo puts it back there instead of at the
/// front: after its predecessor if that clip is still around, else before
/// its successor, else at the original index.
struct ClipPlacement {
    let container: BarSource
    let index: Int
    let item: ClipItem
    let predecessorID: UUID?
    let successorID: UUID?

    func restorationIndex(in items: [ClipItem]) -> Int {
        if let predecessorID, let i = items.firstIndex(where: { $0.id == predecessorID }) { return i + 1 }
        if let successorID, let i = items.firstIndex(where: { $0.id == successorID }) { return i }
        return min(max(0, index), items.count)
    }
}

/// One delete operation, restorable as a whole: a bulk delete comes back
/// with a single Undo.
struct ClipDeletion {
    let placements: [ClipPlacement]
    let deletedAt: Date
}

/// The deletions still open for Undo. Memory only: deleted content is never
/// written back to store.json, and nothing here reaches sync. Entries are
/// pushed in time order, so the last one is the newest and the first one
/// expires first.
struct ClipUndoStack {
    static let window: TimeInterval = 5 * 60

    private(set) var deletions: [ClipDeletion] = []

    var isEmpty: Bool { deletions.isEmpty }

    var nextExpiration: Date? {
        deletions.first.map { $0.deletedAt.addingTimeInterval(Self.window) }
    }

    mutating func push(_ placements: [ClipPlacement], at date: Date) {
        guard !placements.isEmpty else { return }
        deletions.append(ClipDeletion(placements: placements, deletedAt: date))
    }

    /// The newest deletion, if its window is still open.
    mutating func pop(at date: Date) -> ClipDeletion? {
        guard let last = deletions.last, !Self.isExpired(last, at: date) else { return nil }
        return deletions.removeLast()
    }

    /// Drops every deletion whose window has closed and hands them back so
    /// the image files they kept alive can be removed.
    mutating func removeExpired(at date: Date) -> [ClipDeletion] {
        let expired = deletions.filter { Self.isExpired($0, at: date) }
        deletions.removeAll { Self.isExpired($0, at: date) }
        return expired
    }

    mutating func removeAll() -> [ClipDeletion] {
        defer { deletions.removeAll() }
        return deletions
    }

    func retainsImageFile(named name: String) -> Bool {
        deletions.contains { $0.placements.contains { $0.item.imageFileName == name } }
    }

    private static func isExpired(_ deletion: ClipDeletion, at date: Date) -> Bool {
        date.timeIntervalSince(deletion.deletedAt) >= window
    }
}
