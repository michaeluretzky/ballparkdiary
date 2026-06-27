import SwiftUI
import UIKit

/// Tab where the user manages what feeds their diary. Games come from tickets
/// shared into the app and from manual entries — combined into a single set of
/// statistics. Pull down to import newly-shared tickets and refresh scores.
struct InboxesView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(StoreViewModel.self) private var storeKit
    @State private var showManualSheet: Bool = false
    @State private var showPaywall: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        CombinedSummary()

                        ShareImportCard()

                        if !store.flaggedDuplicates.isEmpty {
                            FlaggedDuplicatesSection()
                        }

                        if !storeKit.isPremium {
                            ProUpgradeBanner { showPaywall = true }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Sources".uppercased())
                                .font(.caps(11, weight: .heavy))
                                .tracking(2.5)
                                .foregroundStyle(Theme.clay)
                                .padding(.horizontal, 4)

                            ForEach(store.connectedInboxes) { inbox in
                                InboxRow(inbox: inbox)
                            }

                            if store.connectedInboxes.isEmpty {
                                EmptyInboxesHint()
                            }
                        }

                        ManualEntryCTA(
                            manualCount: store.connectedInboxes.first(where: { $0.provider == .manual })?.ticketsFound ?? 0
                        ) {
                            showManualSheet = true
                        }

                        Text("Every game — shared or added by hand — is combined into one diary. Your games, ballparks, runs and W-L always reflect the total.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)

                        Color.clear.frame(height: 32)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .refreshable { await store.refresh(force: true) }
            .sheet(isPresented: $showManualSheet) {
                ManualGameEntryView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(store: storeKit)
            }
            .onChange(of: store.requestedManualEntry) { _, shouldOpen in
                if shouldOpen {
                    showManualSheet = true
                    store.requestedManualEntry = false
                }
            }
            .onAppear {
                // Handle the case where the flag was set before this view rendered
                // (e.g. the tab switch from a deep link hasn't completed yet).
                if store.requestedManualEntry {
                    showManualSheet = true
                    store.requestedManualEntry = false
                }
            }
        }
    }
}

// MARK: - Summary

private struct CombinedSummary: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COMBINED DIARY")
                        .font(.caps(10, weight: .heavy))
                        .tracking(2.5)
                        .foregroundStyle(Theme.clay)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(store.totalGames)")
                            .font(.scoreboard(40, weight: .black))
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: store.totalGames)
                        Text("games")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                BaseballMark(size: 50)
                    .shadow(color: Theme.clay.opacity(0.4), radius: 10)
            }

            HStack(spacing: 10) {
                MiniStat(value: "\(store.upcomingGames.count)", label: "Upcoming")
                MiniStat(value: "\(store.ballparkCount)", suffix: "/30", label: "Ballparks")
                MiniStat(value: "\(store.totalRuns)", label: "Runs")
            }
        }
        .padding(16)
        .nightCard()
    }

    private var subtitle: String {
        let upcoming = store.upcomingGames.count
        if store.totalGames == 0 && upcoming == 0 { return "Share a ticket to start your diary" }
        if upcoming > 0 { return "\(upcoming) upcoming \(upcoming == 1 ? "game" : "games") on deck" }
        return "Pull down to import new tickets"
    }
}

private struct MiniStat: View {
    let value: String
    var suffix: String = ""
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.stat(22, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.stat(12, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            Text(label.uppercased())
                .font(.caps(9, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardElevated)
        )
    }
}

// MARK: - Share import card

/// Explains the clean, on-device share-sheet import: share a ticket screenshot,
/// PDF or forwarded email into Ballpark Diary from any app and the game is added
/// automatically — no accounts, no email access.
private struct ShareImportCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(InboxProvider.shared.brandColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(InboxProvider.shared.brandColor.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share a ticket")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Add a game straight from any app")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ShareStep(number: "1", text: "Open a ticket screenshot, PDF or confirmation email.")
                ShareStep(number: "2", text: "Tap Share, then choose Ballpark Diary.")
                ShareStep(number: "3", text: "We read it on your device and confirm the box score.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.cardElevated)
            )

            Text("Nothing leaves your phone — no email login, no accounts. Pull down to refresh after sharing.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(16)
        .nightCard()
    }
}

private struct ShareStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.clay)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.clay.opacity(0.16)))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Inbox row

private struct InboxRow: View {
    @Environment(DiaryStore.self) private var store
    let inbox: ConnectedInbox

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: inbox.provider.symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(inbox.provider.brandColor)
                .frame(width: 44, height: 44)
                .background(Circle().fill(inbox.provider.brandColor.opacity(0.18)))

