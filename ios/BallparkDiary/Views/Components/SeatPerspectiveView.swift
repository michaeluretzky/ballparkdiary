import SwiftUI
import MapKit

/// In-memory cache so each section-highlight snapshot is only rendered once per
/// session.  Keyed by ballpark, section, and heading so different seats produce
/// different highlight placements.
@MainActor
final class SeatSnapshotCache {
    static let shared = SeatSnapshotCache()
    private var cache: [String: UIImage] = [:]
    func image(for key: String) -> UIImage? { cache[key] }
    func store(_ image: UIImage, for key: String) { cache[key] = image }
}

/// An overhead satellite map of the ballpark with the user's section highlighted
/// by a glowing spotlight — showing *where* in the stadium bowl the seat is.
///
/// Section numbers are mapped to a compass heading, then that heading determines
/// which edge of the stadium gets lit up.  A pulsing amber glow and a bearing
/// line from the diamond make it instantly readable.
struct SeatPerspectiveView: View {
    let game: AttendedGame

    // MARK: - Camera (overhead)

    /// Map the section number to a compass heading using the same heuristic as
    /// before: low sections sit behind home plate (~45° NE), higher numbers
    /// sweep clockwise around the bowl.
    /// Amber stadium-lights colour usable in Core Graphics contexts.
    private static let highlightColor = UIColor(red: 0.961, green: 0.784, blue: 0.259, alpha: 1)

    private var heading: CLLocationDirection {
        let digits = game.section.filter(\.isNumber)
        guard let n = Double(digits), n > 0 else { return 45 }
        let offset = n * 0.5
        var h = (45.0 - offset).truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        return h
    }

    /// Higher altitude for a generous overhead view that shows the full stadium
    /// and some surrounding context.
    private var distance: CLLocationDistance {
        switch game.ballpark.capacity {
        case ..<25_000: return 500
        case ..<40_000: return 600
        case ..<48_000: return 700
        default:        return 800
        }
    }

    /// Nearly top-down so the stadium layout is legible.
    private let pitch: CGFloat = 8

    // MARK: - State

    @State private var image: UIImage?
    @State private var highlightPhase: CGFloat = 0

    private var cacheKey: String {
        "seat-overhead-\(game.ballpark.id)-\(game.section)-\(Int(heading))"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }

            // Section badge — bottom-right
            if game.hasSeatInfo {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        sectionBadge
                    }
                }
            }
        }
        .task(id: cacheKey) { await load() }
    }

    private var sectionBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "location.fill")
                .font(.system(size: 8, weight: .bold))
            Text("Section \(game.section)")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Theme.lights)
                .shadow(color: Theme.lights.opacity(0.5), radius: 6, y: 2)
        )
        .padding(8)
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Theme.grass.opacity(0.20), Theme.nightDeep],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            ProgressView()
                .tint(Theme.lights.opacity(0.7))
        }
    }

    // MARK: - Snapshot + highlight drawing

    private func load() async {
        if let cached = SeatSnapshotCache.shared.image(for: cacheKey) {
            image = cached
            return
        }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: game.ballpark.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.0045, longitudeDelta: 0.0045)
        )
        options.size = CGSize(width: 640, height: 420)
        options.mapType = .satellite
        options.showsBuildings = true
        options.camera = MKMapCamera(
            lookingAtCenter: game.ballpark.coordinate,
            fromDistance: distance,
            pitch: pitch,
            heading: 0   // north-up so the overlay bearing is true
        )

        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return }

        // Convert the centre coordinate to a point on the snapshot so we know
        // where the diamond sits in image space.
        let centrePt = snapshot.point(for: game.ballpark.coordinate)

        // The section sits roughly 100–140 m from home plate in the stands.
        // At these map spans that maps to ~60–100 pt on the snapshot.
        let seatRadius: CGFloat = 85

        // Convert the heading (clockwise from north) to a UIKit/Quartz angle
        // (clockwise from the positive x-axis, which on a north-up map is right).
        let rad = CGFloat(heading) * .pi / 180
        // UIKit y is flipped vs north, so the angle visual stays correct.
        let dx = seatRadius * sin(rad)
        let dy = seatRadius * -cos(rad)
        let seatPt = CGPoint(x: centrePt.x + dx, y: centrePt.y + dy)

        // Render the snapshot with the highlight drawn on top.
        let renderer = UIGraphicsImageRenderer(size: options.size)
        let annotated = renderer.image { ctx in
            // 1. Draw the raw satellite snapshot
            snapshot.image.draw(at: .zero)

            let cg = ctx.cgContext

            // 2. Bearing line — thin amber line from diamond to section
            cg.setStrokeColor(Self.highlightColor.withAlphaComponent(0.55).cgColor)
            cg.setLineWidth(1.5)
            cg.setLineDash(phase: 0, lengths: [4, 4])
            cg.move(to: centrePt)
            cg.addLine(to: seatPt)
            cg.strokePath()

            // 3. Glowing dot at the diamond (origin marker)
            drawGlow(cg: cg, at: centrePt, radius: 12, color: Self.highlightColor.withAlphaComponent(0.3))
            let diamondDot = UIBezierPath(ovalIn: CGRect(x: centrePt.x - 4, y: centrePt.y - 4, width: 8, height: 8))
            Self.highlightColor.withAlphaComponent(0.9).setFill()
            diamondDot.fill()

            // 4. Section highlight — larger, brighter glow at the seat position
            drawGlow(cg: cg, at: seatPt, radius: 46, color: Self.highlightColor.withAlphaComponent(0.22))
            drawGlow(cg: cg, at: seatPt, radius: 26, color: Self.highlightColor.withAlphaComponent(0.35))
            drawGlow(cg: cg, at: seatPt, radius: 14, color: Self.highlightColor.withAlphaComponent(0.50))

            // 5. Section pin
            let pinR: CGFloat = 10
            let pinRect = CGRect(x: seatPt.x - pinR, y: seatPt.y - pinR, width: pinR * 2, height: pinR * 2)
            let pin = UIBezierPath(ovalIn: pinRect)
            Self.highlightColor.setFill()
            pin.fill()

            // Outer ring
            let ring = UIBezierPath(ovalIn: pinRect.insetBy(dx: -3, dy: -3))
            ring.lineWidth = 2
            Self.highlightColor.withAlphaComponent(0.7).setStroke()
            ring.stroke()

            // 6. Tiny diamond icon inside the pin
            let diamond = UIBezierPath()
            let cx = seatPt.x, cy = seatPt.y, s: CGFloat = 5
            diamond.move(to: CGPoint(x: cx, y: cy - s))
            diamond.addLine(to: CGPoint(x: cx + s, y: cy))
            diamond.addLine(to: CGPoint(x: cx, y: cy + s))
            diamond.addLine(to: CGPoint(x: cx - s, y: cy))
            diamond.close()
            UIColor.black.withAlphaComponent(0.8).setFill()
            diamond.fill()
        }

        SeatSnapshotCache.shared.store(annotated, for: cacheKey)
        image = annotated
    }

    /// Draw a soft radial glow centred at `pt` with the given `radius`.
    private func drawGlow(cg: CGContext, at pt: CGPoint, radius: CGFloat, color: UIColor) {
        let colours = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        let locations: [CGFloat] = [0, 1]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colours, locations: locations) else { return }
        cg.drawRadialGradient(
            gradient,
            startCenter: pt, startRadius: 0,
            endCenter: pt, endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
    }
}
