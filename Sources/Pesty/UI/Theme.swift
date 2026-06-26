import SwiftUI

enum Theme {
    static let cardWidth: CGFloat = 212
    static let cardSpacing: CGFloat = 14
    static let cornerRadius: CGFloat = 14
    static let cardCorner: CGFloat = 12

    static let panelTint = Color.black.opacity(0.22)
    static let cardBG = Color.white.opacity(0.055)
    static let cardBGHover = Color.white.opacity(0.09)
    static let cardBGSelected = Color.white.opacity(0.13)
    static let cardBorder = Color.white.opacity(0.08)

    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.5)
    static let textTertiary = Color.white.opacity(0.32)

    static let fieldBG = Color.white.opacity(0.08)
}

extension Date {
    var clipRelative: String {
        let secs = -timeIntervalSinceNow
        switch secs {
        case ..<5:        return "Now"
        case ..<60:       return "\(Int(secs))s"
        case ..<3600:     return "\(Int(secs / 60))m"
        case ..<86_400:   return "\(Int(secs / 3600))h"
        case ..<604_800:  return "\(Int(secs / 86_400))d"
        default:
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: self)
        }
    }
}
