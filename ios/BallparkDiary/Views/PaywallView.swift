import SwiftUI
import RevenueCat

/// Ballpark Diary Pro paywall. Stadium-night styling matching the rest of the
/// app, a list of Pro perks, the yearly package from RevenueCat's current
/// offering, and a required Restore Purchases action.
struct PaywallView: View {
    var store: StoreViewModel
    @Environment(\.dismiss) private var dismiss

    private let perks: [Perk] = [
        Perk(symbol: "tray.full.fill", title: "Unlimited inboxes", detail: "Gmail, iCloud, Outlook & more — all merged"),
        Perk(symbol: "sparkles", title: "Ballpark Wrapped", detail: "Your cinematic season recap, every year"),
        Perk(symbol: "square.and.arrow.up.fill", title: "Shareable game cards", detail: "Export polished cards of any game"),
        Perk(symbol: "map.fill", title: "Ballpark quest & travel map", detail: "Track all 30 parks + miles traveled"),
        Perk(symbol: "camera.fill", title: "Camera ticket scanning", detail: "Snap paper stubs & add photo memories"),
        Perk(symbol: "chart.bar.xaxis", title: "Deep box-score data", detail: "Player milestones & notable plays")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()
                Theme.lightsGradient
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: 22) {
                        header
                        perksList
                        purchaseSection
                        legalFooter
                        Color.clear.frame(height: 12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { store.error != nil },
                set: { if !$0 { store.error = nil } }
            )) {
                Button("OK") { store.error = nil }
            } message: {
                Text(store.error ?? "")
            }
            .onChange(of: store.isPremium) { _, isPremium in
                if isPremium { dismiss() }
            }
            .task { await store.fetchOfferings() }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 14) {
            BaseballMark(size: 84)
                .shadow(color: Theme.clay.opacity(0.5), radius: 16, y: 8)
                .padding(.top, 8)

            Text("BALLPARK DIARY")
                .font(.caps(11, weight: .heavy))
                .tracking(4)
                .foregroundStyle(Theme.textSecondary)

            Text("Go Pro")
                .font(.scoreboard(40, weight: .black))
                .foregroundStyle(Theme.textPrimary)

            Text("Every game, every park, every season — captured forever.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    // MARK: Perks

    private var perksList: some View {
        VStack(spacing: 12) {
            ForEach(perks) { perk in
                HStack(spacing: 14) {
                    Image(systemName: perk.symbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.clay)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.clay.opacity(0.16)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(perk.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(perk.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .nightCard()
    }

    // MARK: Purchase

    @ViewBuilder
    private var purchaseSection: some View {
        if store.isLoading {
            ProgressView()
                .tint(Theme.clay)
                .padding(.vertical, 30)
        } else if let pkg = yearlyPackage {
            VStack(spacing: 12) {
                Button {
                    Task { await store.purchase(package: pkg) }
                } label: {
                    VStack(spacing: 4) {
                        Text("Unlock Pro")
                            .font(.system(size: 17, weight: .heavy))
                        Text("\(pkg.storeProduct.localizedPriceString) / year · cancel anytime")
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.9)
                        if let intro = pkg.storeProduct.introductoryDiscount {
                            Text("Start with \(intro.subscriptionPeriod.value)-\(unitLabel(intro.subscriptionPeriod.unit)) free trial")
                                .font(.system(size: 11, weight: .semibold))
                                .opacity(0.95)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(Theme.clayGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Theme.clay.opacity(0.4), radius: 14, y: 6)
                }
                .disabled(store.isPurchasing)
                .opacity(store.isPurchasing ? 0.6 : 1)
                .overlay {
                    if store.isPurchasing {
                        ProgressView().tint(.white)
                    }
                }

                Button {
                    Task { await store.restore() }
                } label: {
                    Text("Restore Purchases")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .disabled(store.isPurchasing)
            }
        } else {
            ContentUnavailableView {
                Label("Pricing unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Couldn't reach the store. Pull down or try again shortly.")
            }
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private var legalFooter: some View {
        Text("Payment is charged to your Apple ID. Subscription renews automatically unless canceled at least 24 hours before the period ends. Manage in Settings.")
            .font(.system(size: 10))
            .foregroundStyle(Theme.textMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }

    private var yearlyPackage: Package? {
        guard let current = store.offerings?.current else { return nil }
        return current.annual ?? current.availablePackages.first
    }

    private func unitLabel(_ unit: SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "period"
        }
    }
}

private struct Perk: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
}
