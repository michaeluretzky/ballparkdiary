import SwiftUI

/// A premium sports-style circular team badge — replaces plain text abbreviations
/// across the app with a distinctive, official-feeling logo treatment.
///
/// Shows the team's primary color with a baseball icon, secondary-color border,
/// and a subtle gloss highlight on top. Works at any size and adapts to both
/// light-on-dark and dark-on-light contexts.
struct TeamLogoView: View {
    let team: Team
    var size: CGFloat = 56
    var showGloss: Bool = true

    private var iconSize: CGFloat { size * 0.38 }
    private var lineWidth: CGFloat { max(1.5, size * 0.035) }

    var body: some View {
        ZStack {
            // Soft outer glow — visible when the logo sits on a dark card
            Circle()
                .fill(team.primary.opacity(0.22))
                .frame(width: size + 10, height: size + 10)
                .blur(radius: 8)

            // Main fill — subtle top-to-bottom gradient for depth
            Circle()
                .fill(
                    LinearGradient(
                        colors: [team.primary.opacity(0.85), team.primary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Border ring in secondary color
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [team.secondary, team.secondary.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: lineWidth
                )

            // Gloss arc — top-left highlight that reads as light reflection
            if showGloss {
                Circle()
                    .trim(from: 0, to: 0.48)
                    .stroke(Color.white.opacity(0.18), lineWidth: size * 0.07)
                    .rotationEffect(.degrees(-40))
                    .padding(size * 0.1)
            }

            // Baseball icon — white, bold, slightly shadowed
            Image(systemName: "baseball.fill")
                .font(.system(size: iconSize, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
    }
}

/// Convenience initializer for shorthand use — matches the size of the old
/// abbreviation circles so layout doesn't shift.
extension TeamLogoView {
    /// A compact logo suitable for chip / row contexts (e.g. 28pt).
    static func compact(_ team: Team, size: CGFloat = 28) -> TeamLogoView {
        TeamLogoView(team: team, size: size, showGloss: size >= 40)
    }
}
