import SwiftUI

/// A team-colored circular badge showing the official MLB team logo
/// loaded from the league's CDN, encircled in the team's primary and
/// secondary colors. Falls back to the cap letter mark if the logo
/// fails to load.
struct TeamLogoView: View {
    let team: Team
    var size: CGFloat = 56
    var showGloss: Bool = true

    @State private var imageLoadFailed = false
    @State private var imageLoaded = false

    private var lineWidth: CGFloat { max(1.5, size * 0.035) }

    private var innerPadding: CGFloat { size * 0.16 }

    var body: some View {
        ZStack {
            // Subtle outer glow
            Circle()
                .fill(team.primary.opacity(0.22))
                .frame(width: size + 10, height: size + 10)
                .blur(radius: 8)

            // Team-primary fill with subtle gradient
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

            // Official team logo from MLB CDN, or fallback letter mark
            if !imageLoadFailed, let url = team.logoURL {
                SVGWebView(url: url, onLoaded: { imageLoaded = true }, onFailed: { imageLoadFailed = true })
                    .frame(
                        width: size - innerPadding * 2,
                        height: size - innerPadding * 2
                    )
                    .clipShape(Circle())
                    .opacity(imageLoaded ? 1 : 0)
            } else {
                fallbackLetterMark
            }

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

    // MARK: - Fallback

    private var fallbackLetterMark: some View {
        Text(team.logoMark)
            .font(.system(size: fontSize, weight: .black, design: .default))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    private var fontSize: CGFloat {
        let base: CGFloat
        switch team.logoMark.count {
        case 1:  base = size * 0.50
        case 2:  base = size * 0.40
        default: base = size * 0.30
        }
        if team.logoMark.count >= 3 { return base * 0.90 }
        return base
    }
}

/// Convenience initializer for chip / row contexts.
extension TeamLogoView {
    /// A compact logo suitable for chip / row contexts (e.g. 28pt).
    static func compact(_ team: Team, size: CGFloat = 28) -> TeamLogoView {
        TeamLogoView(team: team, size: size, showGloss: size >= 40)
    }
}
