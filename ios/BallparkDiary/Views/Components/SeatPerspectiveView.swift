import SwiftUI

/// A stylized "view from your seat" — a perspective look at the field drawn from
/// the section the user actually sat in. The viewing angle shifts based on the
/// section number so each seat feels distinct.
struct SeatPerspectiveView: View {
    let game: AttendedGame

    /// A normalized horizontal viewing offset (-1 = far down the 3rd-base line,
    /// +1 = far down the 1st-base line), derived from the section number.
    private var viewAngle: CGFloat {
        let digits = game.section.filter(\.isNumber)
        guard let n = Int(digits) else { return 0 }
        // Map section number into a repeating -0.7...0.7 spread around home plate.
        let wrapped = Double(n % 160) / 160.0   // 0...1 around the bowl
        return CGFloat((wrapped - 0.5) * 1.4)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Night sky behind the stadium
                LinearGradient(
                    colors: [Theme.nightDeep, Theme.night],
                    startPoint: .top, endPoint: .bottom
                )

                // Outfield grass beyond the infield
                FieldGrass(angle: viewAngle)
                    .fill(Theme.grass.opacity(0.55))
                FieldGrass(angle: viewAngle)
                    .stroke(.white.opacity(0.10), lineWidth: 1)

                // Infield dirt diamond, drawn in perspective from the stands
                InfieldDiamond(angle: viewAngle)
                    .fill(Theme.clay.opacity(0.85))
                InfieldDiamond(angle: viewAngle)
                    .stroke(Theme.chalk.opacity(0.6), lineWidth: 1.5)

                // Foul lines fanning out from home plate at the bottom
                FoulLines(angle: viewAngle)
                    .stroke(Theme.chalk.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // Stadium light glow up top
                Ellipse()
                    .fill(Theme.lights.opacity(0.12))
                    .frame(width: w * 0.9, height: h * 0.35)
                    .blur(radius: 28)
                    .offset(y: -h * 0.32)

                // Foreground rail to anchor the "from the seats" feeling
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(.black.opacity(0.55))
                        .frame(height: 10)
                        .overlay(Rectangle().fill(.white.opacity(0.08)).frame(height: 2), alignment: .top)
                }
            }
        }
    }
}

private struct FieldGrass: Shape {
    let angle: CGFloat
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX + angle * rect.width * 0.22
        var p = Path()
        p.move(to: CGPoint(x: rect.minX - 20, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX - 20, y: rect.height * 0.55))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX + 20, y: rect.height * 0.55),
            control: CGPoint(x: cx, y: rect.height * 0.30)
        )
        p.addLine(to: CGPoint(x: rect.maxX + 20, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct InfieldDiamond: Shape {
    let angle: CGFloat
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX + angle * rect.width * 0.28
        let home = CGPoint(x: rect.midX, y: rect.height * 0.92)
        let second = CGPoint(x: cx, y: rect.height * 0.52)
        let first = CGPoint(x: cx + rect.width * 0.26, y: rect.height * 0.70)
        let third = CGPoint(x: cx - rect.width * 0.26, y: rect.height * 0.70)
        var p = Path()
        p.move(to: home)
        p.addLine(to: first)
        p.addLine(to: second)
        p.addLine(to: third)
        p.closeSubpath()
        return p
    }
}

private struct FoulLines: Shape {
    let angle: CGFloat
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX + angle * rect.width * 0.28
        let home = CGPoint(x: rect.midX, y: rect.height * 0.92)
        var p = Path()
        p.move(to: home)
        p.addLine(to: CGPoint(x: cx + rect.width * 0.55, y: rect.height * 0.50))
        p.move(to: home)
        p.addLine(to: CGPoint(x: cx - rect.width * 0.55, y: rect.height * 0.50))
        return p
    }
}
