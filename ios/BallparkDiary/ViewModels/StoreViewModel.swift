import Foundation
import Observation
import RevenueCat

/// Central entitlement state for Ballpark Diary Pro ($9.99 lifetime).
/// Owns the current offering, purchase/restore flows, and the live
/// `premium` entitlement status sourced from RevenueCat's customer-info stream.
///
/// To grant Pro access to specific users without purchase, create a Customer
/// in the RevenueCat dashboard (RevenueCat → Customers → + New) and grant the
/// "pro" entitlement. The user's App User ID can be found in Xcode logs
/// (search for "Purchases" — the ID is logged on configure). You can also
/// create Offering Overrides to give specific customers a free or discounted
/// price for the lifetime package.
@Observable
@MainActor
final class StoreViewModel {
    var offerings: Offerings?
    var isPremium: Bool = false
    var isLoading: Bool = false
    var isPurchasing: Bool = false
    var error: String?

    private let entitlementID = "pro"

    init() {
        Task { await listenForUpdates() }
        Task { await fetchOfferings() }
    }

    private func listenForUpdates() async {
        for await info in Purchases.shared.customerInfoStream {
            isPremium = info.entitlements[entitlementID]?.isActive == true
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
                isPremium = result.customerInfo.entitlements[entitlementID]?.isActive == true
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
            isPremium = info.entitlements[entitlementID]?.isActive == true
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
            isPremium = info.entitlements[entitlementID]?.isActive == true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
