import SwiftUI

struct ClipCardView: View {
    let item: ClipItem
    let index: Int
    let selected: Bool

    @State private var hovering = false
    private var store: ClipboardStore { ClipboardStore.shared }
    private var headerColor: Color { SourceColor.color(for: item.sourceBundleID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            body_
        }
        .frame(width: Theme.cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .strokeBorder(selected ? Theme.selection : Theme.cardBorder,
                              lineWidth: selected ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(selected ? 0.35 : 0.18),
                radius: selected ? 12 : 5, y: selected ? 5 : 2)
        .scaleEffect(hovering && !selected ? 1.015 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: selected)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { AppController.shared.pasteItem(item) }
        .onTapGesture { store.selectedID = item.id }
        .contextMenu { menu }
    }

    private var header: some View {
        ZStack {
            headerColor
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.type.label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.headerText)
                    Text(item.createdAt.clipRelativeLong)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.headerSubText)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                appIconTile
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(height: Theme.headerHeight)
    }

    private var appIconTile: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.black.opacity(0.22))
            .frame(width: 38, height: 38)
            .overlay(
                Image(nsImage: AppIconProvider.icon(forBundleID: item.sourceBundleID))
                    .resizable()
                    .frame(width: 28, height: 28)
            )
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(.horizontal, 13)
        .padding(.top, 11)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.cardBody)
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .image:
            if let img = store.loadImage(for: item) {
                Image(nsImage: img)
                    .resizable().interpolation(.medium).scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { placeholder("photo") }
        case .color:
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(hex: item.colorHex ?? "#000") ?? .black)
                Text(item.colorHex ?? "")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white).shadow(radius: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .file:
            VStack(spacing: 9) {
                Image(systemName: "doc.fill").font(.system(size: 32))
                    .foregroundStyle(headerColor)
                Text(item.displayTitle).font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary).lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .link:
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Image(systemName: "safari").font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        default:
            Text(item.text ?? "")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textPrimary.opacity(0.9))
                .lineLimit(10)
                .multilineTextAlignment(.leading)
        }
    }

    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 30))
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            if item.type == .link {
                Text(item.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(metaLeft)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if index < 9 {
                    HStack(spacing: 3) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(.top, 8)
    }

    private var metaLeft: String {
        switch item.type {
        case .text, .richText:
            return "\(item.charCount) characters"
        case .link:
            return (item.text ?? "").replacingOccurrences(of: "https://", with: "")
                                    .replacingOccurrences(of: "http://", with: "")
        case .file:
            return "\(item.fileURLs.count) file\(item.fileURLs.count == 1 ? "" : "s")"
        case .image:
            return "Image"
        case .color:
            return item.colorHex ?? "Color"
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