            VStack(alignment: .leading, spacing: 2) {
                Text(inbox.email)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(inbox.ticketsFound) \(inbox.ticketsFound == 1 ? "game" : "games") · \(inbox.provider.name)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Menu {
                Button(role: .destructive) {
                    store.disconnect(inbox)
                } label: {
                    Label("Remove source", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.textMuted)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
        }
        .padding(14)
        .nightCard()
    }
}

private struct EmptyInboxesHint: View {
    @State private var animate: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            BaseballMark(size: 48)
                .opacity(animate ? 0.55 : 0.35)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animate)
            Text("Nothing here yet")
                .font(.headline(16, weight: .heavy))
                .foregroundStyle(Theme.textSecondary)
            Text("Share a ticket or add a game by hand to get started.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card.opacity(0.5))
        )
        .onAppear { animate = true }
    }
}

// MARK: - Pro Upgrade Banner

private struct ProUpgradeBanner: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.lights)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Theme.lights.opacity(0.16)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ballpark Diary Pro")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Wrapped, share cards & more · $9.99 lifetime")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.lights)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.lights.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.lights.opacity(0.45), lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Manual Entry CTA

private struct ManualEntryCTA: View {
    let manualCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.lights)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a game manually")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(manualCount > 0
                         ? "\(manualCount) manual \(manualCount == 1 ? "game" : "games") · add another"
                         : "For games older than digital tickets or paper stubs")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        Theme.lights.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.4, dash: [6, 5])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.lights.opacity(0.05))
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flagged Duplicates Section

/// Shows potential duplicate tickets that were flagged during import.
/// Each card displays the candidate game and the existing diary entry it
/// conflicts with. The user can swipe to dismiss (keep the existing game)
/// or tap to review and optionally replace.
private struct FlaggedDuplicatesSection: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("POSSIBLE DUPLICATES".uppercased())
                    .font(.caps(10, weight: .heavy))
                    .tracking(2.5)
                    .foregroundStyle(Theme.lights)
                Spacer()
                // Auto-delete toggle
                Button {
                    store.toggleAutoDelete()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: store.autoDeleteDuplicates ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(store.autoDeleteDuplicates ? Theme.grass : Theme.textMuted)
                        Text("Auto-delete")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            ForEach(store.flaggedDuplicates) { flagged in
                FlaggedDuplicateRow(flagged: flagged)
            }
        }
    }
}

private struct FlaggedDuplicateRow: View {
    @Environment(DiaryStore.self) private var store
    let flagged: FlaggedDuplicate
    @State private var offset: CGFloat = 0

    private var existingGame: AttendedGame? {
        store.game(id: flagged.existingGameId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.lights)
                Text("Similar to an existing entry")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.lights)
                Spacer()
                Text(flagged.formattedDate)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
            }

            // Matchup
            HStack(spacing: 10) {
                TeamLogoView.compact(flagged.candidateAwayTeam, size: 30)
                Text("@")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                TeamLogoView.compact(flagged.candidateHomeTeam, size: 30)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(flagged.candidateBallpark.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    if flagged.hasSeatInfo {
                        Text("Sec \(flagged.candidateSection), Row \(flagged.candidateRow), Seat \(flagged.candidateSeat)")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                    }
                }
            }

            // Existing game reference
            if let existing = existingGame {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                    Text("Conflicts with: \(existing.awayTeam.abbreviation) @ \(existing.homeTeam.abbreviation)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    NavigationLink {
                        GameDetailView(game: existing)
                    } label: {
                        Text("View")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.clay)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.cardElevated)
                )
            }

            // Actions
            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy) {
                        store.dismissFlaggedDuplicate(flagged.id)
                    }
                } label: {
                    Label("Keep Existing", systemImage: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.grass)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.grass.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.snappy) {
                        store.acceptFlaggedDuplicate(flagged)
                    }
                } label: {
                    Label("Use New", systemImage: "arrow.triangle.swap")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.clay)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.clay.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.lights.opacity(0.35), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.lights.opacity(0.04))
                )
        )
        .offset(x: offset)
        .gesture(
            DragGesture()
                .onChanged { val in
                    if val.translation.width < -20 {
                        offset = val.translation.width
                    }
                }
                .onEnded { val in
                    if val.translation.width < -80 {
                        withAnimation(.snappy) {
                            store.dismissFlaggedDuplicate(flagged.id)
                        }
                    }
                    withAnimation(.snappy) { offset = 0 }
                }
        )
    }
}
