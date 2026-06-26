import SwiftUI

/// A beautiful, ground-level stadium illustration — like a photograph taken
/// from outside the ballpark at twilight. No more overhead satellite maps.
///
/// Used as the hero image on diary cards and the game-detail ballpark panel.
struct BallparkSnapshot: View {
    let ballpark: Ballpark
    var span: Double = 0.0065 // kept for API compatibility

    private var teamColor: Color { ballpark.team.primary }
    private var teamSecondary: Color { ballpark.team.secondary }

    var body: some View {
        StadiumIllustration(teamColor: teamColor, teamSecondary: teamSecondary)
    }
}

// MARK: - Stadium illustration

private struct StadiumIllustration: View {
    let teamColor: Color
    let teamSecondary: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // ── Sky ──
            let skyGradient = Gradient(colors: [
                Color(red: 0.02, green: 0.06, blue: 0.20),
                Color(red: 0.05, green: 0.10, blue: 0.28),
                Color(red: 0.08, green: 0.16, blue: 0.36),
                Color(red: 0.15, green: 0.22, blue: 0.40),
            ])
            context.fill(
                Path(CGRect(x: 0, y: 0, width: w, height: h)),
                with: .linearGradient(skyGradient, startPoint: CGPoint(x: 0.5, y: 0), endPoint: CGPoint(x: 0.5, y: 1))
            )

            // ── Stars ──
            let starPositions: [(CGFloat, CGFloat, CGFloat)] = [
                (0.12, 0.12, 1.5), (0.28, 0.06, 1.0), (0.45, 0.14, 1.8),
                (0.62, 0.08, 1.2), (0.78, 0.11, 1.0), (0.91, 0.05, 1.5),
                (0.18, 0.22, 0.8), (0.55, 0.19, 1.0), (0.85, 0.24, 0.7),
                (0.33, 0.04, 1.3), (0.70, 0.03, 0.9), (0.05, 0.18, 0.6),
                (0.95, 0.16, 0.8), (0.40, 0.25, 0.5), (0.15, 0.30, 0.4),
            ]
            for (rx, ry, rs) in starPositions {
                let starPath = Path { p in
                    let cx = rx * w
                    let cy = ry * h
                    let r = rs * 1.2
                    // Four-point star
                    p.move(to: CGPoint(x: cx, y: cy - r))
                    p.addLine(to: CGPoint(x: cx + r * 0.35, y: cy - r * 0.25))
                    p.addLine(to: CGPoint(x: cx + r, y: cy))
                    p.addLine(to: CGPoint(x: cx + r * 0.35, y: cy + r * 0.25))
                    p.addLine(to: CGPoint(x: cx, y: cy + r))
                    p.addLine(to: CGPoint(x: cx - r * 0.35, y: cy + r * 0.25))
                    p.addLine(to: CGPoint(x: cx - r, y: cy))
                    p.addLine(to: CGPoint(x: cx - r * 0.35, y: cy - r * 0.25))
                    p.closeSubpath()
                }
                context.fill(starPath, with: .color(.white.opacity(0.55 + Double.random(in: 0...0.35))))
            }

