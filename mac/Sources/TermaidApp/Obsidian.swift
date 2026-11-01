import SwiftUI

/// termaid's Obsidian palette (src/obsidianTheme.ts): a black canvas, muted jewel hues, Avenir Next.
enum Obsidian {
    static let canvas = Color(red: 5 / 255, green: 5 / 255, blue: 6 / 255)
    static let surface = Color(red: 12 / 255, green: 12 / 255, blue: 16 / 255)
    static let border = Color(red: 63 / 255, green: 63 / 255, blue: 70 / 255)
    static let fg = Color(red: 236 / 255, green: 236 / 255, blue: 239 / 255)
    static let muted = Color(red: 161 / 255, green: 161 / 255, blue: 170 / 255)
    // The decision-node blues, muted the way the diagrams mute every hue.
    static let skyBlue = Color(red: 96 / 255, green: 165 / 255, blue: 250 / 255)
    static let deepBlue = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    static let green = Color(red: 34 / 255, green: 163 / 255, blue: 90 / 255)
    static let amber = Color(red: 214 / 255, green: 160 / 255, blue: 77 / 255)
    static let rose = Color(red: 208 / 255, green: 112 / 255, blue: 124 / 255)
    static let accent = LinearGradient(colors: [skyBlue, deepBlue], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Avenir Next", size: size).weight(weight)
    }
}

