import SwiftUI

/// Tab where the user manages every inbox feeding their diary. Shows the
/// combined total at the top so it's obvious that tickets from all inboxes
/// are merged into a single set of statistics.
struct InboxesView: View {
    @Environment(DiaryStore.self) private var store
    @State private var showAddSheet: Bool = false
    @State private var showManualSheet: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        CombinedSummary()

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

                        AddInboxCTA { showAddSheet = true }

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
            .sheet(isPresented: $showAddSheet) {
                AddInboxSheet()
            }
            .sheet(isPresented: $showManualSheet) {
                ManualGameEntryView()
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
                    Text("Add Gmail, iCloud, or Outlook")
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
