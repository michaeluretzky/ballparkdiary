import SwiftUI

/// Displays a real Wikipedia Commons photo of the ballpark.
/// Falls back to a hand-drawn illustration if the photo fails to load.
struct BallparkSnapshot: View {
    let ballpark: Ballpark
    var span: Double = 0.0065 // kept for API compatibility

    private var teamColor: Color { ballpark.team.primary }

    var body: some View {
        if let photoURL = ballpark.photoURL {
            RealStadiumPhoto(url: photoURL, teamColor: teamColor, ballpark: ballpark)
        } else {
            StadiumIllustration(
                ballpark: ballpark,
                teamColor: teamColor,
                teamSecondary: ballpark.team.secondary
            )
        }
    }
}

// MARK: - Real stadium photo via AsyncImage

private struct RealStadiumPhoto: View {
    let url: URL
    let teamColor: Color
    let ballpark: Ballpark

    @State private var loadFailed = false

    var body: some View {
        ZStack {
            if loadFailed {
                // Graceful fallback when photo fails to load
                StadiumIllustration(
                    ballpark: ballpark,
                    teamColor: teamColor,
                    teamSecondary: ballpark.team.secondary
                )
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        shimmerPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        // Trigger fallback on next render
                        Color.clear
                            .onAppear { loadFailed = true }
                    @unknown default:
                        Color.clear
                            .onAppear { loadFailed = true }
                    }
                }
            }
        }
    }

    /// Animated shimmer while the photo loads.
    private var shimmerPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [teamColor.opacity(0.15), teamColor.opacity(0.08), teamColor.opacity(0.15)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

// MARK: - Stadium illustration (fallback)

private struct StadiumIllustration: View {
    let ballpark: Ballpark
    let teamColor: Color
    let teamSecondary: Color

    private var style: Ballpark.IllustrationStyle { ballpark.illustration }
    private var isClassic: Bool {
        if case .classic = style { return true }
        return false
    }
    private var isRetroClassic: Bool {
        if case .retroClassic = style { return true }
        return false
    }
    private var isRetractable: Bool {
        if case .retractable = style { return true }
        return false
    }
    private var isDome: Bool {
        if case .dome = style { return true }
        return false
    }
    private var isLandmark: Bool {
        if case .landmark = style { return true }
        return false
    }

    private var landmarkName: String? {
        if case .landmark(let name) = style { return name }
        return nil
    }

    private var marqueeColorHex: String? {
        if case .classic(let color) = style { return color }
        return nil
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            drawSky(context: &context, w: w, h: h)
            drawStars(context: &context, w: w, h: h)
            drawMoon(context: &context, w: w, h: h)

            if let landmark = landmarkName {
                drawLandmark(context: &context, w: w, h: h, landmark: landmark)
            }

            drawStadium(context: &context, w: w, h: h)
            drawMarquee(context: &context, w: w, h: h)
            drawField(context: &context, w: w, h: h)

            if style.hasWaterFeature {
                drawWaterFeature(context: &context, w: w, h: h)
            }

            drawVignette(context: &context, w: w, h: h)
        }
    }

    // MARK: - Sky

    private func drawSky(context: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let topColor: Color
        let bottomColor: Color

        if isDome {
            topColor = Color(red: 0.04, green: 0.09, blue: 0.22)
            bottomColor = Color(red: 0.10, green: 0.15, blue: 0.30)
        } else if isLandmark {
            topColor = Color(red: 0.02, green: 0.05, blue: 0.18)
            bottomColor = Color(red: 0.08, green: 0.14, blue: 0.34)
        } else {
            topColor = Color(red: 0.02, green: 0.06, blue: 0.20)
            bottomColor = Color(red: 0.06, green: 0.12, blue: 0.30)
        }

        let skyGradient = Gradient(colors: [topColor, bottomColor])
        context.fill(
            Path(CGRect(x: 0, y: 0, width: w, height: h)),
            with: .linearGradient(skyGradient, startPoint: CGPoint(x: 0.5, y: 0), endPoint: CGPoint(x: 0.5, y: 1))
        )
    }

    // MARK: - Stars

    private func drawStars(context: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let starData: [(CGFloat, CGFloat, CGFloat)] = [
            (0.10, 0.10, 1.6), (0.25, 0.05, 1.2), (0.42, 0.13, 2.0),
            (0.60, 0.07, 1.4), (0.75, 0.10, 1.1), (0.90, 0.04, 1.7),
            (0.16, 0.20, 0.9), (0.52, 0.17, 1.2), (0.82, 0.22, 0.8),
            (0.30, 0.03, 1.5), (0.68, 0.04, 1.0), (0.07, 0.17, 0.7),
            (0.93, 0.15, 0.9), (0.38, 0.24, 0.6), (0.14, 0.29, 0.5),
        ]
        for (rx, ry, rs) in starData {
            let cx = rx * w
            let cy = ry * h
            let r = rs * 1.2
            var star = Path()
            star.move(to: CGPoint(x: cx, y: cy - r))
            star.addLine(to: CGPoint(x: cx + r * 0.35, y: cy - r * 0.25))
            star.addLine(to: CGPoint(x: cx + r, y: cy))
            star.addLine(to: CGPoint(x: cx + r * 0.35, y: cy + r * 0.25))
            star.addLine(to: CGPoint(x: cx, y: cy + r))
            star.addLine(to: CGPoint(x: cx - r * 0.35, y: cy + r * 0.25))
            star.addLine(to: CGPoint(x: cx - r, y: cy))
            star.addLine(to: CGPoint(x: cx - r * 0.35, y: cy - r * 0.25))
            star.closeSubpath()
            context.fill(star, with: .color(.white.opacity(0.45 + Double.random(in: 0...0.45))))
        }
    }

    // MARK: - Moon

    private func drawMoon(context: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let moonX = w * 0.84
        let moonY: CGFloat = isLandmark ? h * 0.18 : h * 0.13
        let moonR: CGFloat = 15

        let glowPath = Path(ellipseIn: CGRect(
            x: moonX - moonR * 2.5, y: moonY - moonR * 2.5,
            width: moonR * 5, height: moonR * 5
        ))
        context.fill(glowPath, with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0.10), .clear]),
            center: CGPoint(x: moonX, y: moonY),
            startRadius: moonR,
            endRadius: moonR * 2.5
        ))
        let moonPath = Path(ellipseIn: CGRect(
            x: moonX - moonR, y: moonY - moonR,
            width: moonR * 2, height: moonR * 2
        ))
        context.fill(moonPath, with: .color(Color(red: 0.95, green: 0.93, blue: 0.85)))
    }

    // MARK: - Landmark silhouette

    private func drawLandmark(context: inout GraphicsContext, w: CGFloat, h: CGFloat, landmark: String) {
        let horizonY = stadiumTop(h)
        let landmarkColor = Color.white.opacity(0.06)

        switch landmark {
        case "Gateway Arch":
            let cx = w * 0.82
            let baseY = horizonY - 8
            let archHeight: CGFloat = h * 0.18
            var arch = Path()
            arch.move(to: CGPoint(x: cx - 28, y: baseY))
            arch.addCurve(
                to: CGPoint(x: cx + 28, y: baseY),
                control1: CGPoint(x: cx - 28, y: baseY - archHeight),
                control2: CGPoint(x: cx + 28, y: baseY - archHeight)
            )
            context.stroke(arch, with: .color(landmarkColor), lineWidth: 3)
        case "CN Tower":
            let cx = w * 0.78
            let baseY = horizonY - 4
            let towerTop = horizonY - h * 0.22
            var tower = Path()
            tower.move(to: CGPoint(x: cx - 2, y: baseY))
            tower.addLine(to: CGPoint(x: cx - 1.5, y: towerTop + h * 0.04))
            tower.addLine(to: CGPoint(x: cx - 3, y: towerTop + h * 0.04))
            tower.addLine(to: CGPoint(x: cx - 3, y: towerTop))
            tower.addLine(to: CGPoint(x: cx + 3, y: towerTop))
            tower.addLine(to: CGPoint(x: cx + 3, y: towerTop + h * 0.04))
            tower.addLine(to: CGPoint(x: cx + 1.5, y: towerTop + h * 0.04))
            tower.addLine(to: CGPoint(x: cx + 2, y: baseY))
            tower.closeSubpath()
            context.fill(tower, with: .color(landmarkColor))
            let pod = Path(ellipseIn: CGRect(x: cx - 5, y: towerTop - 3, width: 10, height: 8))
            context.fill(pod, with: .color(landmarkColor))
        case "Clemente Bridge":
            let leftX = w * 0.55
            let bridgeY = horizonY - 30
            for i in 0..<3 {
                let bx = leftX + CGFloat(i) * 16
                var arch = Path()
                arch.move(to: CGPoint(x: bx, y: horizonY))
                arch.addLine(to: CGPoint(x: bx, y: bridgeY))
                arch.addLine(to: CGPoint(x: bx + 10, y: bridgeY))
                arch.addLine(to: CGPoint(x: bx + 10, y: horizonY))
                context.fill(arch, with: .color(landmarkColor))
            }
        case "B&O Warehouse":
            let wx = w * 0.58
            let wy = horizonY - h * 0.12
            let bw: CGFloat = 50
            let bh = horizonY - wy
            var warehouse = Path(CGRect(x: wx, y: wy, width: bw, height: bh))
            context.fill(warehouse, with: .color(landmarkColor))
            for row in 0..<4 {
                for col in 0..<5 {
                    let winX = wx + 6 + CGFloat(col) * 9
                    let winY = wy + 8 + CGFloat(row) * 10
                    let win = Path(CGRect(x: winX, y: winY, width: 5, height: 5))
                    context.fill(win, with: .color(Color.white.opacity(0.03)))
                }
            }
        case "Space Needle":
            let cx = w * 0.80
            let baseY = horizonY - 4
            let needleTop = horizonY - h * 0.20
            var needle = Path()
            needle.move(to: CGPoint(x: cx - 1.5, y: baseY))
            needle.addLine(to: CGPoint(x: cx - 2, y: needleTop + h * 0.05))
            needle.addLine(to: CGPoint(x: cx - 5, y: needleTop + h * 0.04))
            needle.addLine(to: CGPoint(x: cx - 5, y: needleTop))
            needle.addLine(to: CGPoint(x: cx + 5, y: needleTop))
            needle.addLine(to: CGPoint(x: cx + 5, y: needleTop + h * 0.04))
            needle.addLine(to: CGPoint(x: cx + 2, y: needleTop + h * 0.05))
            needle.addLine(to: CGPoint(x: cx + 1.5, y: baseY))
            needle.closeSubpath()
            context.fill(needle, with: .color(landmarkColor))
        case "Rocky Mountains":
            let peaks: [(CGFloat, CGFloat)] = [
                (0.65, 0.38), (0.72, 0.22), (0.78, 0.30), (0.85, 0.18), (0.92, 0.28)
            ]
            var mountains = Path()
            let my = horizonY
            mountains.move(to: CGPoint(x: w * 0.58, y: my))
            for (px, ph) in peaks {
                mountains.addLine(to: CGPoint(x: w * px, y: h * ph))
                mountains.addLine(to: CGPoint(x: w * (px + 0.04), y: my))
            }
            mountains.addLine(to: CGPoint(x: w * 0.98, y: my))
            mountains.closeSubpath()
            context.fill(mountains, with: .color(landmarkColor.opacity(1.5)))
        case "Capitol":
            let cx = w * 0.81
            let domeY = horizonY - h * 0.10
            var dome = Path()
            dome.addArc(
                center: CGPoint(x: cx, y: domeY + 18),
                radius: 20,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: true
            )
            dome.closeSubpath()
            context.fill(dome, with: .color(landmarkColor))
            let base = Path(CGRect(x: cx - 14, y: domeY + 16, width: 28, height: 14))
            context.fill(base, with: .color(landmarkColor))
        default:
            let buildings: [(CGFloat, CGFloat, CGFloat)] = [
                (0.60, 0.35, 16), (0.65, 0.28, 20), (0.70, 0.32, 14),
                (0.75, 0.24, 24), (0.80, 0.30, 18), (0.85, 0.34, 12),
            ]
            for (bx, bhFrac, bw) in buildings {
                let bxAbs = bx * w
                let byAbs = horizonY
                let bhAbs = h * bhFrac
                let building = Path(CGRect(x: bxAbs, y: byAbs - bhAbs, width: bw, height: bhAbs))
                context.fill(building, with: .color(landmarkColor))
            }
        }
    }

    // MARK: - Stadium structure

    private func stadiumTop(_ h: CGFloat) -> CGFloat { h * 0.32 }
    private func stadiumBottom(_ h: CGFloat) -> CGFloat {
        if isDome { return h * 0.54 }
        return h * 0.56
    }

    private func drawStadium(context: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let sTop = stadiumTop(h)
        let sBot = stadiumBottom(h)
        let sHeight = sBot - sTop

        if isDome {
            drawDomeStructure(context: &context, w: w, h: h, sTop: sTop, sBot: sBot, sHeight: sHeight)
        } else if isRetractable {
            drawRetractableStructure(context: &context, w: w, h: h, sTop: sTop, sBot: sBot, sHeight: sHeight)
        } else if isClassic {
            drawClassicStructure(context: &context, w: w, h: h, sTop: sTop, sBot: sBot, sHeight: sHeight)
        } else {
            drawModernStructure(context: &context, w: w, h: h, sTop: sTop, sBot: sBot, sHeight: sHeight)
        }

        drawLightTowers(context: &context, w: w, h: h, sTop: sTop, sHeight: sHeight)
    }

    private func drawClassicStructure(context: inout GraphicsContext, w: CGFloat, h: CGFloat, sTop: CGFloat, sBot: CGFloat, sHeight: CGFloat) {
        let darkColor = Color(red: 0.03, green: 0.04, blue: 0.08)
        let midColor = Color(red: 0.06, green: 0.08, blue: 0.14)
        let arcColor = teamColor

        var grandstand = Path()
        grandstand.move(to: CGPoint(x: w * 0.04, y: sTop + sHeight * 0.50))
        grandstand.addCurve(
            to: CGPoint(x: w * 0.96, y: sTop + sHeight * 0.50),
            control1: CGPoint(x: w * 0.22, y: sTop - sHeight * 0.05),
            control2: CGPoint(x: w * 0.78, y: sTop - sHeight * 0.05)
        )
        grandstand.addLine(to: CGPoint(x: w * 0.96, y: sBot))
        grandstand.addLine(to: CGPoint(x: w * 0.04, y: sBot))
        grandstand.closeSubpath()
        context.fill(grandstand, with: .color(darkColor))

        var upperDeck = Path()
        upperDeck.move(to: CGPoint(x: w * 0.05, y: sTop + sHeight * 0.58))
        upperDeck.addCurve(
            to: CGPoint(x: w * 0.95, y: sTop + sHeight * 0.58),
            control1: CGPoint(x: w * 0.23, y: sTop + sHeight * 0.12),
            control2: CGPoint(x: w * 0.77, y: sTop + sHeight * 0.12)
        )
        upperDeck.addLine(to: CGPoint(x: w * 0.95, y: sBot))
        upperDeck.addLine(to: CGPoint(x: w * 0.05, y: sBot))
        upperDeck.closeSubpath()
        context.fill(upperDeck, with: .color(midColor))

        let archCount = 9
        let archSpan = w * 0.82 / CGFloat(archCount)
        let archStartX = w * 0.09
        let archTop = sBot - sHeight * 0.28
        let archBot = sBot

        for i in 0..<archCount {
            let cx = archStartX + archSpan * CGFloat(i) + archSpan * 0.08
            let aw = archSpan * 0.50
            let ah = archBot - archTop

            var arch = Path()
            arch.move(to: CGPoint(x: cx - aw / 2, y: archBot))
            arch.addLine(to: CGPoint(x: cx - aw / 2, y: archTop + ah * 0.18))
            arch.addCurve(
                to: CGPoint(x: cx + aw / 2, y: archTop + ah * 0.18),
                control1: CGPoint(x: cx - aw / 2, y: archTop),
                control2: CGPoint(x: cx + aw / 2, y: archTop)
            )
            arch.addLine(to: CGPoint(x: cx + aw / 2, y: archBot))
            arch.closeSubpath()
            context.fill(arch, with: .color(arcColor.opacity(0.25)))
            context.stroke(arch, with: .color(arcColor.opacity(0.30)), lineWidth: 1)
        }

        if ballpark.id == "wrigley-field" {
            let ivyY = sBot
            let ivyH: CGFloat = sHeight * 0.18
            let ivyPath = Path(CGRect(x: w * 0.06, y: ivyY, width: w * 0.88, height: ivyH))
            context.fill(ivyPath, with: .color(Theme.grass.opacity(0.55)))
            for _ in 0..<30 {
                let dx = CGFloat.random(in: w * 0.06...w * 0.94)
                let dy = CGFloat.random(in: ivyY...ivyY + ivyH)
                let dot = Path(ellipseIn: CGRect(x: dx, y: dy, width: 3, height: 2))
                context.fill(dot, with: .color(Theme.grass.opacity(0.8)))
            }
        }
    }

    private func drawModernStructure(context: inout GraphicsContext, w: CGFloat, h: CGFloat, sTop: CGFloat, sBot: CGFloat, sHeight: CGFloat) {
        let darkColor = Color(red: 0.03, green: 0.04, blue: 0.08)
        let midColor = Color(red: 0.06, green: 0.08, blue: 0.14)

        var block = Path()
        block.move(to: CGPoint(x: w * 0.03, y: sTop + sHeight * 0.45))
        block.addCurve(
            to: CGPoint(x: w * 0.97, y: sTop + sHeight * 0.45),
            control1: CGPoint(x: w * 0.20, y: sTop + sHeight * 0.05),
            control2: CGPoint(x: w * 0.80, y: sTop + sHeight * 0.05)
        )
        block.addLine(to: CGPoint(x: w * 0.97, y: sBot))
        block.addLine(to: CGPoint(x: w * 0.03, y: sBot))
        block.closeSubpath()
        context.fill(block, with: .color(darkColor))

        var upper = Path()
        upper.move(to: CGPoint(x: w * 0.04, y: sTop + sHeight * 0.52))
        upper.addCurve(
            to: CGPoint(x: w * 0.96, y: sTop + sHeight * 0.52),
            control1: CGPoint(x: w * 0.21, y: sTop + sHeight * 0.18),
            control2: CGPoint(x: w * 0.79, y: sTop + sHeight * 0.18)
        )
        upper.addLine(to: CGPoint(x: w * 0.96, y: sBot))
        upper.addLine(to: CGPoint(x: w * 0.04, y: sBot))
        upper.closeSubpath()
        context.fill(upper, with: .color(midColor))

        let bandY = sTop + sHeight * 0.52
        let band = Path(CGRect(x: w * 0.05, y: bandY, width: w * 0.90, height: 2))
        context.fill(band, with: .color(Theme.lights.opacity(0.12)))

        let boardW: CGFloat = w * 0.22
        let boardH: CGFloat = sHeight * 0.18
        let boardX = w * 0.39
        let boardY = sTop + sHeight * 0.30
        let board = Path(CGRect(x: boardX, y: boardY, width: boardW, height: boardH))
        context.fill(board, with: .color(teamColor.opacity(0.10)))
        context.stroke(board, with: .color(teamColor.opacity(0.18)), lineWidth: 1)
    }

    private func drawDomeStructure(context: inout GraphicsContext, w: CGFloat, h: CGFloat, sTop: CGFloat, sBot: CGFloat, sHeight: CGFloat) {
        let domeColor = Color(red: 0.04, green: 0.06, blue: 0.12)
        var dome = Path()
        dome.move(to: CGPoint(x: w * 0.05, y: sBot))
        dome.addCurve(
            to: CGPoint(x: w * 0.95, y: sBot),
            control1: CGPoint(x: w * 0.05, y: sTop - sHeight * 0.25),
            control2: CGPoint(x: w * 0.95, y: sTop - sHeight * 0.25)
        )
        dome.addLine(to: CGPoint(x: w * 0.95, y: sBot))
        dome.closeSubpath()
        context.fill(dome, with: .color(domeColor))
        for i in 1...5 {
            let ly = sTop - sHeight * 0.25 + (sHeight * 1.25) * (CGFloat(i) / 6.0)
            var line = Path()
            line.move(to: CGPoint(x: w * 0.10, y: ly))
            line.addLine(to: CGPoint(x: w * 0.90, y: ly))
            context.stroke(line, with: .color(Color.white.opacity(0.03)), lineWidth: 1)
        }
        let archCount = 7
        let archSpan = w * 0.76 / CGFloat(archCount)
        let archStartX = w * 0.12
        for i in 0..<archCount {
            let cx = archStartX + archSpan * CGFloat(i) + archSpan * 0.08
            let aw = archSpan * 0.45
            let ah = sHeight * 0.20
            var arch = Path()
            arch.move(to: CGPoint(x: cx - aw / 2, y: sBot - 1))
            arch.addLine(to: CGPoint(x: cx - aw / 2, y: sBot - ah * 0.70))
            arch.addCurve(
                to: CGPoint(x: cx + aw / 2, y: sBot - ah * 0.70),
                control1: CGPoint(x: cx - aw / 2, y: sBot - ah),
                control2: CGPoint(x: cx + aw / 2, y: sBot - ah)
            )
            arch.addLine(to: CGPoint(x: cx + aw / 2, y: sBot - 1))
            arch.closeSubpath()
            context.fill(arch, with: .color(teamColor.opacity(0.15)))
            context.stroke(arch, with: .color(teamColor.opacity(0.22)), lineWidth: 1)
        }
    }

    private func drawRetractableStructure(context: inout GraphicsContext, w: CGFloat, h: CGFloat, sTop: CGFloat, sBot: CGFloat, sHeight: CGFloat) {
        let darkColor = Color(red: 0.03, green: 0.05, blue: 0.10)
        let midColor = Color(red: 0.05, green: 0.08, blue: 0.16)

        var main = Path()
        main.move(to: CGPoint(x: w * 0.03, y: sTop + sHeight * 0.42))
        main.addCurve(
            to: CGPoint(x: w * 0.97, y: sTop + sHeight * 0.42),
            control1: CGPoint(x: w * 0.18, y: sTop + sHeight * 0.02),
            control2: CGPoint(x: w * 0.82, y: sTop + sHeight * 0.02)
        )
        main.addLine(to: CGPoint(x: w * 0.97, y: sBot))
        main.addLine(to: CGPoint(x: w * 0.03, y: sBot))
        main.closeSubpath()
        context.fill(main, with: .color(darkColor))

        let roofY = sTop + sHeight * 0.30
        var roofTrack = Path()
        roofTrack.move(to: CGPoint(x: w * 0.08, y: roofY))
        roofTrack.addCurve(
            to: CGPoint(x: w * 0.92, y: roofY),
            control1: CGPoint(x: w * 0.20, y: roofY - sHeight * 0.08),
            control2: CGPoint(x: w * 0.80, y: roofY - sHeight * 0.08)
        )
        context.stroke(roofTrack, with: .color(teamColor.opacity(0.15)), lineWidth: 2)

        for i in 0..<8 {
            let bx = w * 0.10 + CGFloat(i) * w * 0.10
            let byTop = roofY - sHeight * 0.06 * (i % 2 == 0 ? 1 : 0.5)
            var beam = Path()
            beam.move(to: CGPoint(x: bx, y: byTop))
            beam.addLine(to: CGPoint(x: bx, y: sBot))
            context.stroke(beam, with: .color(Color.white.opacity(0.02)), lineWidth: 2)
        }

        var upper = Path()
        upper.move(to: CGPoint(x: w * 0.04, y: sTop + sHeight * 0.50))
        upper.addCurve(
            to: CGPoint(x: w * 0.96, y: sTop + sHeight * 0.50),
            control1: CGPoint(x: w * 0.20, y: sTop + sHeight * 0.15),
            control2: CGPoint(x: w * 0.80, y: sTop + sHeight * 0.15)
        )
        upper.addLine(to: CGPoint(x: w * 0.96, y: sBot))
        upper.addLine(to: CGPoint(x: w * 0.04, y: sBot))
        upper.closeSubpath()
        context.fill(upper, with: .color(midColor))
    }

    // MARK: - Light towers

    private func drawLightTowers(context: inout GraphicsContext, w: CGFloat, h: CGFloat, sTop: CGFloat, sHeight: CGFloat) {
        let towerData: [(CGFloat, CGFloat)] = isClassic
            ? [(0.10, 0.22), (0.26, 0.16), (0.50, 0.12), (0.74, 0.16), (0.90, 0.22)]
            : [(0.12, 0.24), (0.28, 0.18), (0.50, 0.14), (0.72, 0.18), (0.88, 0.24)]

        for (tx, ty) in towerData {
            let txAbs = tx * w
            let towerTop = ty * h
            let towerBot = sTop + sHeight * 0.42
            let poleW: CGFloat = 2.5

            let pole = Path(CGRect(x: txAbs - poleW / 2, y: towerTop, width: poleW, height: towerBot - towerTop))
            context.fill(pole, with: .color(Color(red: 0.14, green: 0.14, blue: 0.17)))

            let cluster = Path(ellipseIn: CGRect(x: txAbs - 7, y: towerTop - 2, width: 14, height: 7))
            context.fill(cluster, with: .color(teamColor.opacity(0.12)))

            let glow = Path(ellipseIn: CGRect(x: txAbs - 20, y: towerTop - 12, width: 40, height: 26))
            context.fill(glow, with: .radialGradient(
                Gradient(colors: [Theme.lights.opacity(0.16), Theme.lights.opacity(0.03), .clear]),
                center: CGPoint(x: txAbs, y: towerTop),
                startRadius: 5,
                endRadius: 22
            ))
        }
    }

    // MARK: - Marquee sign

    private func drawMarquee(context: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let sTop = stadiumTop(h)
        let sHeight = stadiumBottom(h) - sTop
        guard isClassic || isRetroClassic else { return }

        let marqueeColor: Color
        if let hex = marqueeColorHex {
            marqueeColor = Color(hex: hex)
        } else {
            marqueeColor = teamColor
        }

        let mx = w * 0.22
        let mw = w * 0.56
        let my = sTop + sHeight * 0.08
        let mh: CGFloat = 18

        let bg = Path(roundedRect: CGRect(x: mx, y: my, width: mw, height: mh), cornerRadius: 4)
        context.fill(bg, with: .color(marqueeColor.opacity(0.85)))
        context.stroke(bg, with: .color(Color.white.opacity(0.3)), lineWidth: 1)

        let textColor = Color.white.opacity(0.85)
        let name = ballpark.name.uppercased()
        let charWidth: CGFloat = 4.5
        let totalChars = CGFloat(name.count)
        let startX = mx + (mw - totalChars * charWidth) / 2 + 1
        let charY = my + 4

        for (i, _) in name.enumerated() {
            let segments: [(CGFloat, CGFloat)] = [
                (0, 0), (0.8, 0.2), (1.5, 0.5), (0.8, 0.8), (0, 1.0),
                (2.5, 0), (3.3, 0.2), (3.3, 1.0),
                (4.0, 0), (4.0, 1.0),
            ]
            let cx = startX + CGFloat(i) * charWidth
            for (sx, sy) in segments.prefix(5 + i % 3) {
                let x = cx + sx * 0.8
                let y = charY + sy * 8
                let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 2))
                context.fill(dot, with: .color(textColor))
            }
        }

        for i in 0..<Int(mw / 6) {
            let bx = mx + CGFloat(i) * 6
            let bulb = Path(ellipseIn: CGRect(x: bx, y: my + mh - 1, width: 3, height: 3))
            context.fill(bulb, with: .color(Theme.lights.opacity(0.5)))
        }
    }

    // MARK: - Field

    private func drawField(context: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let fieldTop = stadiumBottom(h)
        let fieldBot = h

        let trackH = h * 0.04
        let track = Path(CGRect(x: 0, y: fieldTop, width: w, height: trackH))
        context.fill(track, with: .color(Theme.clay.opacity(0.55)))

        let grassPath = Path(CGRect(x: 0, y: fieldTop + trackH, width: w, height: fieldBot - fieldTop - trackH))
        context.fill(grassPath, with: .linearGradient(
            Gradient(colors: [Theme.grass.opacity(0.7), Theme.grass.opacity(0.45), Theme.grass.opacity(0.3)]),
            startPoint: CGPoint(x: 0.5, y: 0),
            endPoint: CGPoint(x: 0.5, y: 1)
        ))

        let foulY = fieldTop + trackH + 4
        var foul1 = Path()
        foul1.move(to: CGPoint(x: w * 0.47, y: foulY))
        foul1.addLine(to: CGPoint(x: w * 0.72, y: h))
        context.stroke(foul1, with: .color(.white.opacity(0.10)), lineWidth: 1.5)

        var foul2 = Path()
        foul2.move(to: CGPoint(x: w * 0.53, y: foulY))
        foul2.addLine(to: CGPoint(x: w * 0.28, y: h))
        context.stroke(foul2, with: .color(.white.opacity(0.10)), lineWidth: 1.5)
    }

    // MARK: - Water feature

    private func drawWaterFeature(context: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let fieldTop = stadiumBottom(h)
        let waterY = fieldTop + h * 0.02
        let waterH = h * 0.06

        for i in 0..<8 {
            let wy = waterY + CGFloat(i) * 1.5
            var ripple = Path()
            ripple.move(to: CGPoint(x: w * 0.55, y: wy))
            ripple.addLine(to: CGPoint(x: w * 0.92, y: wy + 1))
            context.stroke(ripple, with: .color(Color(red: 0.12, green: 0.35, blue: 0.55).opacity(0.3)), lineWidth: 1)
        }
    }

    // MARK: - Vignette

    private func drawVignette(context: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let vignettePath = Path(CGRect(x: 0, y: 0, width: w, height: h))
        context.fill(vignettePath, with: .radialGradient(
            Gradient(colors: [.clear, Color.black.opacity(0.22), Color.black.opacity(0.40)]),
            center: CGPoint(x: 0.5, y: 0.55),
            startRadius: w * 0.32,
            endRadius: w * 0.78
        ))

        let textOverlay = Path(CGRect(x: 0, y: h * 0.68, width: w, height: h * 0.32))
        context.fill(textOverlay, with: .linearGradient(
            Gradient(colors: [.clear, Color.black.opacity(0.55)]),
            startPoint: CGPoint(x: 0.5, y: 0),
            endPoint: CGPoint(x: 0.5, y: 1)
        ))
    }
}
