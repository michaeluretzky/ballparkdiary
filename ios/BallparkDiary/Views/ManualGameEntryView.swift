import SwiftUI

/// Manual game entry form for ballparks visited before digital ticketing,
/// stub-and-paper ticket games, or anything not surfaced by an inbox scan.
/// Now verifies against the real MLB box score — the user picks a matchup
/// and date, and we confirm it against the live schedule before saving.
struct ManualGameEntryView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date = Calendar.current.date(byAdding: .year, value: -10, to: .now) ?? .now
    @State private var ballparkId: String = Ballpark.all[0].id
    @State private var homeTeamId: String = ""
    @State private var awayTeamId: String = Team.redSox.id
    @State private var homeScore: Int = 0
    @State private var awayScore: Int = 0
    @State private var userRootedForHome: Bool = true
    @State private var section: String = ""
    @State private var row: String = ""
    @State private var seat: String = ""
    @State private var weather: AttendedGame.Weather = .clear
    @State private var notes: String = ""
    @FocusState private var focusedField: Field?

    // Verification state
    @State private var verifyState: VerifyState = .idle
    @State private var verifyMessage: String = ""

    enum Field: Hashable { case section, row, seat, notes }
    enum VerifyState {
        case idle
        case verifying
        case verified(game: AttendedGame, notice: String?)
        case notFound
        case savedUnverified
    }

    private var ballpark: Ballpark { Ballpark.by(id: ballparkId) ?? Ballpark.all[0] }
    private var resolvedHomeTeamId: String {
        homeTeamId.isEmpty ? ballpark.team.id : homeTeamId
    }
    private var canVerify: Bool { resolvedHomeTeamId != awayTeamId }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()
                FieldLinesBackground()
                    .opacity(0.06)
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: 16) {
                        Header()

                        FormCard(title: "When") {
                            DatePicker(
                                "Game date",
                                selection: $date,
                                in: ...Date.now,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .tint(Team.by(id: resolvedHomeTeamId)?.primary ?? Theme.clay)
                            .foregroundStyle(Theme.textPrimary)
                        }

                        FormCard(title: "Where") {
                            BallparkPicker(selection: $ballparkId, onChange: { newId in
                                if let bp = Ballpark.by(id: newId) {
                                    homeTeamId = bp.team.id
                                }
                            })
                        }

                        FormCard(title: "Matchup") {
                            VStack(spacing: 10) {
                                TeamRow(
                                    label: "Home",
                                    selection: Binding(
                                        get: { resolvedHomeTeamId },
                                        set: { homeTeamId = $0 }
                                    )
                                )
                                TeamRow(label: "Away", selection: $awayTeamId)
                                if !canVerify {
                                    Text("Home and away can't be the same team.")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.foul)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }

                        if case .idle = verifyState {
                            FormCard(title: "Your best guess at the score") {
                                HStack(spacing: 12) {
                                    ScoreStepper(
                                        label: Team.by(id: awayTeamId)?.abbreviation ?? "AWAY",
                                        accent: Team.by(id: awayTeamId)?.primary ?? Theme.clay,
                                        value: $awayScore
                                    )
                                    ScoreStepper(
                                        label: Team.by(id: resolvedHomeTeamId)?.abbreviation ?? "HOME",
                                        accent: Team.by(id: resolvedHomeTeamId)?.primary ?? Theme.clay,
                                        value: $homeScore
                                    )
                                }
                            }

                            FormCard(title: "You rooted for") {
                                Picker("Rooted for", selection: $userRootedForHome) {
                                    Text(Team.by(id: resolvedHomeTeamId)?.abbreviation ?? "Home").tag(true)
                                    Text(Team.by(id: awayTeamId)?.abbreviation ?? "Away").tag(false)
                                }
                                .pickerStyle(.segmented)
                            }

                            FormCard(title: "Seat (optional)") {
                                VStack(spacing: 8) {
                                    HStack(spacing: 8) {
                                        LabeledInput(label: "Section", text: $section)
                                            .focused($focusedField, equals: .section)
                                        LabeledInput(label: "Row", text: $row)
                                            .focused($focusedField, equals: .row)
                                        LabeledInput(label: "Seat", text: $seat)
                                            .focused($focusedField, equals: .seat)
                                    }
                                }
                            }
                        }

                        // Verification result
                        Group {
                            switch verifyState {
                            case .verified(_, let notice):
                                VerifiedNotice(message: notice)
                            case .notFound:
                                NotFoundNotice(date: date, home: resolvedHomeTeamId, away: awayTeamId) {
                                    verifyState = .idle
                                } saveAnyway: {
                                    saveUnverified()
                                }
                            case .savedUnverified:
                                SavedUnverifiedNotice()
                            case .verifying:
                                VerifyingNotice()
                            case .idle:
                                EmptyView()
                            }
                        }
                        .padding(.horizontal, 16)

                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Add a Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    switch verifyState {
                    case .verifying:
                        ProgressView().tint(Theme.lights)
                    case .verified(let game, _):
                        Button("Save", action: { saveVerified(game) })
                            .fontWeight(.heavy)
                            .foregroundStyle(Theme.grass)
                    default:
                        Button("Verify & Save", action: verifyAndSave)
                            .fontWeight(.heavy)
                            .foregroundStyle(canVerify ? Theme.lights : Theme.textMuted)
                            .disabled(!canVerify)
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") { focusedField = nil }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func verifyAndSave() {
        guard canVerify else { return }
        verifyState = .verifying

        let homeMlbId = Team.by(id: resolvedHomeTeamId)?.mlbId ?? 0
        let awayMlbId = Team.by(id: awayTeamId)?.mlbId ?? 0
        guard homeMlbId > 0, awayMlbId > 0 else {
            verifyState = .notFound
            verifyMessage = "Couldn't resolve team IDs."
            return
        }

        Task { @MainActor in
            let found: Bool
            if let results = try? await MLBStatsService.shared.games(on: date, teamMlbId: homeMlbId) {
                let match = results.first { result in
                    (result.homeMlbId == homeMlbId && result.awayMlbId == awayMlbId) ||
                    (result.awayMlbId == homeMlbId && result.homeMlbId == awayMlbId)
                }
                if let match {
                    // Found the real game — build with verified data.
                    guard let baseGame = AttendedGame.from(
                        result: match,
                        source: "Manual entry (verified)",
                        emailSubject: "Manual entry · \(ballpark.name)",
                        favoriteTeamId: store.favoriteTeamId,
                        section: section.isEmpty ? "—" : section,
                        row: row.isEmpty ? "—" : row,
                        seat: seat.isEmpty ? "—" : seat,
                        confirmation: nil
                    ) else {
                        verifyState = .notFound
                        verifyMessage = "Couldn't resolve the ballpark for this game."
                        return
                    }

                    let enrichedGame: AttendedGame
                    if !baseGame.isUpcoming, let details = await MLBStatsService.shared.details(forGamePk: match.gamePk) {
                        enrichedGame = baseGame.enriched(with: details)
                    } else {
                        enrichedGame = baseGame
                    }

                    // Check for score discrepancy
                    let notice: String?
                    let userEnteredScore = homeScore > 0 || awayScore > 0
                    let realScoreDiffers = userEnteredScore && (homeScore != enrichedGame.homeScore || awayScore != enrichedGame.awayScore)
                    if realScoreDiffers {
                        notice = "Final was \(enrichedGame.awayScore)–\(enrichedGame.homeScore) — updated to match the official box score"
                    } else {
                        notice = nil
                    }

                    withAnimation(.snappy) {
                        verifyState = .verified(game: enrichedGame, notice: notice)
                    }
                    found = true
                } else {
                    found = false
                }
            } else {
                // Offline — save unverified, auto re-verify later.
                withAnimation(.snappy) {
                    saveUnverified()
                }
                return
            }

            if !found {
                withAnimation(.snappy) {
                    verifyState = .notFound
                    verifyMessage = "We couldn't find that matchup on that date."
                }
            }
        }
    }

    private func saveUnverified() {
        let game = makeGame(isVerified: false, status: .completed)
        if store.addManualGame(game) != nil {
            verifyState = .savedUnverified
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
        }
    }

    private func saveVerified(_ game: AttendedGame) {
        if store.addManualGame(game) != nil {
            dismiss()
        }
    }

    private func makeGame(isVerified: Bool, status: AttendedGame.Status) -> AttendedGame {
        AttendedGame(
            id: UUID(),
            date: date,
            ballparkId: ballparkId,
            homeTeamId: resolvedHomeTeamId,
            awayTeamId: awayTeamId,
            homeScore: homeScore,
            awayScore: awayScore,
            userRootedForHome: userRootedForHome,
            section: section.isEmpty ? "—" : section,
            row: row.isEmpty ? "—" : row,
            seat: seat.isEmpty ? "—" : seat,
            confirmation: nil,
            weather: weather,
            firstPitchTempF: isVerified ? 72 : 72,
            attendance: isVerified ? ballpark.capacity : ballpark.capacity,
            durationMinutes: isVerified ? 180 : 180,
            highlights: [],
            milestones: [],
            emailSubject: "Manual entry · \(ballpark.name)",
            source: isVerified ? "Manual entry (verified)" : "Manual entry (unverified)",
            status: status,
            isVerified: isVerified
        )
    }
}

// MARK: - Verification UI

private struct VerifyingNotice: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Theme.lights)
            Text("Checking the official box score…")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(14)
        .nightCard()
    }
}

