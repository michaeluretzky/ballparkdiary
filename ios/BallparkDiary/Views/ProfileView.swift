import SwiftUI

/// Profile / Settings tab where the user manages their favorite team, home
/// ballpark preference, and subscription status. Persisted choices feed into
/// map centering, stat tinting, and diary personalization.
struct ProfileView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(StoreViewModel.self) private var storeKit
    @State private var showTeamPicker: Bool = false
    @State private var showPaywall: Bool = false
    @State private var showResetConfirm: Bool = false
    #if DEBUG
    @State private var showDebugProToggle: Bool = false
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()
                Theme.nightVignette.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        // Favorite team card
                        favoriteTeamCard
                            .padding(.horizontal, 16)

                        // Home ballpark
                        homeBallparkCard
                            .padding(.horizontal, 16)

                        // Pro status
                        proStatusCard
                            .padding(.horizontal, 16)

                        // Developer debug section (hidden — long-press pro card to reveal).
                        // DEBUG builds only; the override does not exist in release.
                        #if DEBUG
                        if showDebugProToggle {
                            debugProSection
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }
                        #endif

                        // Danger zone
                        dangerZone
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        // Legal disclaimer
                        legalDisclaimer
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        Color.clear.frame(height: 30)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showTeamPicker) {
                TeamPickerSheet { team in
                    store.pickFavorite(team)
                    showTeamPicker = false
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(store: storeKit)
            }
            .alert("Reset Diary?", isPresented: $showResetConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset Everything", role: .destructive) {
                    withAnimation { store.resetAll() }
                }
            } message: {
                Text("This will erase your diary, stats, ballpark visits, and inboxes. Your Pro purchase (if any) is not affected.")
            }
        }
    }

    // MARK: - Favorite team

    private var favoriteTeamCard: some View {
        let team = store.favoriteTeam
        return Button { showTeamPicker = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(team.primary)
                    Circle().strokeBorder(team.secondary, lineWidth: 2)
                    TeamLogoView(team: team, size: 56)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Favorite Team")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                    Text(team.fullName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Tap to change")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(16)
            .nightCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Home ballpark

    private var homeBallparkCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "house.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.lights)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.lights.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Home Ballpark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                    if let home = store.homeBallpark {
                        Text(home.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                    } else {
                        Text("Set by visiting a park most often")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 16)

            // Show ballpark visit distribution
            if !store.completedGames.isEmpty {
                VStack(spacing: 8) {
                    ForEach(ballparkDistribution.prefix(5), id: \.park.id) { item in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(item.park.team.primary)
                                .frame(width: 10, height: 10)
                            Text(item.park.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.count)")
                                .font(.stat(13, weight: .heavy))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            } else {
                Text("Visit a ballpark to see your distribution.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .nightCard()
    }

    private var ballparkDistribution: [(park: Ballpark, count: Int)] {
        let counts = Dictionary(grouping: store.completedGames, by: \.ballparkId)
            .mapValues(\.count)
        return counts.compactMap { id, count in
            Ballpark.by(id: id).map { ($0, count) }
        }.sorted { $0.count > $1.count }
    }

    // MARK: - Pro status

    private var proStatusCard: some View {
        Button {
            if !storeKit.isPremium { showPaywall = true }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Image(systemName: storeKit.isPremium ? "crown.fill" : "crown")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(storeKit.isPremium ? Theme.lights : Theme.textMuted)
                }
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(
                        storeKit.isPremium ? Theme.lights.opacity(0.18) : Theme.cardElevated
                    )
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(storeKit.isPremium ? "Ballpark Diary Pro" : "Ballpark Diary Free")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(storeKit.isPremium
                         ? "Lifetime access — all features unlocked"
                         : "Unlock Pro features — one-time purchase")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if !storeKit.isPremium {
                    if let price = storeKit.lifetimePriceString {
                        Text(price)
                            .font(.stat(15, weight: .heavy))
                            .foregroundStyle(Theme.lights)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Theme.lights.opacity(0.16))
                            )
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.lights)
                    }
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.grass)
                }
            }
            .padding(16)
            .nightCard()
            .overlay(alignment: .topTrailing) {
                if storeKit.isPremium {
                    Text("PRO")
                        .font(.caps(9, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(Theme.lights)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Theme.lights.opacity(0.16))
                        )
                        .padding(12)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(storeKit.isPremium)
        #if DEBUG
        .onLongPressGesture(minimumDuration: 1.5) {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showDebugProToggle.toggle()
            }
        }
        #endif
    }

    // MARK: - Debug Pro section

    #if DEBUG
    private var debugProSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.lights)
                Text("Developer Pro Override")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.lights)
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manual Pro access")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(storeKit.debugProEnabled
                         ? "Pro features are force-enabled regardless of purchase."
                         : "Toggle to enable Pro features without purchasing.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { storeKit.debugProEnabled },
                    set: { _ in withAnimation { storeKit.toggleDebugPro() } }
                ))
                .tint(Theme.lights)
                .labelsHidden()
            }

            Text("This bypasses RevenueCat. Disable to restore normal purchase flow.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted.opacity(0.6))
        }
        .padding(16)
        .nightCard()
        .overlay(alignment: .topTrailing) {
            Text("DEBUG")
                .font(.caps(9, weight: .heavy))
                .tracking(2)
                .foregroundStyle(Theme.lights)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Theme.lights.opacity(0.16))
                )
                .padding(12)
        }
    }
    #endif

    // MARK: - Danger zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Danger Zone")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.foul)

            Button(role: .destructive) { showResetConfirm = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.foul)
                    Text("Reset entire diary")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.foul)
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.foul.opacity(0.5), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.foul.opacity(0.06))
                        )
                )
            }
            .buttonStyle(.plain)

            Text("This cannot be undone. Your shared tickets and manual entries will be removed from the app.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Legal

    private var legalDisclaimer: some View {
        VStack(spacing: 10) {
            Divider().background(Color.white.opacity(0.08))
            VStack(alignment: .leading, spacing: 6) {
                Text("About Ballpark Diary")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                Text("Ballpark Diary is an independent personal journal app. It is not affiliated with, endorsed by, sponsored by, or associated with Major League Baseball, any MLB team, any MLB player, or any other sports organization. All team names, logos, and trademarks are the property of their respective owners and are used for informational and identification purposes only. This app does not imply any partnership or endorsement by any professional sports league or team.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Team picker sheet

private struct TeamPickerSheet: View {
    let onSelect: (Team) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(DiaryStore.self) private var store

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 10)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    Text("Pick your home team.")
                        .font(.scoreboard(24))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 16)
                    Text("We'll center your map here and tint your stats in their colors.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 4)

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(Team.all) { team in
                                Button {
                                    onSelect(team)
                                } label: {
                                    VStack(spacing: 6) {
                                        ZStack {
                                            Circle().fill(team.primary)
                                            Circle().strokeBorder(team.secondary, lineWidth: 2)
                                            TeamLogoView(team: team, size: 52)
                                        }
                                        .frame(width: 52, height: 52)
                                        .overlay(alignment: .topTrailing) {
                                            if team.id == store.favoriteTeam.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundStyle(Theme.lights)
                                                    .background(Circle().fill(Theme.nightDeep))
                                                    .offset(x: 4, y: -4)
                                            }
                                        }
                                        Text(team.name)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Theme.textSecondary)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(team.id == store.favoriteTeam.id ? Theme.clay.opacity(0.18) : Theme.card.opacity(0.55))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(team.id == store.favoriteTeam.id ? Theme.clay : Color.white.opacity(0.06), lineWidth: team.id == store.favoriteTeam.id ? 1.5 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}
