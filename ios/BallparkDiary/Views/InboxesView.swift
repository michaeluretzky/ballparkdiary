import SwiftUI
import UIKit

/// Tab where the user manages every inbox feeding their diary. Shows the
/// combined total at the top so it's obvious that tickets from all inboxes
/// are merged into a single set of statistics.
struct InboxesView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(StoreViewModel.self) private var storeKit
    @State private var showAddSheet: Bool = false
    @State private var showManualSheet: Bool = false
    @State private var showPaywall: Bool = false

    /// Inboxes that count toward the free 1-inbox limit (manual entries are free & unlimited).
    private var connectedRealInboxes: Int {
        store.connectedInboxes.filter { $0.provider != .manual }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        CombinedSummary()

                        ForwardingCard()

                        ShareImportCard()

                        if !storeKit.isPremium {
                            ProUpgradeBanner { showPaywall = true }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Connected".uppercased())
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

                        AddInboxCTA {
                            if storeKit.isPremium || connectedRealInboxes < 1 {
                                showAddSheet = true
                            } else {
                                showPaywall = true
                            }
                        }

                        ManualEntryCTA(
                            manualCount: store.connectedInboxes.first(where: { $0.provider == .manual })?.ticketsFound ?? 0
                        ) {
                            showManualSheet = true
                        }

                        Text("All tickets from every inbox are combined into one diary. Your games, ballparks, runs and W-L always reflect the total.")
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
            .navigationTitle("Inboxes")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { await store.refreshForwarding() }
            .refreshable { await store.refreshForwarding() }
            .sheet(isPresented: $showAddSheet) {
                AddInboxSheet()
            }
            .sheet(isPresented: $showManualSheet) {
                ManualGameEntryView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(store: storeKit)
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
                MiniStat(value: "\(store.connectedInboxes.count)", label: "Inboxes")
                MiniStat(value: "\(store.ballparkCount)", suffix: "/30", label: "Ballparks")
                MiniStat(value: "\(store.totalRuns)", label: "Runs")
            }
        }
        .padding(16)
        .nightCard()
    }

    private var subtitle: String {
        let n = store.connectedInboxes.count
        if n == 0 { return "No inboxes connected yet" }
        if n == 1 { return "From 1 inbox · merged" }
        return "From \(n) inboxes · merged"
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

// MARK: - Forwarding card

/// Primary auto-import path: the user forwards ticket receipts to a personal
/// address and we parse + confirm the game server-side. No mailbox access.
private struct ForwardingCard: View {
    @Environment(DiaryStore.self) private var store
    @State private var didCopy: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(InboxProvider.forwarding.brandColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(InboxProvider.forwarding.brandColor.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-import by email")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Forward any ticket receipt — we add the game")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if store.forwardingConfigured, let address = store.forwardingAddress {
                Button {
                    UIPasteboard.general.string = address
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    withAnimation(.snappy) { didCopy = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.snappy) { didCopy = false }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(address)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(didCopy ? InboxProvider.forwarding.brandColor : Theme.clay)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.cardElevated)
                    )
                }
                .buttonStyle(.plain)

                Text(didCopy ? "Copied! Paste it as a forwarding address in your mail app."
                     : "Tip: set this as an auto-forward filter for Ticketmaster, SeatGeek, StubHub & MLB emails.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.lights)
                    Text("Your forwarding address is being set up — check back soon.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.cardElevated)
                )
            }
        }
        .padding(16)
        .nightCard()
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

            Text("Nothing leaves your phone — no email login, no accounts.")
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
                .font(.system(size: 12, weight: .heavy, design: .rounded))
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
                Text("\(inbox.ticketsFound) tickets · \(inbox.provider.name)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Menu {
                Button(role: .destructive) {
                    store.disconnect(inbox)
                } label: {
                    Label("Disconnect inbox", systemImage: "trash")
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
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.textMuted)
            Text("No inboxes connected")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("Connect one below to start your diary.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card.opacity(0.6))
        )
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
                    Text("Unlimited inboxes, Wrapped, share cards & more · $9.99/yr")
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

// MARK: - Add CTA

private struct AddInboxCTA: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.clay)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect another inbox")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Add iCloud, Outlook, or another email")
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
                        Theme.clay.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.4, dash: [6, 5])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.clay.opacity(0.05))
                    )
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

// MARK: - Add Inbox Sheet

/// Modal flow for connecting an additional inbox after onboarding.
/// Reuses the same ScanPanel so the experience is consistent end-to-end.
struct AddInboxSheet: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.nightGradient.ignoresSafeArea()
            FieldLinesBackground()
                .opacity(0.08)
                .allowsHitTesting(false)

            Group {
                switch store.scanPhase {
                case .idle:
                    ChooseProviderPanel(onCancel: { dismiss() })
                        .transition(.opacity)
                case .connecting, .scanning, .finishing, .finished:
                    ScanPanel()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.45), value: store.scanPhase)
        }
        .task(id: store.scanPhase) {
            if store.scanPhase == .finished {
                try? await Task.sleep(for: .milliseconds(1500))
                dismiss()
            }
        }
        .presentationDragIndicator(.visible)
    }
}

private struct ChooseProviderPanel: View {
    @Environment(DiaryStore.self) private var store
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)

            BaseballMark(size: 110)
                .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
                .padding(.bottom, 18)

            Text("ADD INBOX")
                .font(.caps(12, weight: .heavy))
                .tracking(5)
                .foregroundStyle(Theme.clay)

            Text("More inboxes,\nmore tickets found.")
                .font(.scoreboard(28))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 6)

            Text("Tickets from each inbox combine into your single diary. Your totals always show every game across every email.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 10)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                ForEach(InboxProvider.connectable) { provider in
                    ConnectButton(
                        provider: provider,
                        isConnected: store.isProviderConnected(provider)
                    ) {
                        store.connect(provider: provider)
                    }
                }

                Button(action: onCancel) {
                    Text("Not now")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
    }
}
