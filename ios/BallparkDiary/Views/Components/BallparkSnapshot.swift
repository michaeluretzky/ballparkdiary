import SwiftUI
import MapKit

/// In-memory cache so each ballpark's aerial is only snapshotted once per session.
@MainActor
final class BallparkSnapshotCache {
    static let shared = BallparkSnapshotCache()
    private var cache: [String: UIImage] = [:]

    func image(for key: String) -> UIImage? { cache[key] }
    func store(_ image: UIImage, for key: String) { cache[key] = image }
}

/// A beautiful hero view for a ballpark. On devices with MapKit support it
/// loads a high-resolution satellite aerial; everywhere else (and while the
/// aerial loads) it shows a richly styled stadium card with team colors,
/// a diamond-pattern overlay, and subtle motion.
///
/// Used as the hero image on diary cards and the game-detail ballpark panel.
struct BallparkSnapshot: View {
    let ballpark: Ballpark
    /// Smaller span = tighter zoom on the stadium itself.
    var span: Double = 0.0065

    @State private var satelliteImage: UIImage?
    @State private var photoLoadFailed: Bool = false

    private var cacheKey: String { "\(ballpark.id)-\(span)" }

    private var teamColor: Color { ballpark.team.primary }
    private var teamSecondary: Color { ballpark.team.secondary }

    var body: some View {
        ZStack {
            if let satelliteImage, !photoLoadFailed {
                Image(uiImage: satelliteImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                stadiumHero
            }

            // Subtle gradient overlay for readability (used by diary cards)
            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .task(id: cacheKey) {
            await loadSatellite()
        }
    }

    // MARK: - Stadium hero (rich fallback)

    private var stadiumHero: some View {
        ZStack {
            // Deep gradient base
            LinearGradient(
                colors: [
                    teamColor.opacity(0.85),
                    teamColor.opacity(0.35),
                    Theme.nightDeep
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Diamond-pattern overlay
            diamondOverlay

            // Vignette
            RadialGradient(
                colors: [.clear, .black.opacity(0.55)],
                center: .center,
                startRadius: 30,
                endRadius: 260
            )

            // Center content — team mark and stadium name
            VStack(spacing: 10) {
                Spacer()

                // Team circle with abbreviation
                ZStack {
                    Circle()
                        .fill(teamColor)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .strokeBorder(teamSecondary, lineWidth: 2.5)
                        )
                        .shadow(color: teamColor.opacity(0.5), radius: 16, y: 4)

                    Text(ballpark.team.abbreviation)
                        .font(.headline(16, weight: .black))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 4) {
                    Text(ballpark.nickname ?? ballpark.name)
                        .font(.headline(16, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 4)
                    Text("\(ballpark.city), \(ballpark.state)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                // Bottom facts strip
                HStack(spacing: 20) {
                    heroFact(label: "Opened", value: "\(ballpark.opened)")
                    heroFact(label: "Capacity", value: ballpark.capacity.formatted(.number))
                    heroFact(label: "Roof", value: ballpark.roof.rawValue)
                }
                .padding(.bottom, 6)
            }
            .padding(16)
        }
        .animation(.easeOut(duration: 0.5), value: satelliteImage)
    }

    private func heroFact(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline(13, weight: .heavy))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(1.2)
        }
    }

    /// Artistic diamond-pattern overlay for the stadium card background.
    private var diamondOverlay: some View {
        Canvas { context, size in
            let diamondSize: CGFloat = 28
            let w = size.width / diamondSize
            let h = size.height / diamondSize
            for row in stride(from: 0, through: Int(h), by: 1) {
                for col in stride(from: 0, through: Int(w), by: 1) {
                    let x = CGFloat(col) * diamondSize
                    let y = CGFloat(row) * diamondSize
                    let path = Path { p in
                        p.move(to: CGPoint(x: x + diamondSize / 2, y: y))
                        p.addLine(to: CGPoint(x: x + diamondSize, y: y + diamondSize / 2))
                        p.addLine(to: CGPoint(x: x + diamondSize / 2, y: y + diamondSize))
                        p.addLine(to: CGPoint(x: x, y: y + diamondSize / 2))
                        p.closeSubpath()
                    }
                    context.fill(path, with: .color(.white.opacity(0.04)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Satellite loader

    private func loadSatellite() async {
        if let cached = BallparkSnapshotCache.shared.image(for: cacheKey) {
            satelliteImage = cached
            return
        }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: ballpark.coordinate,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
        options.size = CGSize(width: 640, height: 400)
        options.mapType = .satellite
        options.showsBuildings = true

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            BallparkSnapshotCache.shared.store(snapshot.image, for: cacheKey)
            satelliteImage = snapshot.image
        } catch {
            photoLoadFailed = true
        }
    }
}
