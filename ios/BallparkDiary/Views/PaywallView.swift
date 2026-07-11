import SwiftUI
import RevenueCat

/// What the user was looking at when the paywall opened. Renders a teaser
/// card built from THEIR data — real numbers convert better than a generic
/// perks list.
enum PaywallContext {
    case milestones(count: Int, sample: String)
    case throwback(yearsAgo: Int, summary: String)
    case fanRecord(wins: Int, losses: Int)
    case wrapped(year: Int, games: Int)
    case famousGame
    case backup
}

/// Ballpark Diary Pro paywall. Stadium-night styling matching the rest of the
/// app, an optional context teaser built from the user's own data, a list of
/// Pro perks, the monthly subscription package from RevenueCat's current
/// offering, and a required Restore Purchases action.
/// Copy is written in a plain, fan-first voice.
struct PaywallView: View {
    var store: StoreViewModel
    var context: PaywallContext? = nil
    @Environment(\.dismiss) private var dismiss

    private let perks: [Perk] = [
        Perk(symbol: "chart.bar.xaxis", title: "Player milestones & box scores", detail: "Career home runs, no-hitters, complete games — the moments you witnessed"),
        Perk(symbol: "trophy.fill", title: "Fan record deep stats", detail: "Your record by team, day vs. night, home vs. road — stats no one else has"),
        Perk(symbol: "sparkles", title: "Famous game flags", detail: "Find out when a game in your diary was historic — no-hitters, milestones, marathons"),
        Perk(symbol: "car.fill", title: "Road-trip builder", detail: "Nearby parks with back-to-back home games, chained into a weekend route"),
        Perk(symbol: "calendar.badge.clock", title: "Anniversary throwbacks", detail: "\"One year ago today\" — your old games resurface on their anniversaries"),
        Perk(symbol: "square.and.arrow.up.fill", title: "Shareable game & recap cards", detail: "Turn any game or season recap into a card to post or send"),
        Perk(symbol: "icloud.fill", title: "Automatic iCloud backup", detail: "Your lifetime diary, protected — plus a home-screen widget"),
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
                        if let context {
                            ContextTeaserCard(context: context)
                        }
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
        } else if let pkg = monthlyPackage {
            VStack(spacing: 12) {
                Button {
                    Task { await store.purchase(package: pkg) }
                } label: {
                    VStack(spacing: 4) {
                        Text(hasFreeTrial(pkg) ? "Try Pro Free" : "Unlock Pro")
                            .font(.system(size: 17, weight: .heavy))
                        Text(hasFreeTrial(pkg)
                             ? "\(trialLabel(pkg)) free, then \(pkg.storeProduct.localizedPriceString)/month"
                             : "\(pkg.storeProduct.localizedPriceString)/month")
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

    /// Whether the package carries an introductory free trial the current
    /// user is eligible for (StoreKit only exposes the discount when eligible).
    private func hasFreeTrial(_ pkg: Package) -> Bool {
        pkg.storeProduct.introductoryDiscount?.paymentMode == .freeTrial
    }

    /// Localized trial length, e.g. "7 days".
    private func trialLabel(_ pkg: Package) -> String {
        guard let discount = pkg.storeProduct.introductoryDiscount else { return "" }
        let period = discount.subscriptionPeriod
        let unitName: String
        switch period.unit {
        case .day: unitName = period.value == 1 ? "day" : "days"
        case .week: return period.value == 1 ? "7 days" : "\(period.value) weeks"
        case .month: unitName = period.value == 1 ? "month" : "months"
        case .year: unitName = period.value == 1 ? "year" : "years"
        }
        return "\(period.value) \(unitName)"
    }

    private var legalFooter: some View {
        VStack(spacing: 8) {
            Text("Payment is charged to your Apple ID. A free trial, when offered, converts to a paid subscription unless canceled before it ends. The subscription renews monthly at the shown price until canceled — cancel anytime in Settings › Apple ID › Subscriptions, at least 24 hours before the period ends.")
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

    /// The monthly auto-renewable package — the paywall copy discloses a
    /// monthly renewal, so only subscription packages qualify as a fallback.
    private var monthlyPackage: Package? {
        guard let current = store.offerings?.current else { return nil }
        return current.monthly
            ?? current.availablePackages.first { $0.storeProduct.productCategory == .subscription }
    }
}

private struct Perk: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
}

// MARK: - Context teaser (the user's own data behind the lock)

private struct ContextTeaserCard: View {
    let context: PaywallContext

    private var symbol: String {
        switch context {
        case .milestones: return "trophy.fill"
        case .throwback: return "calendar.badge.clock"
        case .fanRecord: return "chart.bar.xaxis"
        case .wrapped: return "sparkles"
        case .famousGame: return "star.circle.fill"
        case .backup: return "icloud.fill"
        }
    }

    private var headline: String {
        switch context {
        case .milestones(let count, _):
            return count == 1
                ? "You've witnessed a career milestone"
                : "You've witnessed \(count) career milestones"
        case .throwback(let yearsAgo, _):
            return yearsAgo == 1 ? "One year ago today…" : "\(yearsAgo) years ago today…"
        case .fanRecord(let wins, let losses):
            return "Your lifetime record is \(wins)–\(losses)"
        case .wrapped(let year, let games):
            return "Your \(String(year)) season: \(games) game\(games == 1 ? "" : "s")"
        case .famousGame:
            return "You were at a famous game"
        case .backup:
            return "Protect your lifetime diary"
        }
    }

    private var blurredDetail: String? {
        switch context {
        case .milestones(_, let sample): return sample
        case .throwback(_, let summary): return summary
        case .fanRecord: return "Your record by team, day vs. night, home vs. road"
        case .wrapped: return "Share your season recap card with friends"
        case .famousGame: return "See exactly why this night was historic"
        case .backup: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.lights)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.lights.opacity(0.16)))
                Text(headline)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if let blurredDetail {
                HStack(spacing: 8) {
                    Text(blurredDetail)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .blur(radius: 4)
                        .accessibilityHidden(true)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.lights)
                }
                .padding(.leading, 46)
            }

            Text("Unlock Pro to see it all.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.lights)
                .padding(.leading, 46)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.lights.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.lights.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). Unlock Pro to see it all.")
    }
}
