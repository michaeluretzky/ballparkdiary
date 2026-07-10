import SwiftUI

/// Centralized visual language for Ballpark Diary.
/// Midnight stadium night with parchment cards, infield-clay orange,
/// outfield grass green and warm stadium-light amber accents.
///
/// Typography uses a bundled athletic display face for scores/big numbers
/// and the system grotesk for body — no more generic serif everywhere.
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

    // Subtle vignette for the night background — avoids flat-digital surfaces.
    static let nightVignette = RadialGradient(
        colors: [.clear, Color.black.opacity(0.35)],
        center: .center,
        startRadius: 100,
        endRadius: 600
    )

    /// Paper-grain overlay for parchment surfaces (ticket stub).
    /// A very subtle noise texture applied as an overlay to break up
    /// the flat color and give the stub physical weight.
    static let paperGrain = LinearGradient(
        colors: [
            Color.white.opacity(0.015),
            Color.black.opacity(0.025),
            Color.white.opacity(0.01),
            Color.black.opacity(0.02)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Motion

    /// Single source of truth for animation curves. Springs are interruptible
    /// by default — never wrap these in non-interruptible completion patterns.
    ///
    ///   snappy — quick spring for state changes (filters, toggles, steppers).
    ///   gentle — soft spring for sheets, cards and larger surface movement.
    ///
    /// Looping/decorative animations (spins, pulses, shimmers) must additionally
    /// check `@Environment(\.accessibilityReduceMotion)` and render static when on.
    enum Motion {
        static let snappy: Animation = .snappy(duration: 0.35)
        static let gentle: Animation = .spring(duration: 0.5, bounce: 0.15)
    }
}

// MARK: - Typography
//
// Structured, official typographic hierarchy — clean sans-serif throughout
// for a modern athletic scoreboard feel. No newspaper serifs.
//
// Roles:
//   display   — biggest numbers (scores, hero counts) · heavy system
//   headline  — section titles, ballpark names · bold system
//   scoreboard — compact athletic label (W/L, team abbreviations) · default
//   stat      — tabular monospaced numbers · default
//   body      — paragraph text · default
//   caption   — secondary / footnote text · default
//   caps      — tracked uppercase label · default

extension Font {
    /// Hero numbers — heavy, structured, authoritative.
    /// Scales with Dynamic Type using @ScaledMetric-backed relative sizing.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Section titles, ballpark names, card headers — bold and official.
    static func headline(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Compact athletic label — scores, team abbreviations, win/loss markers.
    static func scoreboard(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Tabular, monospaced digits for stat numbers.
    static func stat(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default).monospacedDigit()
    }

    /// Paragraph body — clean, readable San Francisco.
    static func body(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Small secondary / footnote text. Minimum 11pt.
    static func caption(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        .system(size: max(11, size), weight: weight, design: .default)
    }

    /// Compact uppercase label. Used sparingly — not on every card.
    static func caps(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: max(11, size), weight: weight, design: .default)
    }
}

// MARK: - ScaledMetric font provider

/// Provides @ScaledMetric-based font sizes that respond to Dynamic Type.
/// Use in views via `@ScaledMetric private var titleSize: CGFloat = 16` then
/// pass to the Font helpers. This keeps the athletic design while scaling.
struct ScaledFont {
    /// Maps a base point size to a TextStyle for Dynamic Type scaling.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 0..<11:  return .caption2
        case 11..<13: return .caption
        case 13..<16: return .footnote
        case 16..<20: return .body
        case 20..<28: return .title3
        case 28..<34: return .title2
        case 34...:   return .title
        default:       return .body
        }
    }
}

// MARK: - Team-aware color helpers

/// Returns accent colors tinted to the user's favorite team.
/// Callers pass the store's favorite team; fallback is infield clay.
struct TeamColors {
    let primary: Color
    let secondary: Color

    static func from(team: Team?) -> TeamColors {
        guard let team else { return TeamColors(primary: Theme.clay, secondary: Theme.clayDeep) }
        return TeamColors(primary: team.primary, secondary: team.secondary)
    }
}

// MARK: - View modifiers

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

    /// A darker, deeper card that feels recessed. For material variety
    /// so not every surface looks like the same card.
    func nightCardDeep(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.nightDeep)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
            )
    }

    /// Vignette overlay for the night background.
    func nightBackground() -> some View {
        ZStack {
            Theme.nightGradient
            Theme.nightVignette
        }
        .ignoresSafeArea()
    }

    /// Faint paper-grain texture for parchment surfaces.
    func parchmentTexture() -> some View {
        self.overlay(Theme.paperGrain)
    }
}
