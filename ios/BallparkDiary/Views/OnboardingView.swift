import SwiftUI

/// Two-step onboarding:
/// 1. Pick a favorite/home team (used to tint stats & rotate the map).
/// 2. Learn how to fill the diary — share tickets in, or add games by hand —
///    then jump into the app.
struct OnboardingView: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        ZStack {
            Theme.lightsGradient
                .offset(y: -120)
                .ignoresSafeArea()
            FieldLinesBackground()
                .opacity(0.10)
                .allowsHitTesting(false)

            Group {
                if !store.hasPickedFavorite {
                    FavoriteTeamPanel()
                        .transition(.opacity)
                } else {
                    HeroPanel()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.5), value: store.hasPickedFavorite)
        }
    }
}

// MARK: - Favorite team picker

private struct FavoriteTeamPanel: View {
    @Environment(DiaryStore.self) private var store
    @State private var selectedId: String? = nil

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("STEP 1 OF 2")
                    .font(.caps(11, weight: .heavy))
                    .tracking(4)
                    .foregroundStyle(Theme.clay)

                Text("Pick your home team.")
                    .font(.scoreboard(30))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)

                Text("We'll center your map here and tint your stats in their colors.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.top, 24)
            .padding(.bottom, 14)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Team.all) { team in
                        TeamPickerTile(team: team, isSelected: selectedId == team.id) {
                            selectedId = team.id
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            VStack(spacing: 10) {
                Button(action: confirm) {
                    HStack(spacing: 8) {
                        Text(selectedId == nil ? "Pick a team to continue" : "Continue")
                            .font(.system(size: 16, weight: .heavy))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selectedId == nil ? AnyShapeStyle(Theme.cardElevated) : AnyShapeStyle(Theme.clayGradient))
                    )
                }
                .buttonStyle(.plain)
                .disabled(selectedId == nil)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
    }

    private func confirm() {
        guard let id = selectedId, let team = Team.by(id: id) else { return }
        store.pickFavorite(team)
    }
}

private struct TeamPickerTile: View {
    let team: Team
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(team.primary)
                    Circle().strokeBorder(team.secondary, lineWidth: 2)
                    Text(team.abbreviation)
                        .font(.stat(15, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.lights)
                            .background(Circle().fill(Theme.nightDeep))
                            .offset(x: 4, y: -4)
                    }
                }

                Text(team.name.isEmpty ? team.city : team.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.clay.opacity(0.18) : Theme.card.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Theme.clay : Color.white.opacity(0.06), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hero (share + manual)

private struct HeroPanel: View {
    @Environment(DiaryStore.self) private var store
    @State private var ballSpin: Double = 0
    @State private var showManualSheet: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Theme.lights.opacity(0.18))
                        .frame(width: 280, height: 280)
                        .blur(radius: 40)

                    BaseballMark(size: 140)
                        .rotationEffect(.degrees(ballSpin))
                        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 12)
                }
                .frame(height: 200)
                .padding(.top, 12)
                .onAppear {
                    withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                        ballSpin = 360
                    }
                }

                VStack(spacing: 12) {
                    Text("STEP 2 OF 2")
                        .font(.caps(11, weight: .heavy))
                        .tracking(4)
                        .foregroundStyle(Theme.clay)

                    Text("build your\nbaseball journal.")
                        .font(.scoreboard(30))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(2)

                    Text("Every game you add is confirmed against the real box score, plotted on your ballpark map, and folded into your stats.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 2)
                }
                .padding(.bottom, 20)

                // Share-in steps
                VStack(alignment: .leading, spacing: 12) {
                    Text("SHARE A TICKET IN")
                        .font(.caps(10, weight: .heavy))
                        .tracking(2.5)
                        .foregroundStyle(Theme.clay)

                    OnboardStep(number: "1", icon: "ticket.fill",
                                text: "Open a ticket screenshot, PDF, or confirmation in any app.")
                    OnboardStep(number: "2", icon: "square.and.arrow.up",
                                text: "Tap Share, then pick Ballpark Diary from the share sheet.")
                    OnboardStep(number: "3", icon: "checkmark.seal.fill",
                                text: "We read it on-device and confirm the matchup automatically.")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nightCard()
                .padding(.horizontal, 22)

                Button { showManualSheet = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.lights)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Theme.lights.opacity(0.18)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Add a game by hand")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("For older games or paper stubs")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textMuted)
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textMuted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.lights.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.lights.opacity(0.05))
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.top, 12)

                Button(action: { store.completeOnboarding() }) {
                    HStack(spacing: 8) {
                        Text("Enter my diary")
                            .font(.system(size: 16, weight: .heavy))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.clayGradient)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.top, 12)

                Text("Works with any ticketing platform — StubHub, SeatGeek, Ticketmaster, Vivid Seats, Gametime, AXS, MLB Ballpark, and team apps.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .padding(.horizontal, 24)

                LegalDisclaimer()
                    .padding(.top, 8)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showManualSheet) {
            ManualGameEntryView()
        }
    }
}

private struct OnboardStep: View {
    let number: String
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.clay)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.clay.opacity(0.16)))
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.lights)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Legal disclaimer with links to Terms and Privacy Policy.
struct LegalDisclaimer: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Tickets you share are read entirely on your device — never uploaded, stored on our servers, or shared. No email or account access is ever requested.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)

            HStack(spacing: 14) {
                Link("Privacy Policy", destination: URL(string: "https://ballparkdiary.app/privacy")!)
                Text("·").foregroundStyle(Theme.textMuted)
                Link("Terms of Service", destination: URL(string: "https://ballparkdiary.app/terms")!)
                Text("·").foregroundStyle(Theme.textMuted)
                Link("EULA", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .tint(Theme.lights)

            Text("By continuing you agree to the Terms. Ballpark Diary is an independent fan app and is not affiliated with MLB or any team.")
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
    }
}
