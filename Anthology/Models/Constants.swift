import SwiftUI

/// Mirror of the Mac app's renderer constants.js so spawn-from-iOS produces
/// sessions that match what the Mac UI already shows.
enum SessionConstants {
    static let colors: [String] = [
        "#7B2FBE", // purple
        "#1DB9A0", // teal
        "#E8634F", // coral
        "#D4A843", // gold
        "#4DA3D4", // sky
        "#7CBB4F", // lime
        "#D4648A", // blush
        "#5A6B7E", // slate
    ]

    static let tags: [String] = [
        "feature", "bugfix", "docs", "exploration",
        "design", "refactor", "review", "spike",
    ]
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
