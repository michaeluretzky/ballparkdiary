import SwiftUI
import MapKit

/// In-memory cache so each seat-perspective snapshot is only
/// rendered once per session.
@MainActor
final class SeatSnapshotCache {
    static let shared = SeatSnapshotCache()
    private var cache: [String: UIImage] = [:]
    func image(for key: String) -> UIImage? { cache[key] }
    func store(_ image: UIImage, for key: String) { cache[key] = image }
}

/// A real 3D satellite-flyover view of the ballpark field, rendered from the
/// approximate angle of the user's section using Apple Maps' 3D stadium models.
///
/// Section numbers are mapped to compass headings so the camera "sits" in the
/// right part of the bowl and looks toward the infield — behind home plate
/// (low numbers) faces center field, higher sections sweep clockwise around
/// the stadium.  Combined with an angled pitch this produces a genuinely
/// different perspective for each seat.
struct SeatPerspectiveView: View {
    let game: AttendedGame

    // MARK: - Camera parameters

    /// Map the section number to a compass heading.  MLB parks are typically
    /// oriented with home plate south‑west and center field north‑east, so
    /// behind‑home‑plate sections (low numbers) look toward ~45° (NE).  Each
    /// 2 section units sweep 1° clockwise — section 360 lands at ~225° (CF
    /// looking back toward home).
    private var heading: CLLocationDirection {
        let digits = game.section.filter(\.isNumber)
        guard let n = Double(digits), n > 0 else { return 45 }
        let offset = n * 0.5
        var h = (45.0 - offset).truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        return h
    }

    /// Camera altitude in metres — scale with ballpark capacity so tiny parks
    /// aren't lost and big stadiums aren't cropped.
    private var distance: CLLocationDistance {
        switch game.ballpark.capacity {
        case ..<25_000: return 280
        case ..<40_000: return 340
        case ..<48_000: return 400
        default:        return 450
        }
    }

    /// Pitch from nadir.  62° gives a believable "sitting in the stands"
    /// angle without the 3D buildings flattening too much.
    private let pitch: CGFloat = 62

    // MARK: - State

    @State private var image: UIImage?

    private var cacheKey: String {
        "seat-\(game.ballpark.id)-\(game.section)-\(Int(heading))-\(Int(distance))"
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

            // Subtle section badge in bottom-right corner
            if game.hasSeatInfo {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Section \(game.section)")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.5), in: .capsule)
                            .padding(6)
                    }
                }
            }
        }
        .task(id: cacheKey) { await load() }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Theme.grass.opacity(0.30), Theme.nightDeep],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            ProgressView()
                .tint(Theme.lights.opacity(0.7))
        }
    }

    // MARK: - Snapshot

    private func load() async {
        if let cached = SeatSnapshotCache.shared.image(for: cacheKey) {
            image = cached
            return
        }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: game.ballpark.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.0030, longitudeDelta: 0.0030)
        )
        options.size = CGSize(width: 640, height: 420)
        options.mapType = .satelliteFlyover
        options.showsBuildings = true
        options.camera = MKMapCamera(
            lookingAtCenter: game.ballpark.coordinate,
            fromDistance: distance,
            pitch: pitch,
            heading: heading
        )

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            SeatSnapshotCache.shared.store(snapshot.image, for: cacheKey)
            image = snapshot.image
        } catch {
            // Keep the placeholder — not worth surfacing an error for imagery.
        }
    }
}
