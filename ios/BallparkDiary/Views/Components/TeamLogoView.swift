import SwiftUI

/// A team-colored circular badge showing each MLB club's distinctive cap
/// letter mark — "NY" for Yankees, "LA" for Dodgers, "B" for Red Sox, etc.
///
/// Every team gets a unique letter treatment sized proportionally to the
/// character count, so 3-letter marks like "STL" stay readable even at
/// compact sizes. The background uses the team's primary color with a
/// subtle gradient, ringed in the secondary color, with an optional
/// gloss highlight on larger variants.
struct TeamLogoView: View {
    let team: Team
    var size: CGFloat = 56
    var showGloss: Bool = true

    // Adaptive font size — wider marks need smaller type to fit
    private var fontSize: CGFloat {
        let base: CGFloat
        switch team.logoMark.count {
        case 1:  base = size * 0.50
        case 2:  base = size * 0.40
        default: base = size * 0.30
        }
        // "SOX" and "STL" are tighter; bump them down slightly more
        if team.logoMark.count >= 3 { return base * 0.90 }
        return base
    }

    private var lineWidth: CGFloat { max(1.5, size * 0.035) }

    var body: some View {
        ZStack {
            // Subtle outer glow — visible against dark card backgrounds
            Circle()
                .fill(team.primary.opacity(0.22))
                .frame(width: size + 10, height: size + 10)
                .blur(radius: 8)

            // Team-primary fill with diagonal gradient for depth
            Circle()
                .fill(
                    LinearGradient(
                        colors: [team.primary.opacity(0.85), team.primary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Secondary-color border ring
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [team.secondary, team.secondary.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: lineWidth
                )

            // Team letter mark — white, bold, slightly shadowed
            Text(team.logoMark)
                .font(.system(size: fontSize, weight: .black, design: .default))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            // Gloss arc — top-left highlight for larger sizes
            if showGloss {
                Circle()
                    .trim(from: 0, to: 0.48)
                    .stroke(Color.white.opacity(0.18), lineWidth: size * 0.07)
                    .rotationEffect(.degrees(-40))
                    .padding(size * 0.1)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Convenience initializer for chip / row contexts where a compact
/// badge replaces the old abbreviation circle without shifting layout.
extension TeamLogoView {
    /// A compact logo suitable for chip / row contexts (e.g. 28pt).
    static func compact(_ team: Team, size: CGFloat = 28) -> TeamLogoView {
        TeamLogoView(team: team, size: size, showGloss: size >= 40)
    }
}
