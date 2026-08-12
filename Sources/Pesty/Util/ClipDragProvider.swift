import AppKit
import UniformTypeIdentifiers

@MainActor
enum ClipDragProvider {
    private static let colorTypeIdentifier = "com.apple.cocoa.pasteboard.color"

    static func make(for item: ClipItem) -> NSItemProvider {
        let provider = NSItemProvider()
        switch item.type {
        case .image:
            registerImage(item, on: provider)
        case .file:
            let urls = item.fileURLs.compactMap(URL.init(string:)).filter(\.isFileURL)
            if urls.count == 1, let url = urls.first {
                provider.registerObject(url as NSURL, visibility: .all)
                provider.suggestedName = url.lastPathComponent
            } else {
                registerText(item.text ?? item.displayTitle, on: provider)
            }
        case .link:
            if let text = item.text, let url = URL(string: text) {
                provider.registerObject(url as NSURL, visibility: .all)
            }
            registerText(item.text ?? "", on: provider)
        case .color:
            if let hex = item.colorHex, let color = NSColor(hex: hex),
               let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) {
                register(data, as: colorTypeIdentifier, on: provider)
            }
            registerText(item.colorHex ?? "", on: provider)
        case .richText:
            if let rtf = item.rtfData {
                register(rtf, as: UTType.rtf.identifier, on: provider)
            }
            registerText(item.text ?? "", on: provider)
        case .text:
            registerText(item.text ?? "", on: provider)
        }
        if provider.suggestedName == nil { provider.suggestedName = item.displayTitle }
        return provider
    }

    private static func registerImage(_ item: ClipItem, on provider: NSItemProvider) {
        guard let url = ClipboardStore.shared.imageURL(for: item) else { return }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            do {
                completion(try Data(contentsOf: url), nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }
        provider.suggestedName = "Pesty Image \(item.id.uuidString.prefix(8)).png"
    }

    private static func registerText(_ text: String, on provider: NSItemProvider) {
        register(Data(text.utf8), as: UTType.utf8PlainText.identifier, on: provider)
    }

    private static func register(_ data: Data, as identifier: String, on provider: NSItemProvider) {
        provider.registerDataRepresentation(forTypeIdentifier: identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
    }
}
