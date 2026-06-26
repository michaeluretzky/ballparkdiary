import SwiftUI

/// Real baseball photo that rotates continuously — used as the brand mark.
struct BaseballMark: View {
    var size: CGFloat = 120
    @State private var rotation: Double = 0

    var body: some View {
        Image("baseball_real")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
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
