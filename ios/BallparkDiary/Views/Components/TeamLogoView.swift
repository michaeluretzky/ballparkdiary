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
    @State private var hasAppeared = false

    private var lineWidth: CGFloat { max(1.5, size * 0.035) }
    private var innerPadding: CGFloat { size * 0.18 }

    /// The fill used for the team-colored circle — always the team's primary.
    private var fillColor: Color { team.primary }
    private var glowColor: Color { team.adaptiveGlow }

    var body: some View {
        ZStack {
            // Outer glow — uses the adaptive glow so dark teams get a visible halo
            Circle()
                .fill(glowColor)
                .frame(width: size + 10, height: size + 10)
                .blur(radius: 8)

            // Team-color fill with subtle gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [fillColor.opacity(0.85), fillColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Secondary-color border ring
            Circle()
                .strokeBorder(
                    team.secondary,
                    lineWidth: lineWidth
                )

            // Subtle light backing so dark SVG logos stay visible against dark
            // primary-colored circles (e.g. Yankees navy "NY" on navy circle).
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(
                    width: size - innerPadding * 2 + 6,
                    height: size - innerPadding * 2 + 6
                )
                .blur(radius: 4)
                .allowsHitTesting(false)

            // Official team logo from MLB CDN, or fallback letter mark.
            // Defer WKWebView creation until the view has appeared on screen
            // to avoid crashes from rapid init/destroy cycles (e.g. StatsView).
            if !imageLoadFailed, let url = team.logoURL, hasAppeared {
                SVGWebView(url: url, onLoaded: { imageLoaded = true }, onFailed: { imageLoadFailed = true })
                    .frame(
                        width: size - innerPadding * 2,
                        height: size - innerPadding * 2
                    )
                    .opacity(imageLoaded ? 1 : 0)
                    .allowsHitTesting(false)
            } else {
                fallbackLetterMark
            }

            // Gloss arc — top-left highlight for larger sizes
            if showGloss && size >= 36 {
                Circle()
                    .trim(from: 0, to: 0.50)
                    .stroke(Color.white.opacity(0.16), lineWidth: size * 0.06)
                    .rotationEffect(.degrees(-45))
                    .padding(size * 0.08)
                    .allowsHitTesting(false)
            }

            // Subtle inner shadow ring
            Circle()
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                .padding(1)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .contentShape(.circle)
        .onAppear {
            // Small delay lets the layout settle before creating WKWebView.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Fallback

    private var fallbackLetterMark: some View {
        Text(team.logoMark)
            .font(.system(size: fallbackFontSize, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.30), radius: 0.5, x: 0, y: 0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .frame(width: size - innerPadding * 2, height: size - innerPadding * 2)
    }

    private var fallbackFontSize: CGFloat {
        switch team.logoMark.count {
        case 1:  return size * 0.48
        case 2:  return size * 0.38
        default: return size * 0.28
        }
    }
}

// MARK: - Convenience

extension TeamLogoView {
    /// A compact logo suitable for chip / row contexts (e.g. 28pt).
    static func compact(_ team: Team, size: CGFloat = 28) -> TeamLogoView {
        TeamLogoView(team: team, size: size, showGloss: size >= 40)
    }
}
