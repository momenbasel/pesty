import SwiftUI

/// The Paste Bar's always-visible content-type filter: one click narrows the
/// strip to a single `ClipType`, which is the fastest answer to "where is that
/// screenshot I copied?".
///
/// It lives in its own row under the top chrome rather than inside it, so the
/// search field, pinboard tabs, bulk-delete and undo controls keep the widths
/// they had. Like the pinboard tabs it scrolls horizontally on narrow displays.
struct ClipTypeFilterBar: View {
    @Bindable private var store = ClipboardStore.shared

    private var filterDescription: String {
        store.typeFilter.map { "\($0.label) clips" } ?? "All clip types"
    }

    var body: some View {
        // Counts are computed once per body evaluation; each chip reads from
        // this dictionary instead of recomputing the whole collection.
        let counts = store.typeCounts
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ClipTypeFilterChip(
                    title: "All Types",
                    icon: "line.3.horizontal.decrease.circle",
                    accent: Theme.selection,
                    selected: store.typeFilter == nil,
                    enabled: true,
                    help: "Show every clip type (⌘⇧F cycles)",
                    accessibilityLabel: "All clip types",
                    accessibilityHint: "Show every clip type") {
                    store.typeFilter = nil
                }

                ForEach(ClipType.allCases, id: \.self) { type in
                    let count = counts[type, default: 0]
                    ClipTypeFilterChip(
                        title: type.label,
                        icon: type.symbol,
                        accent: type.accent,
                        selected: store.typeFilter == type,
                        // A selected chip stays enabled even when its last clip
                        // was deleted or the pinboard changed underneath it, so
                        // a stranded filter can always be tapped off again.
                        enabled: count > 0 || store.typeFilter == type,
                        help: helpText(for: type, count: count),
                        accessibilityLabel: "Show only \(type.label.lowercased()) clips",
                        accessibilityHint: count > 0 || store.typeFilter == type
                            ? "Show only \(type.label.lowercased()) clips"
                            : "No clips of this type in this collection") {
                        // Clicking the selected type again returns to All, so
                        // the filter can be dismissed without aiming at a
                        // second chip.
                        store.typeFilter = store.typeFilter == type ? nil : type
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 3)
        }
        .frame(height: 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Content type filter")
        .accessibilityValue(filterDescription)
    }

    private func helpText(for type: ClipType, count: Int) -> String {
        let availability = count > 0
            ? "Show only \(type.label.lowercased()) clips (\(count))"
            : "No \(type.label.lowercased()) clips in this collection"
        // "Image" is the image *data* kind; Finder-copied image files are
        // recorded as File clips and are not included here.
        guard type == .image else { return availability }
        return availability + ". Copied image files count as File clips."
    }
}

/// A single filter pill. Selected chips keep the bar's established
/// white-pill style (the same one PinboardTabs uses) and borrow the type's
/// accent for the icon and border only - filling the pill with the accent
/// would leave white 12pt text below readable contrast for the lighter,
/// warmer type colors.
private struct ClipTypeFilterChip: View {
    let title: String
    let icon: String
    let accent: Color
    let selected: Bool
    let enabled: Bool
    let help: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? accent : Theme.chromeTextSecondary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(selected ? Theme.chromeTextPrimary : Theme.chromeTextSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(background, in: Capsule())
            .overlay {
                Capsule().strokeBorder(borderColor, lineWidth: selected ? 1.5 : 0.5)
            }
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .fixedSize()
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var background: Color {
        if selected { return Color.white.opacity(0.24) }
        if hovering && enabled { return Theme.pillSelected.opacity(0.7) }
        return Theme.pillBG
    }

    private var borderColor: Color {
        selected ? accent.opacity(0.95) : Color.black.opacity(0.10)
    }
}
