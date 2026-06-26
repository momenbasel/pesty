import SwiftUI

enum ClipType: String, Codable, CaseIterable {
    case text
    case richText
    case link
    case image
    case file
    case color

    var label: String {
        switch self {
        case .text:     return "Text"
        case .richText: return "Rich Text"
        case .link:     return "Link"
        case .image:    return "Image"
        case .file:     return "File"
        case .color:    return "Color"
        }
    }

    var accent: Color {
        switch self {
        case .text:     return Color(red: 0.39, green: 0.55, blue: 0.98)
        case .richText: return Color(red: 0.60, green: 0.46, blue: 0.98)
        case .link:     return Color(red: 0.20, green: 0.74, blue: 0.62)
        case .image:    return Color(red: 0.96, green: 0.62, blue: 0.26)
        case .file:     return Color(red: 0.91, green: 0.44, blue: 0.47)
        case .color:    return Color(red: 0.55, green: 0.78, blue: 0.34)
        }
    }

    var symbol: String {
        switch self {
        case .text:     return "text.alignleft"
        case .richText: return "doc.richtext"
        case .link:     return "link"
        case .image:    return "photo"
        case .file:     return "doc"
        case .color:    return "paintpalette"
        }
    }
}
