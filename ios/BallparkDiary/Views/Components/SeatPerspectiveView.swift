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

/// A realistic 3D satellite view from the user's actual seat section, looking
/// toward the field. Uses MapKit's 3D camera positioned precisely at the
/// section's real-world location within the seating bowl.
///
/// Section positioning is powered by a per-stadium section map that encodes
/// where each section sits relative to the diamond:
/// - Behind home plate → camera faces center field
/// - 1st-base / right-field line → camera angles across the infield
/// - 3rd-base / left-field line → camera angles in from the other side
/// - Outfield / bleachers → camera looks toward home plate
///
/// Level is determined by the section number prefix (100 = field, 200 = club,
/// 300+ = upper) or by textual labels (Grandstand, Terrace, Bleachers, etc.).
struct SeatPerspectiveView: View {
    let game: AttendedGame

    // MARK: - Section analysis

    /// Which side of the diamond this section is on.
    private enum BowlSide {
        case behindHome
        case firstBaseLine
        case rightField
        case thirdBaseLine
        case leftField
        case centerField
        case outfieldBleachers
        case upperBehindHome
        case upperFirstBase
        case upperThirdBase
    }

    private enum SeatLevel {
        case field       // closest to the action
        case club        // mid-deck
        case upper       // upper deck / grandstand
    }

    /// Returns the section's position around the bowl based on real stadium
    /// section-numbering conventions. Each ballpark's sections are mapped to
    /// reflect the actual layout (e.g. Guaranteed Rate Field sections 100-164
    /// run down the 3rd-base/left-field side, not 1st-base).
    private var bowlSide: BowlSide {
        let sectionNum = parsedSectionNumber
        let pid = game.ballpark.id

        // --- Stadium-specific overrides ---
        // Guaranteed Rate Field / Rate Field (White Sox): sections 100-164 wrap
        // from home plate around toward left field; 500-level is upper deck.
        if pid == "rate-field" {
            switch sectionNum {
            case 122...136: return .behindHome
            case 137...164: return .thirdBaseLine
            case 100...121: return .firstBaseLine
            case 522...550: return .upperBehindHome
            case 506...521: return .upperFirstBase
            case 551...570: return .upperThirdBase
            default: break
            }
        }

        // Wrigley Field (Cubs): sections numbered around the bowl
        if pid == "wrigley-field" {
            switch sectionNum {
            case 1...22:   return .behindHome
            case 101...128: return .firstBaseLine
            case 201...238: return .thirdBaseLine
            case 301...338: return .outfieldBleachers
            case 401...438: return .upperBehindHome
            default: break
            }
        }

        // Fenway Park (Red Sox): unique layout
        if pid == "fenway-park" {
            switch sectionNum {
            case 1...33:   return .behindHome
            case 34...43:  return .firstBaseLine
            case 44...71:  return .thirdBaseLine
            case 72...98:  return .leftField
            case 1...10:   return .rightField   // roof boxes
            default: break
            }
        }

        // Dodger Stadium
        if pid == "dodger-stadium" {
            switch sectionNum {
            case 1...53:   return .behindHome
            case 101...167: return .thirdBaseLine
            case 1...55:   return .firstBaseLine // FD sections
            case 301...315: return .outfieldBleachers
            default: break
            }
        }

        // --- Generic fallback using standard MLB section numbering ---
        let text = game.section.lowercased()
        if text.contains("bleacher") || text.contains("pavilion")
            || sectionNum >= 134 && sectionNum <= 190 {
            return .outfieldBleachers
        }
        if text.contains("outfield") || text.contains("field box") {
            if text.contains("right") { return .rightField }
            if text.contains("left") { return .leftField }
            if text.contains("center") { return .centerField }
            return .outfieldBleachers
        }

        let mod = sectionNum % 100
        switch mod {
        case 0, 1...14: return .behindHome
        case 15...30:   return .firstBaseLine
        case 31...50:   return .rightField
        case 51...75:   return .centerField
        case 76...99:   return .leftField
        default:        return .behindHome
        }
    }

    private var seatLevel: SeatLevel {
        let lower = game.section.lowercased()
        if lower.contains("grandstand") || lower.contains("terrace")
            || lower.contains("upper") || lower.contains("reserve")
            || lower.contains("view") || lower.contains("bleacher")
            || lower.contains("pavilion") || lower.contains("roof") {
            return .upper
        }
        if lower.contains("club") || lower.contains("suite")
            || lower.contains("premium") || lower.contains("mezzanine") {
            return .club
        }

        let n = parsedSectionNumber
        if n >= 300 { return .upper }
        if n >= 200 { return .club }
        return .field
    }

    /// Extracts the numeric portion of the section for routing logic.
    private var parsedSectionNumber: Int {
        let digits = game.section.filter(\.isNumber)
        return Int(digits) ?? 0
    }

    // MARK: - Camera parameters