            // ── Moon glow ──
            let moonX = w * 0.82
            let moonY = h * 0.14
            let moonR: CGFloat = 16
            // Glow
            let glowPath = Path(ellipseIn: CGRect(x: moonX - moonR * 2, y: moonY - moonR * 2, width: moonR * 4, height: moonR * 4))
            context.fill(glowPath, with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.12), .clear]),
                center: CGPoint(x: moonX, y: moonY),
                startRadius: moonR,
                endRadius: moonR * 2
            ))
            // Moon body
            let moonPath = Path(ellipseIn: CGRect(x: moonX - moonR, y: moonY - moonR, width: moonR * 2, height: moonR * 2))
            context.fill(moonPath, with: .color(Color(red: 0.95, green: 0.93, blue: 0.85)))

            // ── Distant horizon glow ──
            let horizonY = h * 0.58
            let horizonGlow = Path { p in
                p.move(to: CGPoint(x: 0, y: horizonY - 20))
                p.addLine(to: CGPoint(x: w, y: horizonY - 20))
                p.addLine(to: CGPoint(x: w, y: horizonY + 8))
                p.addLine(to: CGPoint(x: 0, y: horizonY + 8))
                p.closeSubpath()
            }
            context.fill(horizonGlow, with: .linearGradient(
                Gradient(colors: [teamColor.opacity(0.08), .clear, teamColor.opacity(0.04)]),
                startPoint: CGPoint(x: 0.5, y: 0),
                endPoint: CGPoint(x: 0.5, y: 1)
            ))

            // ── Stadium structure (main building) ──
            let structureTop = h * 0.32
            let structureBot = h * 0.58
            let structureHeight = structureBot - structureTop

            // Main grandstand block
            let grandstandPath = Path { p in
                // Curved roofline — gentle arch
                p.move(to: CGPoint(x: w * 0.05, y: structureTop + structureHeight * 0.55))
                p.addCurve(
                    to: CGPoint(x: w * 0.95, y: structureTop + structureHeight * 0.55),
                    control1: CGPoint(x: w * 0.25, y: structureTop),
                    control2: CGPoint(x: w * 0.75, y: structureTop)
                )
                p.addLine(to: CGPoint(x: w * 0.95, y: structureBot))
                p.addLine(to: CGPoint(x: w * 0.05, y: structureBot))
                p.closeSubpath()
            }
            // Dark silhouette
            context.fill(grandstandPath, with: .color(Color(red: 0.03, green: 0.04, blue: 0.08)))

            // Lighter upper deck band
            let upperDeck = Path { p in
                p.move(to: CGPoint(x: w * 0.06, y: structureTop + structureHeight * 0.62))
                p.addCurve(
                    to: CGPoint(x: w * 0.94, y: structureTop + structureHeight * 0.62),
                    control1: CGPoint(x: w * 0.25, y: structureTop + structureHeight * 0.18),
                    control2: CGPoint(x: w * 0.75, y: structureTop + structureHeight * 0.18)
                )
                p.addLine(to: CGPoint(x: w * 0.94, y: structureBot))
                p.addLine(to: CGPoint(x: w * 0.06, y: structureBot))
                p.closeSubpath()
            }
            context.fill(upperDeck, with: .color(Color(red: 0.06, green: 0.08, blue: 0.14)))

            // ── Arched entryways ──
            let archCount = 7
            let archSpan = w * 0.78 / CGFloat(archCount)
            let archStartX = w * 0.11
            let archTop = structureBot - structureHeight * 0.25
            let archBot = structureBot
            for i in 0..<archCount {
                let cx = archStartX + archSpan * CGFloat(i) + archSpan * 0.05
                let archWidth = archSpan * 0.55
                let archHeight = archBot - archTop

                // Arch shape
                var arch = Path()
                arch.move(to: CGPoint(x: cx - archWidth / 2, y: archBot))
                arch.addLine(to: CGPoint(x: cx - archWidth / 2, y: archTop + archHeight * 0.15))
                arch.addCurve(
                    to: CGPoint(x: cx + archWidth / 2, y: archTop + archHeight * 0.15),
                    control1: CGPoint(x: cx - archWidth / 2, y: archTop),
                    control2: CGPoint(x: cx + archWidth / 2, y: archTop)
                )
                arch.addLine(to: CGPoint(x: cx + archWidth / 2, y: archBot))
                arch.closeSubpath()
                context.fill(arch, with: .color(teamColor.opacity(0.22)))

                // Arch outline
                var archOutline = Path()
                archOutline.move(to: CGPoint(x: cx - archWidth / 2, y: archBot))
                archOutline.addLine(to: CGPoint(x: cx - archWidth / 2, y: archTop + archHeight * 0.15))
                archOutline.addCurve(
                    to: CGPoint(x: cx + archWidth / 2, y: archTop + archHeight * 0.15),
                    control1: CGPoint(x: cx - archWidth / 2, y: archTop),
                    control2: CGPoint(x: cx + archWidth / 2, y: archTop)
                )
                archOutline.addLine(to: CGPoint(x: cx + archWidth / 2, y: archBot))
                context.stroke(archOutline, with: .color(teamColor.opacity(0.35)), lineWidth: 1)
            }

            // ── Light towers ──
            let towerPositions: [(CGFloat, CGFloat)] = [
                (0.12, 0.24), (0.28, 0.18), (0.50, 0.15), (0.72, 0.18), (0.88, 0.24),
            ]
            for (tx, ty) in towerPositions {
                let txAbs = tx * w
                let towerTop = ty * h
                let towerBot = structureTop + structureHeight * 0.45
                let towerWidth: CGFloat = 3

                // Tower pole
                let pole = Path(CGRect(
                    x: txAbs - towerWidth / 2, y: towerTop,
                    width: towerWidth, height: towerBot - towerTop
                ))
                context.fill(pole, with: .color(Color(red: 0.15, green: 0.15, blue: 0.18)))

                // Light cluster at top
                let lightCluster = Path { p in
                    p.addEllipse(in: CGRect(x: txAbs - 8, y: towerTop - 3, width: 16, height: 8))
                }
                context.fill(lightCluster, with: .color(teamColor.opacity(0.15)))

                // Glow effect
                let glow = Path(ellipseIn: CGRect(x: txAbs - 22, y: towerTop - 14, width: 44, height: 30))
                context.fill(glow, with: .radialGradient(
                    Gradient(colors: [Theme.lights.opacity(0.18), Theme.lights.opacity(0.04), .clear]),
                    center: CGPoint(x: txAbs, y: towerTop),
                    startRadius: 6,
                    endRadius: 24
                ))
            }

            // ── Field / warning track ──
            let fieldTop = structureBot
            let fieldBot = h

            // Warning track (clay-colored strip)
            let warningTrack = Path(CGRect(x: 0, y: fieldTop, width: w, height: h * 0.04))
            context.fill(warningTrack, with: .color(Theme.clay.opacity(0.6)))

            // Outfield grass
            let grassPath = Path(CGRect(x: 0, y: fieldTop + h * 0.04, width: w, height: fieldBot - fieldTop - h * 0.04))
            context.fill(grassPath, with: .linearGradient(
                Gradient(colors: [
                    Theme.grass.opacity(0.7),
                    Theme.grass.opacity(0.5),
                    Theme.grass.opacity(0.35),
                ]),
                startPoint: CGPoint(x: 0.5, y: 0),
                endPoint: CGPoint(x: 0.5, y: 1)
            ))

            // ── Foul lines on the field ──
            let foulLineY = fieldTop + h * 0.06
            var foulLine1 = Path()
            foulLine1.move(to: CGPoint(x: w * 0.48, y: foulLineY))
            foulLine1.addLine(to: CGPoint(x: w * 0.72, y: h))
            context.stroke(foulLine1, with: .color(.white.opacity(0.12)), lineWidth: 1.5)

            var foulLine2 = Path()
            foulLine2.move(to: CGPoint(x: w * 0.52, y: foulLineY))
            foulLine2.addLine(to: CGPoint(x: w * 0.28, y: h))
            context.stroke(foulLine2, with: .color(.white.opacity(0.12)), lineWidth: 1.5)

            // ── Foreground vignette ──
            let vignettePath = Path(CGRect(x: 0, y: 0, width: w, height: h))
            context.fill(vignettePath, with: .radialGradient(
                Gradient(colors: [.clear, Color.black.opacity(0.25), Color.black.opacity(0.45)]),
                center: CGPoint(x: 0.5, y: 0.55),
                startRadius: w * 0.35,
                endRadius: w * 0.8
            ))

            // ── Bottom gradient overlay for text readability ──
            let textOverlay = Path(CGRect(x: 0, y: h * 0.65, width: w, height: h * 0.35))
            context.fill(textOverlay, with: .linearGradient(
                Gradient(colors: [.clear, Color.black.opacity(0.5)]),
                startPoint: CGPoint(x: 0.5, y: 0),
                endPoint: CGPoint(x: 0.5, y: 1)
            ))
        }
    }
}
