import Foundation
import Observation
import RevenueCat

/// Central entitlement state for Ballpark Diary Pro.
/// Owns the current offering, purchase/restore flows, and the live
/// `premium` entitlement status sourced from RevenueCat's customer-info stream.
///
/// In DEBUG builds, a debug override (UserDefaults "bp_debug_pro") lets
/// developers manually toggle Pro access. In RELEASE builds this key is
/// actively deleted on init and isPremium derives ONLY from RevenueCat's
/// server-validated entitlement.
@Observable
@MainActor
final class StoreViewModel {
    var offerings: Offerings?
    var isLoading: Bool = false
    var isPurchasing: Bool = false
    var error: String?

    #if DEBUG
    /// True when the debug pro override has been manually enabled.
    private(set) var debugProEnabled: Bool = false
    #endif

    /// Effective premium status. In release, derives ONLY from RevenueCat's
    /// server-validated entitlement. In debug, also respects the manual override.
    var isPremium: Bool {
        #if DEBUG
        if debugProEnabled { return true }
        #endif
        return revenueCatPremium
    }

    private var revenueCatPremium: Bool = false
    private let entitlementID = "pro"
    private let debugKey = "bp_debug_pro"
    private let defaults = UserDefaults.standard

    init() {
        #if DEBUG
        // Load any persisted debug override before RevenueCat starts streaming.
        debugProEnabled = defaults.bool(forKey: debugKey)
        #else
        // Release: actively delete any stale debug key so jailbroken / crafted
        // backups can't flip lifetime Pro.
        defaults.removeObject(forKey: "bp_debug_pro")
        #endif
        // Defer async work slightly so RevenueCat has time to configure.
        // Purchases.configure() in BallparkDiaryApp.init() runs after property
        // initializers, so we schedule our tasks on the next run loop.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Proactive check: fetch customer info immediately so premium status
            // is available right away instead of waiting for the stream to emit.
            Task { await self.checkStatus() }
            Task { await self.listenForUpdates() }
            Task { await self.fetchOfferings() }
        }
    }

    #if DEBUG
    /// Toggle the debug pro override. Persisted to UserDefaults so it
    /// survives app restarts. Call this from the developer section in Profile.
    func toggleDebugPro() {
        debugProEnabled.toggle()
        defaults.set(debugProEnabled, forKey: debugKey)
    }
    #endif

    private func listenForUpdates() async {
        for await info in Purchases.shared.customerInfoStream {
            revenueCatPremium = info.entitlements[entitlementID]?.isActive == true
        }
    }

    func fetchOfferings() async {
        isLoading = true
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func purchase(package: Package) async {
        isPurchasing = true
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled {
                revenueCatPremium = result.customerInfo.entitlements[entitlementID]?.isActive == true
            }
        } catch ErrorCode.purchaseCancelledError {
            // User backed out of the StoreKit sheet — not an error.
        } catch ErrorCode.paymentPendingError {
            // Awaiting parental approval or extra auth — not a failure.
        } catch {
            self.error = error.localizedDescription
        }
        isPurchasing = false
    }

    func restore() async {
        isPurchasing = true
        do {
            let info = try await Purchases.shared.restorePurchases()
            revenueCatPremium = info.entitlements[entitlementID]?.isActive == true
            if !isPremium {
                self.error = "No previous Ballpark Diary Pro purchase was found on this Apple ID."
            }
        } catch {
            self.error = error.localizedDescription
        }
        isPurchasing = false
    }

    func checkStatus() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            revenueCatPremium = info.entitlements[entitlementID]?.isActive == true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
