import SwiftUI
import MapKit

/// In-memory cache for section-perspective snapshots. Each unique
/// (ballpark, section) combination gets a single render per session.
@MainActor
final class SeatSnapshotCache {
    static let shared = SeatSnapshotCache()
    private var cache: [String: UIImage] = [:]

    func image(for key: String) -> UIImage? { cache[key] }
    func store(_ image: UIImage, for key: String) { cache[key] = image }
}

/// A realistic 3D satellite view from the user's seat section, looking
/// toward the field. Uses MapKit's 3D camera positioned in the stands
/// at the correct height and heading for the section, so the user sees
/// the actual ballpark as it would appear from their seat — not a
/// top-down map.
///
/// Section numbers map to positions around the seating bowl:
/// - Behind home plate (low numbers, Field Box) → camera faces center field
/// - 1st base side (mid numbers) → camera positioned in right field, faces infield
/// - 3rd base side (high numbers) → camera positioned in left field, faces infield
/// - Outfield / Bleachers → camera faces in toward home plate
///
/// Level is inferred from the section prefix or label:
/// - 100-level / Field Box → close to the field, lower altitude
/// - 200-level / Club → mid-deck height
/// - 300-level / Grandstand / Terrace / Upper → upper deck
struct SeatPerspectiveView: View {
    let game: AttendedGame

    // MARK: - Section analysis

    /// General area of the stadium the section is in.
    private enum BowlArea {
        case behindHome    // directly behind home plate
        case firstBase     // 1st base / right field side
        case thirdBase     // 3rd base / left field side
        case outfield      // bleachers / outfield seating
    }

    /// Vertical level of the section.
    private enum SeatLevel {
        case field    // ~25m altitude, closest to the action
        case club     // ~45m, mid-level
        case upper    // ~60m, upper deck
    }

    private var bowlArea: BowlArea {
        let lower = game.section.lowercased()

        // Explicit labels take priority
        if lower.contains("bleacher") || lower.contains("outfield") || lower.contains("pavilion") {
            return .outfield
        }

        // Parse the numeric portion
        let digits = game.section.filter(\.isNumber)
        guard let n = Int(digits) else { return .behindHome }

        // Most stadiums number sections starting behind home plate,
        // increasing down the baselines. Low numbers = home plate area.
        let sectionMod = n % 100 // strip the level prefix

        switch sectionMod {
        case 1...16:  return .behindHome
        case 17...30: return .firstBase
        case 31...44: return .firstBase
        default:      return .thirdBase
        }
    }

    private var seatLevel: SeatLevel {
        let lower = game.section.lowercased()
        if lower.contains("grandstand") || lower.contains("terrace") || lower.contains("upper")
            || lower.contains("reserve") || lower.contains("view") {
            return .upper
        }
        if lower.contains("club") || lower.contains("suite") || lower.contains("premium") {
            return .club
        }

        let digits = game.section.filter(\.isNumber)
        guard let n = Int(digits) else { return .field }

        let firstDigit = String(n).first.flatMap { Int(String($0)) } ?? 1
        switch firstDigit {
        case 1: return .field
        case 2: return .club
        case 3...9: return .upper
        default: return .field
        }
    }

    // MARK: - Camera parameters

    /// Direction the camera faces — from the section toward the field.
    private var cameraHeading: CLLocationDirection {
        switch bowlArea {
        case .behindHome: return 45     // from behind home plate, looking toward center
        case .firstBase:  return 320    // from right field, looking across infield
        case .thirdBase:  return 130    // from left field, looking across infield
        case .outfield:   return 225    // from center field, looking in toward home
        }
    }

    /// Distance from the focal point (home plate area) to the camera.
    private var cameraDistance: CLLocationDistance {
        switch seatLevel {
        case .field: return 110
        case .club:  return 140
        case .upper: return 175
        }
    }

    /// Pitch angle — how much the camera tilts down toward the field.
    /// 0 = straight down (nadir), 90 = horizon.
    private var cameraPitch: CGFloat {
        switch seatLevel {
        case .field: return 50
        case .club:  return 58
        case .upper: return 65
        }
    }

    /// Tighter span for the 3D perspective.
    private var mapSpan: Double {
        switch seatLevel {
        case .field: return 0.0030
        case .club:  return 0.0035
        case .upper: return 0.0040
        }
    }

    // MARK: - State

    @State private var image: UIImage?

    private var cacheKey: String {
        "seat-3d-\(game.ballpark.id)-\(game.section)-\(bowlArea)-\(seatLevel)"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderView
            }

            // Subtle vignette — darkens edges for a photo-from-the-stands feel
            Rectangle()
                .fill(.clear)
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.30), .clear, .black.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.25), .clear, .black.opacity(0.25)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .allowsHitTesting(false)

            // Section badge — bottom-right
            if game.hasSeatInfo {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        sectionLabel
                    }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .task(id: cacheKey) { await load() }
    }

    private var sectionLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "location.fill")
                .font(.system(size: 8, weight: .bold))
            Text("Section \(game.section)")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Theme.lights)
                .shadow(color: Theme.lights.opacity(0.45), radius: 6, y: 2)
        )
        .padding(10)
    }

    private var placeholderView: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Theme.grass.opacity(0.20), Theme.nightDeep],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            VStack(spacing: 8) {
                ProgressView()
                    .tint(Theme.lights.opacity(0.7))
                Text("Loading view from Section \(game.section)...")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
            }
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
            span: MKCoordinateSpan(latitudeDelta: mapSpan, longitudeDelta: mapSpan)
        )
        options.size = CGSize(width: 640, height: 400)
        options.mapType = .satelliteFlyover
        options.showsBuildings = true
        options.camera = MKMapCamera(
            lookingAtCenter: game.ballpark.coordinate,
            fromDistance: cameraDistance,
            pitch: cameraPitch,
            heading: cameraHeading
        )

        let snapshotter = MKMapSnapshotter(options: options)

        guard let snapshot = try? await snapshotter.start() else { return }
        SeatSnapshotCache.shared.store(snapshot.image, for: cacheKey)
        image = snapshot.image
    }
}
