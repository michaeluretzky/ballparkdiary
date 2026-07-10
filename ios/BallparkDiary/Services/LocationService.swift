import Foundation
import CoreLocation
import Observation

/// Lightweight one-shot location provider for the ballpark quest.
/// Asks for when-in-use permission on demand; if the user declines
/// (or hasn't answered), callers fall back to the favorite team's
/// home ballpark as the distance anchor.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    /// Most recent coarse fix, nil until permission is granted and a fix arrives.
    private(set) var lastLocation: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus

    /// True once we have a real user fix to anchor distances on.
    var hasUserLocation: Bool { lastLocation != nil }

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        // Kilometer accuracy is plenty for ranking ballparks hundreds of miles apart.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Prompt for permission if undecided, or fetch a fresh fix if already allowed.
    func requestLocationIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            if lastLocation == nil {
                manager.requestLocation()
            }
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = fix
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silent by design — the quest falls back to the home-ballpark anchor.
    }
}
