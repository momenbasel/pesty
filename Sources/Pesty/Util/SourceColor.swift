import SwiftUI

@MainActor
enum SourceColor {
    private static let palette: [Color] = [
        Color(red: 0.85, green: 0.66, blue: 0.22),
        Color(red: 0.34, green: 0.56, blue: 0.82),
        Color(red: 0.72, green: 0.38, blue: 0.58),
        Color(red: 0.27, green: 0.62, blue: 0.55),
        Color(red: 0.80, green: 0.40, blue: 0.34),
        Color(red: 0.45, green: 0.40, blue: 0.74),
        Color(red: 0.49, green: 0.62, blue: 0.30),
        Color(red: 0.84, green: 0.52, blue: 0.27),
        Color(red: 0.30, green: 0.49, blue: 0.74),
        Color(red: 0.62, green: 0.42, blue: 0.30),
        Color(red: 0.74, green: 0.36, blue: 0.42),
        Color(red: 0.40, green: 0.55, blue: 0.62)
    ]

    private static let key = "appColorMap"
    private static var map: [String: Int] = {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }()

    static func color(for bundleID: String?) -> Color {
        guard let id = bundleID, !id.isEmpty else { return palette[0] }
        if let i = map[id] { return palette[i % palette.count] }
        let i = map.count % palette.count
        map[id] = i
        UserDefaults.standard.set(map, forKey: key)
        return palette[i]
    }
}
