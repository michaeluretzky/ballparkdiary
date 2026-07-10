import SwiftUI
import RevenueCat

/// Ballpark Diary Pro paywall. Stadium-night styling matching the rest of the
/// app, a list of Pro perks, the lifetime package from RevenueCat's current
/// offering, and a required Restore Purchases action.
/// Copy is written in a plain, fan-first voice.
struct PaywallView: View {
    var store: StoreViewModel
    @Environment(\.dismiss) private var dismiss

    private let perks: [Perk] = [
        Perk(symbol: "chart.bar.xaxis", title: "Player milestones & box scores", detail: "Career home runs, no-hitters, complete games — the moments you witnessed"),
        Perk(symbol: "car.fill", title: "Road-trip builder", detail: "Nearby parks with back-to-back home games, chained into a weekend route"),
        Perk(symbol: "ticket.fill", title: "Ticket search on upcoming games", detail: "Jump straight to tickets for any game on the map"),
        Perk(symbol: "calendar.badge.clock", title: "Anniversary throwbacks", detail: "\"One year ago today\" — your old games resurface on their anniversaries"),
        Perk(symbol: "square.and.arrow.up.fill", title: "Shareable game cards", detail: "Turn any game into a card to post or send"),
        Perk(symbol: "map.fill", title: "Quest card & Pro badges", detail: "The 30-ballpark quest plus division, rivalry, and road-warrior badges")
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

            Text("Keep a record of every game you've ever been to.")
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
        } else if let pkg = lifetimePackage {
            VStack(spacing: 12) {
                Button {
                    Task { await store.purchase(package: pkg) }
                } label: {
                    VStack(spacing: 4) {
                        Text("Unlock Pro")
                            .font(.system(size: 17, weight: .heavy))
                        Text(pkg.storeProduct.localizedPriceString)
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.9)
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
                Text("We couldn't reach the store. Give it another try in a moment.")
            }
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private var legalFooter: some View {
        VStack(spacing: 8) {
            Text("Pay once and it's yours. No subscription, no renewals. Restore it on any device signed into your Apple ID.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Link("Privacy Policy", destination: URL(string: "https://ballparkdiary.app/privacy")!)
                Text("·").foregroundStyle(Theme.textMuted)
                Link("Terms", destination: URL(string: "https://ballparkdiary.app/terms")!)
                Text("·").foregroundStyle(Theme.textMuted)
                Link("EULA", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.system(size: 10, weight: .semibold))
            .tint(Theme.lights)

            Text("Ballpark Diary is an independent fan app — not affiliated with, endorsed by, or sponsored by Major League Baseball or any MLB team.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
    }

    /// Only one-time (non-renewing) packages qualify — the paywall copy
    /// promises "pay once, no subscription", so a subscription package must
    /// never slip in via a fallback.
    private var lifetimePackage: Package? {
        guard let current = store.offerings?.current else { return nil }
        return current.lifetime
            ?? current.availablePackages.first { $0.storeProduct.productCategory == .nonSubscription }
    }
}

private struct Perk: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
}
