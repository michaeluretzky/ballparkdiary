import SwiftUI

/// Stylized baseball with red curved stitching used as the brand mark.
struct BaseballMark: View {
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            // Ball
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white, Color(white: 0.86)],
                        center: .init(x: 0.35, y: 0.30),
                        startRadius: size * 0.05,
                        endRadius: size * 0.7
                    )
                )
                .overlay(
                    Circle().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
                )

            // Two stitching arcs
            StitchArc(stitches: 9, side: .left)
                .stroke(Theme.foul, style: StrokeStyle(lineWidth: max(1, size * 0.022), lineCap: .round))
            StitchArc(stitches: 9, side: .right)
                .stroke(Theme.foul, style: StrokeStyle(lineWidth: max(1, size * 0.022), lineCap: .round))

            // Subtle inner ring
            Circle()
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
        }
        .frame(width: size, height: size)
    }
}

/// Draws short red stitch marks along an arc — left or right side.
struct StitchArc: Shape {
    let stitches: Int
    let side: Side
    enum Side { case left, right }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.width * 0.50
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Arc spans roughly 110 degrees on one side
        let startAngle: Double = side == .right ? -55 : 125
        let span: Double = 110
        let inset: CGFloat = r * 0.18
        let arcRadius = r - inset

        for i in 0..<stitches {
            let t = Double(i) / Double(stitches - 1)
            let angle = (startAngle + t * span) * .pi / 180
            let mid = CGPoint(x: center.x + arcRadius * CGFloat(cos(angle)),
                              y: center.y + arcRadius * CGFloat(sin(angle)))
            // Stitch direction: perpendicular to radius, slight tilt
            let stitchLength = arcRadius * 0.30
            let perp = angle + .pi / 2
            // Skew the stitch to lean
            let lean: Double = (side == .right ? -0.45 : 0.45)
            let a = perp + lean
            let dx = CGFloat(cos(a)) * stitchLength * 0.5
            let dy = CGFloat(sin(a)) * stitchLength * 0.5
            p.move(to: CGPoint(x: mid.x - dx, y: mid.y - dy))
            p.addLine(to: CGPoint(x: mid.x + dx, y: mid.y + dy))
        }
        return p
    }
}

/// Faint chalk-line baseball field as a background texture.
struct FieldLinesBackground: View {
    var body: some View {
        GeometryReader { geo in
            let size = max(geo.size.width, geo.size.height)
            Canvas { ctx, _ in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.85)
                // Foul lines
                var lines = Path()
                lines.move(to: center)
                lines.addLine(to: CGPoint(x: center.x - size, y: center.y - size))
                lines.move(to: center)
                lines.addLine(to: CGPoint(x: center.x + size, y: center.y - size))
                ctx.stroke(lines, with: .color(Theme.chalk.opacity(0.4)), lineWidth: 1)

                // Outfield arc
                var arc = Path()
                arc.addArc(center: center, radius: size * 0.55,
                           startAngle: .degrees(225), endAngle: .degrees(315), clockwise: false)
                ctx.stroke(arc, with: .color(Theme.chalk.opacity(0.35)), lineWidth: 1)

                // Infield diamond
                var diamond = Path()
                let s = size * 0.10
                diamond.move(to: CGPoint(x: center.x, y: center.y - s * 1.4))
                diamond.addLine(to: CGPoint(x: center.x + s, y: center.y - s * 0.7))
                diamond.addLine(to: CGPoint(x: center.x, y: center.y))
                diamond.addLine(to: CGPoint(x: center.x - s, y: center.y - s * 0.7))
                diamond.closeSubpath()
                ctx.stroke(diamond, with: .color(Theme.chalk.opacity(0.4)), lineWidth: 1)
            }
        }
    }
}