private struct VerifiedNotice: View {
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.grass)
                Text("Verified — official box score matched")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.grass)
                Spacer()
            }
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .nightCard()
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.grass.opacity(0.3), lineWidth: 1)
        )
    }
}

private struct NotFoundNotice: View {
    let date: Date
    let home: String
    let away: String
    let retry: () -> Void
    let saveAnyway: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.lights)
                Text("Couldn't confirm this matchup")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.lights)
                Spacer()
            }
            Text("We couldn't find a game between \(Team.by(id: home)?.fullName ?? home) and \(Team.by(id: away)?.fullName ?? away) on \(date.formatted(date: .abbreviated, time: .omitted)).")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: retry) {
                    Text("Adjust & retry")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.lights)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().strokeBorder(Theme.lights.opacity(0.5), lineWidth: 1)
                        )
                }
                Button(action: saveAnyway) {
                    Text("Save anyway")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().strokeBorder(Theme.textMuted.opacity(0.4), lineWidth: 1)
                        )
                }
            }
        }
        .padding(14)
        .nightCard()
    }
}

private struct SavedUnverifiedNotice: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.lights)
            Text("Saved — we'll verify it on the next refresh.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(14)
        .nightCard()
    }
}

// MARK: - Header

private struct Header: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "ticket")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.lights)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.lights.opacity(0.18)))

            Text("ADD A GAME BY HAND")
                .font(.caps(11, weight: .heavy))
                .tracking(4)
                .foregroundStyle(Theme.clay)

            Text("We'll verify against the real box score after you hit Verify & Save.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }
}

