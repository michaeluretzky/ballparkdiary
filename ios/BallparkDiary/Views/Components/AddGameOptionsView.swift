import SwiftUI

/// Sheet presented from the Diary "+" button. Gives the user two clear paths
/// to add a game: manually fill out a form, or share a ticket screenshot.
struct AddGameOptionsView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showManualEntry = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(store.favoriteTeam.primary)
                            .padding(.top, 24)

                        Text("Add a Game")
                            .font(.scoreboard(22, weight: .black))
                            .foregroundStyle(.white)

                        Text("Every ticket, stub, and memory — all in one place.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.bottom, 28)

                    // Options
                    VStack(spacing: 12) {
                        OptionCard(
                            icon: "square.and.pencil",
                            title: "Enter Manually",
                            subtitle: "Fill in the details yourself for any game you've attended.",
                            accent: store.favoriteTeam.primary,
                            action: { showManualEntry = true }
                        )

                        OptionCard(
                            icon: "square.and.arrow.down.fill",
                            title: "Share a Ticket",
                            subtitle: "Tap Share on a ticket email or screenshot, then pick Ballpark Diary.",
                            accent: Theme.lights,
                            action: {
                                dismiss()
                                // Navigate to inboxes tab to guide the user
                                store.requestedTab = "inboxes"
                            }
                        )
                    }
                    .padding(.horizontal, 16)

                    Spacer()

                    // Tip
                    VStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.lights.opacity(0.6))
                        Text("Tip: We verify every game against the official MLB box score, so your stats are always accurate.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .sheet(isPresented: $showManualEntry) {
                ManualGameEntryView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Option card

private struct OptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(accent.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
