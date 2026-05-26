import SwiftUI

/// Three-step onboarding:
/// 1. Pick a favorite/home team (used to tint stats & rotate the map).
/// 2. Connect any number of inbox providers — receipt-scanning hero/CTA.
/// 3. Animated mock scan that reveals detected tickets and ends in the app.
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
                    switch store.scanPhase {
                    case .idle:
                        HeroPanel()
                            .transition(.opacity)
                    case .connecting, .scanning, .finishing, .finished:
                        ScanPanel()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .animation(.smooth(duration: 0.5), value: store.scanPhase)
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

// MARK: - Hero

private struct HeroPanel: View {
    @Environment(DiaryStore.self) private var store
    @State private var ballSpin: Double = 0
    @State private var showOtherSheet: Bool = false
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
                    Text("BALLPARK DIARY".uppercased())
                        .font(.caps(13, weight: .heavy))
                        .tracking(6)
                        .foregroundStyle(Theme.clay)

                    Text("welcome to your\nvirtual baseball journal.")
                        .font(.scoreboard(30))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(2)

                    Text("connect every inbox you've ever bought tickets from and build your interactive baseball journal.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 2)
                }
                .padding(.bottom, 18)

                VStack(spacing: 10) {
                    ForEach(InboxProvider.connectable) { provider in
                        ConnectButton(provider: provider, isConnected: false) {
                            if provider == .other {
                                showOtherSheet = true
                            } else {
                                store.connect(provider: provider)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                        Text("OR")
                            .font(.caps(10, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(Theme.textMuted)
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    }
                    .padding(.top, 6)

                    Button { showManualSheet = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.lights)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Theme.lights.opacity(0.18)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Add games manually")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("For games older than digital tickets")
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

                    Text("Works with any ticketing platform — StubHub, SeatGeek, Ticketmaster, Vivid Seats, Gametime, AXS, MLB Ballpark, and team mobile apps.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                        .padding(.horizontal, 24)

                    LegalDisclaimer()
                        .padding(.top, 8)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showOtherSheet) {
            OtherInboxSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showManualSheet) {
            ManualGameEntryView()
        }
    }
}

/// Legal disclaimer with links to Terms and Privacy Policy. Required for any
/// app that accesses mailbox content to satisfy App Store review.
struct LegalDisclaimer: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("We only scan for ticket-related receipts. Email content is processed on-device and never stored or shared.")
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

/// Lightweight "Other email" sheet — accepts any email address and kicks off
/// the same scan animation as the named providers.
struct OtherInboxSheet: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var email: String = ""
    @FocusState private var focused: Bool

    private var isValid: Bool {
        let parts = email.split(separator: "@")
        return parts.count == 2 && parts.last?.contains(".") == true
    }

    var body: some View {
        ZStack {
            Theme.nightGradient.ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(systemName: "at")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.clay)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Theme.clay.opacity(0.18)))

                    Text("Connect any inbox")
                        .font(.scoreboard(22))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Works with Fastmail, ProtonMail, work email, and any other IMAP provider.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 20)

                TextField("you@example.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.emailAddress)
                    .focused($focused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.cardElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06))
                    )
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 22)

                Button {
                    store.connect(provider: .other, email: email)
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isValid ? AnyShapeStyle(Theme.clayGradient) : AnyShapeStyle(Theme.cardElevated))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
                .padding(.horizontal, 22)

                Spacer()
            }
        }
        .onAppear { focused = true }
    }
}

/// Provider connect row. Reused by the onboarding hero and the in-app
/// "add another inbox" sheet.
struct ConnectButton: View {
    let provider: InboxProvider
    let isConnected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: provider.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(provider.brandColor)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(provider.brandColor.opacity(0.18)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(isConnected ? provider.name : "Continue with \(provider.name)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if isConnected {
                        Text("Already connected")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.grass)
                    } else if provider == .other {
                        Text(provider.blurb)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.grass)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.cardElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isConnected)
    }
}

// MARK: - Scanning (reused inside onboarding and the in-app add-inbox sheet)

struct ScanPanel: View {
    @Environment(DiaryStore.self) private var store

    private var progress: Double {
        if case let .scanning(p, _) = store.scanPhase { return p }
        if store.scanPhase == .finishing || store.scanPhase == .finished { return 1.0 }
        return 0.02
    }

    private var statusTitle: String {
        switch store.scanPhase {
        case .connecting: return "Connecting to \(store.connectedInbox ?? "inbox")…"
        case .scanning: return "Reading your receipts"
        case .finishing: return "Plotting your ballparks"
        case .finished: return store.connectedInboxes.count > 1 ? "Combined with your diary" : "Welcome to your diary"
        case .idle: return ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ScanEmblem(progress: progress, finished: store.scanPhase == .finished)
                .frame(width: 200, height: 200)
                .padding(.bottom, 18)

            Text(statusTitle.uppercased())
                .font(.caps(12, weight: .heavy))
                .tracking(4)
                .foregroundStyle(Theme.clay)
                .multilineTextAlignment(.center)

            HStack(spacing: 14) {
                Text("\(store.foundEmails.count)")
                    .font(.stat(64, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: store.foundEmails.count)
                VStack(alignment: .leading, spacing: 2) {
                    Text("tickets found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(Int(progress * 100))% complete")
                        .font(.stat(13, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.top, 4)

            ScanProgressBar(progress: progress)
                .frame(height: 6)
                .padding(.horizontal, 36)
                .padding(.top, 16)

            EmailStream(subjects: store.foundEmails)
                .padding(.top, 22)
                .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
    }
}

private struct ScanEmblem: View {
    let progress: Double
    let finished: Bool
    @State private var sweep: Double = 0

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(Theme.clay.opacity(0.10 + Double(i) * 0.06), lineWidth: 1)
                    .scaleEffect(1.0 - CGFloat(i) * 0.18)
            }

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [Theme.clay, Theme.lights, Theme.clay],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: progress)

            if !finished {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.lights.opacity(0.35), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: 86, height: 2)
                    .offset(x: 43)
                    .rotationEffect(.degrees(sweep))
                    .blur(radius: 1)
                    .mask(Circle().padding(8))
            }

            BaseballMark(size: 86)
                .shadow(color: Theme.clay.opacity(0.5), radius: 18)
                .scaleEffect(finished ? 1.05 : 1.0)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: finished)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                sweep = 360
            }
        }
    }
}

private struct ScanProgressBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.clay, Theme.lights], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * progress)
                    .animation(.smooth, value: progress)
            }
        }
    }
}

private struct EmailStream: View {
    let subjects: [String]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(subjects.suffix(4).enumerated()), id: \.offset) { idx, subject in
                EmailRow(subject: subject)
                    .opacity(opacity(for: idx, total: min(subjects.count, 4)))
                    .scaleEffect(1.0 - 0.02 * Double(min(subjects.count, 4) - 1 - idx), anchor: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: subjects.count)
    }

    private func opacity(for index: Int, total: Int) -> Double {
        let position = total - 1 - index
        return 1.0 - Double(position) * 0.22
    }
}

private struct EmailRow: View {
    let subject: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.clay)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.clay.opacity(0.18)))

            Text(subject)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.grass)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.card.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05))
        )
    }
}
