import SwiftUI

struct ClipCardView: View {
    let item: ClipItem
    let index: Int
    let selected: Bool

    @State private var hovering = false
    private var store: ClipboardStore { ClipboardStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(item.type.accent)
                .frame(height: 3)
            VStack(alignment: .leading, spacing: 9) {
                header
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer
            }
            .padding(12)
        }
        .frame(width: Theme.cardWidth)
        .background(selected ? Theme.cardBGSelected : (hovering ? Theme.cardBGHover : Theme.cardBG))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .strokeBorder(selected ? item.type.accent : Theme.cardBorder,
                              lineWidth: selected ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) { numberBadge }
        .scaleEffect(selected ? 1.0 : 0.985)
        .animation(.easeOut(duration: 0.12), value: selected)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { AppController.shared.pasteItem(item) }
        .onTapGesture { store.selectedID = item.id }
        .contextMenu { menu }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIconProvider.icon(forBundleID: item.sourceBundleID))
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(item.sourceAppName ?? item.type.label)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(item.createdAt.clipRelative)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .image:
            if let img = store.loadImage(for: item) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholder("photo")
            }
        case .color:
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: item.colorHex ?? "#000000") ?? .black)
                Text(item.colorHex ?? "")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
            }
        case .file:
            VStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(item.type.accent)
                Text(item.text ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .link:
            Text(item.text ?? "")
                .font(.system(size: 12))
                .foregroundStyle(item.type.accent)
                .lineLimit(6)
                .multilineTextAlignment(.leading)
                .textSelection(.disabled)
        default:
            Text(item.text ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                .lineLimit(9)
                .multilineTextAlignment(.leading)
        }
    }

    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 30))
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text(item.type.label.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(item.type.accent)
                .tracking(0.4)
            Spacer()
            Text(metaText)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var metaText: String {
        switch item.type {
        case .text, .richText, .link:
            return "\(item.charCount) chars"
        case .file:
            return "\(item.fileURLs.count) file\(item.fileURLs.count == 1 ? "" : "s")"
        case .image:
            return "Image"
        case .color:
            return "Color"
        }
    }

    @ViewBuilder
    private var numberBadge: some View {
        if index < 9 {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 18, height: 18)
                .background(Color.black.opacity(0.35), in: Circle())
                .padding(6)
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Paste") { AppController.shared.pasteItem(item) }
        Button("Copy") { AppController.shared.copyItem(item) }
        Divider()
        if !store.pinboards.isEmpty {
            Menu("Save to Pinboard") {
                ForEach(store.pinboards) { b in
                    Button(b.name) { store.saveToPinboard(item, boardID: b.id) }
                }
            }
        }
        Button("Save to New Pinboard…") {
            if let name = TextPrompt.run(title: "New Pinboard", message: "Name") {
                let b = store.addPinboard(name: name)
                store.saveToPinboard(item, boardID: b.id)
            }
        }
        Button("Edit Title…") {
            if let t = TextPrompt.run(title: "Edit Title", message: "Card title",
                                      defaultValue: item.customTitle ?? "") {
                store.setTitle(t, for: item)
            }
        }
        Divider()
        Button("Delete", role: .destructive) { store.delete(item) }
    }
}
