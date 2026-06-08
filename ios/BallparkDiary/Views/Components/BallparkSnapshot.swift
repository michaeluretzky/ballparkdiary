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

/// A real aerial photo of a ballpark, rendered from MapKit satellite imagery.
/// Used as the hero image on diary cards and the seat-view panel.
struct BallparkSnapshot: View {
    let ballpark: Ballpark
    /// Smaller span = tighter zoom on the stadium itself.
    var span: Double = 0.0065

    @State private var image: UIImage?

    private var cacheKey: String { "\(ballpark.id)-\(span)" }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .task(id: cacheKey) { await load() }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Theme.grass.opacity(0.45), Theme.nightDeep],
            startPoint: .top, endPoint: .bottom
        )
        .overlay {
            Image(systemName: "map.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    private func load() async {
        if let cached = BallparkSnapshotCache.shared.image(for: cacheKey) {
            image = cached
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
            image = snapshot.image
        } catch {
            // Keep the placeholder; not worth surfacing an error for imagery.
        }
    }
}
