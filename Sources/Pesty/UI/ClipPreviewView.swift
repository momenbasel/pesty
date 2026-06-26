import SwiftUI

struct ClipPreviewView: View {
    let item: ClipItem

    private var store: ClipboardStore { ClipboardStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.12))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIconProvider.icon(forBundleID: item.sourceBundleID))
                .resizable()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text(item.sourceAppName ?? item.type.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(item.createdAt.clipRelative)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .image:
            imagePreview
        case .color:
            colorPreview
        case .file:
            filePreview
        case .link:
            textPreview(item.text ?? "", accent: item.type.accent, monospaced: false)
        case .richText:
            textPreview(item.text ?? "", accent: Theme.textPrimary, monospaced: false)
        case .text:
            textPreview(item.text ?? "", accent: Theme.textPrimary, monospaced: looksLikeCode)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = store.loadImage(for: item) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.055))

                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .padding(10)
            }
        } else {
            placeholder(symbol: "photo", text: "Image unavailable")
        }
    }

    private var colorPreview: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: item.colorHex ?? "#000000") ?? .black)

            Text(item.colorHex ?? "Color")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                .padding(14)
        }
    }

    private var filePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(item.type.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileURLs.count == 1 ? "1 file" : "\(item.fileURLs.count) files")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(item.text ?? item.displayTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(fileNames, id: \.self) { name in
                        HStack(spacing: 7) {
                            Image(systemName: "doc")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                            Text(name)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func textPreview(_ text: String, accent: Color, monospaced: Bool) -> some View {
        ScrollView {
            Text(text.isEmpty ? item.displayTitle : text)
                .font(.system(size: 13.5,
                              weight: .regular,
                              design: monospaced ? .monospaced : .default))
                .foregroundStyle(accent.opacity(item.type == .link ? 0.95 : 0.9))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Label(item.type.label.uppercased(), systemImage: item.type.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(item.type.accent)
                .labelStyle(.titleAndIcon)

            Spacer()

            Text(metaText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
    }

    private var fileNames: [String] {
        item.fileURLs.map { raw in
            URL(string: raw)?.lastPathComponent ?? raw
        }
    }

    private var looksLikeCode: Bool {
        guard let text = item.text else { return false }
        return text.contains("{") || text.contains("}") || text.contains("func ") || text.contains("let ")
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
            return item.colorHex ?? "Color"
        }
    }
}