// MARK: - Reusable form pieces

private struct FormCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caps(10, weight: .heavy))
                .tracking(2.2)
                .foregroundStyle(Theme.clay)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
    }
}

private struct BallparkPicker: View {
    @Binding var selection: String
    let onChange: (String) -> Void

    var body: some View {
        Menu {
            ForEach(Ballpark.all) { bp in
                Button {
                    selection = bp.id
                    onChange(bp.id)
                } label: {
                    Label(bp.name, systemImage: bp.id == selection ? "checkmark" : "")
                }
            }
        } label: {
            HStack {
                let bp = Ballpark.by(id: selection) ?? Ballpark.all[0]
                VStack(alignment: .leading, spacing: 2) {
                    Text(bp.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(bp.city), \(bp.state)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.cardElevated)
            )
        }
    }
}

private struct TeamRow: View {
    let label: String
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(.caps(10, weight: .heavy))
                .tracking(2)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 48, alignment: .leading)

            Menu {
                ForEach(Team.all) { team in
                    Button {
                        selection = team.id
                    } label: {
                        Label(team.fullName, systemImage: team.id == selection ? "checkmark" : "")
                    }
                }
            } label: {
                let team = Team.by(id: selection) ?? .yankees
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(team.primary)
                        Circle().strokeBorder(team.secondary, lineWidth: 1.5)
                        Text(team.abbreviation)
                            .font(.stat(11, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 28, height: 28)

                    Text(team.fullName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.cardElevated)
                )
            }
        }
    }
}

private struct ScoreStepper: View {
    let label: String
    let accent: Color
    @Binding var value: Int

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.stat(12, weight: .heavy))
                .foregroundStyle(accent)
            Text("\(value)")
                .font(.scoreboard(40, weight: .black))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            HStack(spacing: 8) {
                StepperButton(symbol: "minus") {
                    if value > 0 { value -= 1 }
                }
                StepperButton(symbol: "plus") {
                    if value < 30 { value += 1 }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(0.4), lineWidth: 1)
        )
    }
}

private struct StepperButton: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.card)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct LabeledInput: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caps(9, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(Theme.textMuted)
            TextField("—", text: $text)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.cardElevated)
                )
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
