import SwiftUI

/// Centralized visual language for Ballpark Diary.
/// Midnight stadium night with parchment cards, infield-clay orange,
/// outfield grass green and warm stadium-light amber accents.
enum Theme {
    // Backgrounds
    static let night = Color(red: 0.043, green: 0.082, blue: 0.188)        // #0B1530 midnight navy
    static let nightDeep = Color(red: 0.024, green: 0.047, blue: 0.118)    // deeper navy
    static let card = Color(red: 0.082, green: 0.129, blue: 0.243)         // #15213E card
    static let cardElevated = Color(red: 0.118, green: 0.169, blue: 0.290) // elevated surface

    // Parchment (vintage baseball card)
    static let parchment = Color(red: 0.957, green: 0.929, blue: 0.847)    // #F4ECD8
    static let parchmentInk = Color(red: 0.149, green: 0.122, blue: 0.090) // dark sepia

    // Accents
    static let clay = Color(red: 0.878, green: 0.478, blue: 0.169)         // #E07A2B infield clay
    static let clayDeep = Color(red: 0.682, green: 0.314, blue: 0.067)
    static let grass = Color(red: 0.290, green: 0.486, blue: 0.227)        // #4A7C3A outfield
    static let lights = Color(red: 0.961, green: 0.784, blue: 0.259)       // #F5C842 stadium lights
    static let chalk = Color(red: 0.961, green: 0.953, blue: 0.937)        // baseline chalk
    static let foul = Color(red: 0.870, green: 0.240, blue: 0.240)         // foul red

    // Text
    static let textPrimary = Color(red: 0.961, green: 0.953, blue: 0.937)
    static let textSecondary = Color(red: 0.647, green: 0.690, blue: 0.788)
    static let textMuted = Color(red: 0.439, green: 0.490, blue: 0.604)

    // Gradients
    static let nightGradient = LinearGradient(
        colors: [nightDeep, night, Color(red: 0.067, green: 0.110, blue: 0.235)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let clayGradient = LinearGradient(
        colors: [clay, clayDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let lightsGradient = RadialGradient(
        colors: [lights.opacity(0.35), .clear],
        center: .center,
        startRadius: 0,
        endRadius: 220
    )
}

extension Font {
    /// Display serif evocative of a scorecard.
    static func scoreboard(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Tabular, monospaced digits for stat numbers.
    static func stat(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func caps(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

extension View {
    /// Subtle inner border on dark cards.
    func nightCard(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}