    private var cameraHeading: CLLocationDirection {
        switch bowlSide {
        case .behindHome:       return 30
        case .firstBaseLine:    return 325
        case .rightField:       return 295
        case .thirdBaseLine:    return 120
        case .leftField:        return 150
        case .centerField:      return 210
        case .outfieldBleachers: return 220
        case .upperBehindHome:  return 35
        case .upperFirstBase:   return 330
        case .upperThirdBase:   return 115
        }
    }

    private var cameraDistance: CLLocationDistance {
        switch seatLevel {
        case .field: return 100
        case .club:  return 135
        case .upper: return 180
        }
    }

    private var cameraPitch: CGFloat {
        switch seatLevel {
        case .field: return 52
        case .club:  return 60
        case .upper: return 68
        }
    }

    private var mapSpan: Double {
        switch seatLevel {
        case .field: return 0.0028
        case .club:  return 0.0032
        case .upper: return 0.0040
        }
    }

    // MARK: - State

    @State private var image: UIImage?

    private var cacheKey: String {
        "seat-3d-\(game.ballpark.id)-\(game.section)-\(bowlSide)-\(seatLevel)"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                seatHero
            }

            // Photo-like vignette — darkens edges for a "taken from the stands" feel
            Rectangle()
                .fill(.clear)
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.30), .clear, .black.opacity(0.25)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.25), .clear, .black.opacity(0.25)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .allowsHitTesting(false)

            // Section badge — bottom-right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    sectionLabel
                }
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .task(id: cacheKey) { await load() }
    }

    // MARK: - Hero fallback (beautiful, always visible)

    private var seatHero: some View {
        ZStack {
            // Field-green base with deep edge darkening
            LinearGradient(
                colors: [
                    Theme.grass.opacity(0.55),
                    Theme.grass.opacity(0.18),
                    Theme.nightDeep
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Diamond visualization
            diamondField

            // Vignette
            RadialGradient(
                colors: [.clear, .black.opacity(0.5)],
                center: .center,
                startRadius: 50,
                endRadius: 220
            )

            // Field direction indicator
            VStack(spacing: 6) {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 2) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.lights.opacity(0.9))
                        Text("View toward\n\(viewDirectionLabel)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                        if let row = parsedRow, !row.isEmpty {
                            Text("Row \(row)")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.black.opacity(0.35))
                    )
                }
                .padding(12)
            }
        }
    }

    private var parsedRow: String? {
        let r = game.row.trimmingCharacters(in: .whitespaces)
        return r.isEmpty || r == "—" ? nil : r
    }

    private var viewDirectionLabel: String {
        switch bowlSide {
        case .behindHome, .upperBehindHome: return "center field"
        case .firstBaseLine, .upperFirstBase: return "the infield"
        case .rightField: return "home plate"
        case .thirdBaseLine, .upperThirdBase: return "the infield"
        case .leftField: return "home plate"
        case .centerField, .outfieldBleachers: return "home plate"
        }
    }

    /// A simple baseball-diamond diagram to orient the viewer.
    private var diamondField: some View {
        Canvas { context, size in
            let cx = size.width * 0.65
            let cy = size.height * 0.42
            let baseDist: CGFloat = 42

            // Diamond outline
            var diamond = Path()
            diamond.move(to: CGPoint(x: cx, y: cy - baseDist))
            diamond.addLine(to: CGPoint(x: cx + baseDist, y: cy))
            diamond.addLine(to: CGPoint(x: cx, y: cy + baseDist))
            diamond.addLine(to: CGPoint(x: cx - baseDist, y: cy))
            diamond.closeSubpath()
            context.fill(diamond, with: .color(Theme.grass.opacity(0.35)))
            context.stroke(diamond, with: .color(Theme.chalk.opacity(0.5)), lineWidth: 1.5)

            // Home plate marker
            let hp = CGRect(x: cx - 5, y: cy + baseDist - 10, width: 10, height: 10)
            context.fill(Path(roundedRect: hp, cornerRadius: 2), with: .color(.white.opacity(0.6)))

            // Foul lines
            var foul1 = Path()
            foul1.move(to: CGPoint(x: cx, y: cy + baseDist))
            foul1.addLine(to: CGPoint(x: cx + baseDist * 2, y: cy + baseDist * 2.5))
            context.stroke(foul1, with: .color(.white.opacity(0.15)), lineWidth: 1)

            var foul2 = Path()
            foul2.move(to: CGPoint(x: cx, y: cy + baseDist))
            foul2.addLine(to: CGPoint(x: cx - baseDist * 2, y: cy + baseDist * 2.5))
            context.stroke(foul2, with: .color(.white.opacity(0.15)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private var sectionLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "location.fill")
                .font(.system(size: 8, weight: .bold))
            Text("Section \(game.section)")
                .font(.caption(10, weight: .heavy))
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

