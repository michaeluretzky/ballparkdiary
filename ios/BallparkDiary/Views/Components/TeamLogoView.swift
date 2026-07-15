import SwiftUI

/// A team-colored circular badge showing the official MLB team logo
/// loaded from the league's raster CDN endpoint, encircled in the team's
/// primary and secondary colors. Falls back to the cap letter mark if the
/// logo fails to load. Uses AsyncImage with a shared URLCache instead of
/// WKWebView for performance and security.
struct TeamLogoView: View {
    let team: Team
    var size: CGFloat = 56
    var showGloss: Bool = true

    @State private var imageLoadFailed = false

    private var lineWidth: CGFloat { max(1.5, size * 0.035) }
    private var innerPadding: CGFloat { size * 0.18 }
    /// The blurred outer glow overflows the layout frame, which makes small
    /// badges look different sizes per team color — only show it on larger art.
    private var showsGlow: Bool { size >= 40 }
    /// Light backing kept strictly inside the border ring so its blur never
    /// bleeds past the circle edge at chip sizes.
    private var backingDiameter: CGFloat {
        min(size - innerPadding * 2 + 6, size - lineWidth * 2 - 4)
    }

    /// The fill used for the team-colored circle — always the team's primary.
    private var fillColor: Color { team.primary }
    private var glowColor: Color { team.adaptiveGlow }

    var body: some View {
        ZStack {
            // Outer glow — uses the adaptive glow so dark teams get a visible halo.
            // Skipped at chip sizes where the overflow distorts apparent size.
            if showsGlow {
                Circle()
                    .fill(glowColor)
                    .frame(width: size + 10, height: size + 10)
                    .blur(radius: 8)
            }

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

            // Subtle light backing so dark logos stay visible against dark
            // primary-colored circles (e.g. Yankees navy "NY" on navy circle).
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: backingDiameter, height: backingDiameter)
                .blur(radius: size >= 40 ? 4 : 3)
                .allowsHitTesting(false)

            // Official team logo from MLB raster CDN via AsyncImage, or
            // fallback letter mark on failure.
            if !imageLoadFailed, let url = team.logoSpotURL(size: size) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        Color.clear
                            .onAppear { imageLoadFailed = true }
                    case .empty:
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
                .frame(
                    width: size - innerPadding * 2,
                    height: size - innerPadding * 2
                )
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
        .accessibilityHidden(true)
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

// MARK: - Shared URLCache for team logos

/// A shared URLCache for team logo images — memory + disk backed so logos
/// are cached across views and app launches without re-downloading.
enum TeamLogoCache {
    static let shared: URLCache = {
        let memoryCapacity = 20 * 1024 * 1024  // 20 MB memory
        let diskCapacity = 50 * 1024 * 1024     // 50 MB disk
        let cache = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: "team-logos")
        URLCache.shared = cache
        return cache
    }()
}

// MARK: - Convenience

extension TeamLogoView {
    /// A compact logo suitable for chip / row contexts (e.g. 28pt).
    static func compact(_ team: Team, size: CGFloat = 28) -> TeamLogoView {
        TeamLogoView(team: team, size: size, showGloss: size >= 40)
    }
}
