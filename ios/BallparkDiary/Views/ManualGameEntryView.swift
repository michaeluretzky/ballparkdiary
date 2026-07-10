import SwiftUI

/// Manual game entry form for ballparks visited before digital ticketing,
/// stub-and-paper ticket games, or anything not surfaced by an inbox scan.
/// Now verifies against the real MLB box score — the user picks a matchup
/// and date, and we confirm it against the live schedule before saving.
struct ManualGameEntryView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date = .now
    @State private var ballparkId: String = Ballpark.all[0].id
    @State private var homeTeamId: String = ""
    @State private var awayTeamId: String = Team.redSox.id
    @State private var homeScore: Int = 0
    @State private var awayScore: Int = 0
    @State private var userRootedForHome: Bool? = true
    @State private var userRootedForNeither: Bool = false
    @State private var section: String = ""
    @State private var row: String = ""
    @State private var seat: String = ""
    @State private var weather: AttendedGame.Weather = .clear
    @State private var companions: String = ""
    @State private var memory: String = ""
    @FocusState private var focusedField: Field?

    // Verification state
    @State private var verifyState: VerifyState = .idle
    @State private var verifyMessage: String = ""
    @State private var resolvingUnsure: Bool = false

    // Duplicate feedback — the save button must never silently fail.
    @State private var exactDuplicate: AttendedGame?
    @State private var nearDuplicateExisting: AttendedGame?
    @State private var pendingSave: AttendedGame?
    @State private var pendingSaveIsUnverified: Bool = false

    enum Field: Hashable { case section, row, seat, companions, memory }
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
    /// Sentinel value meaning the user doesn't remember this team — the app
    /// will scan the schedule on the selected date using the other (known) team
    /// to fill in the missing opponent.
    fileprivate static let unsureTeamId = "__unsure__"

    private var isHomeUnsure: Bool { homeTeamId.isEmpty || homeTeamId == Self.unsureTeamId }
    private var isAwayUnsure: Bool { awayTeamId == Self.unsureTeamId }

    private var canVerify: Bool {
        // Both unsure — nothing to search by
        if isHomeUnsure && isAwayUnsure { return false }
        // Both known and different — normal verify
        if !isHomeUnsure && !isAwayUnsure { return resolvedHomeTeamId != awayTeamId }
        // One unsure, other known — can scan
        return true
    }

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
                                    let msg: String = {
                                        if isHomeUnsure && isAwayUnsure {
                                            return "Pick at least one team so we can look up the matchup."
                                        }
                                        return "Home and away can't be the same team."
                                    }()
                                    Text(msg)
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
                                        label: Team.by(id: awayTeamId)?.fullName ?? "AWAY",
                                        accent: Team.by(id: awayTeamId)?.primary ?? Theme.clay,
                                        value: $awayScore
                                    )
                                    ScoreStepper(
                                        label: Team.by(id: resolvedHomeTeamId)?.fullName ?? "HOME",
                                        accent: Team.by(id: resolvedHomeTeamId)?.primary ?? Theme.clay,
                                        value: $homeScore
                                    )
                                }
                            }

                            FormCard(title: "You rooted for") {
                                Picker("Rooted for", selection: Binding<Int>(
                                    get: {
                                        if userRootedForNeither { return 2 }
                                        return userRootedForHome == true ? 0 : 1
                                    },
                                    set: { val in
                                        switch val {
                                        case 0: userRootedForHome = true; userRootedForNeither = false
                                        case 1: userRootedForHome = false; userRootedForNeither = false
                                        default: userRootedForHome = nil; userRootedForNeither = true
                                        }
                                    }
                                )) {
                                    Text(Team.by(id: resolvedHomeTeamId)?.fullName ?? "Home").tag(0)
                                    Text(Team.by(id: awayTeamId)?.fullName ?? "Away").tag(1)
                                    Text("Neither").tag(2)
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

                            FormCard(title: "Memories (optional)") {
                                VStack(spacing: 8) {
                                    LabeledInput(label: "Went with", text: $companions)
                                        .focused($focusedField, equals: .companions)
                                    LabeledInput(label: "Notes", text: $memory, multiline: true, autocap: false)
                                        .focused($focusedField, equals: .memory)
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
            .alert(
                "Already in your diary",
                isPresented: Binding(
                    get: { exactDuplicate != nil },
                    set: { if !$0 { exactDuplicate = nil } }
                )
            ) {
                Button("OK") {
                    exactDuplicate = nil
                    dismiss()
                }
            } message: {
                Text(exactDuplicateMessage)
            }
            .alert(
                "Possible duplicate",
                isPresented: Binding(
                    get: { nearDuplicateExisting != nil },
                    set: { if !$0 { nearDuplicateExisting = nil } }
                )
            ) {
                Button("Save Anyway") { saveAnyway() }
                Button("Cancel", role: .cancel) {
                    nearDuplicateExisting = nil
                    pendingSave = nil
                }
            } message: {
                Text(nearDuplicateMessage)
            }
        }
    }

    private var exactDuplicateMessage: String {
        guard let g = exactDuplicate else { return "" }
        return "\(g.awayTeam.fullName) @ \(g.homeTeam.fullName) on \(g.date.formatted(date: .abbreviated, time: .omitted)) is already saved — no need to add it again."
    }

    private var nearDuplicateMessage: String {
        guard let g = nearDuplicateExisting else { return "" }
        return "This looks a lot like \(g.awayTeam.fullName) @ \(g.homeTeam.fullName) on \(g.date.formatted(date: .abbreviated, time: .omitted)), which is already in your diary. Save this as a separate game?"
    }

    // MARK: - Actions

    private func verifyAndSave() {
        guard canVerify else { return }
        verifyState = .verifying
        resolvingUnsure = isHomeUnsure || isAwayUnsure

        // When one team is unknown, scan the schedule using the known team
        // and fill in the missing opponent from the first matching game.
        if resolvingUnsure {
            let knownTeamId = isHomeUnsure ? awayTeamId : resolvedHomeTeamId
            guard let knownMlbId = Team.by(id: knownTeamId)?.mlbId, knownMlbId > 0 else {
                verifyState = .notFound
                verifyMessage = "Couldn't resolve the known team."
                return
            }

            Task { @MainActor in
                guard let results = try? await MLBStatsService.shared.games(on: date, teamMlbId: knownMlbId),
                      let match = results.first
                else {
                    withAnimation(Theme.Motion.snappy) {
                        verifyState = .notFound
                        verifyMessage = "We couldn't find a game for that team on that date."
                    }
                    return
                }

                // Resolve the missing team from the actual matchup
                let resolvedHomeMlbId = isHomeUnsure ? match.homeMlbId : Team.by(id: resolvedHomeTeamId)?.mlbId ?? 0
                let resolvedAwayMlbId = isAwayUnsure ? match.awayMlbId : Team.by(id: awayTeamId)?.mlbId ?? 0

                // Update team selections from the real data
                if isHomeUnsure, let resolvedTeam = Team.by(mlbId: match.homeMlbId) {
                    homeTeamId = resolvedTeam.id
                }
                if isAwayUnsure, let resolvedTeam = Team.by(mlbId: match.awayMlbId) {
                    awayTeamId = resolvedTeam.id
                }

                await finishVerification(with: match)
            }
            return
        }

        let homeMlbId = Team.by(id: resolvedHomeTeamId)?.mlbId ?? 0
        let awayMlbId = Team.by(id: awayTeamId)?.mlbId ?? 0
        guard homeMlbId > 0, awayMlbId > 0 else {
            verifyState = .notFound
            verifyMessage = "Couldn't resolve team IDs."
            return
        }

        Task { @MainActor in
            if let results = try? await MLBStatsService.shared.games(on: date, teamMlbId: homeMlbId) {
                let match = results.first { result in
                    (result.homeMlbId == homeMlbId && result.awayMlbId == awayMlbId) ||
                    (result.awayMlbId == homeMlbId && result.homeMlbId == awayMlbId)
                }
                if let match {
                    await finishVerification(with: match)
                } else {
                    withAnimation(Theme.Motion.snappy) {
                        verifyState = .notFound
                        verifyMessage = "We couldn't find that matchup on that date."
                    }
                }
            } else {
                // Offline — save unverified, auto re-verify later.
                withAnimation(Theme.Motion.snappy) {
                    saveUnverified()
                }
            }
        }
    }

    /// Shared verification finalization: enrich with box score details and
    /// surface any score discrepancies.
    @MainActor
    private func finishVerification(with match: MLBGameResult) async {
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

        var enrichedGame: AttendedGame
        if !baseGame.isUpcoming, let details = await MLBStatsService.shared.details(forGamePk: match.gamePk) {
            enrichedGame = baseGame.enriched(with: details)
        } else {
            enrichedGame = baseGame
        }

        // Preserve the user's explicit choices — AttendedGame.from ignores
        // the form's rooting, companions, and memory fields.
        let userRoot: Bool? = userRootedForNeither ? nil : userRootedForHome
        enrichedGame = enrichedGame.rooting(forHome: userRoot)
        enrichedGame = enrichedGame.withMemory(
            companions: companions.trimmingCharacters(in: .whitespaces),
            memory: memory.trimmingCharacters(in: .whitespaces)
        )

        // Build an appropriate notice
        let notice: String?
        let userEnteredScore = homeScore > 0 || awayScore > 0
        let realScoreDiffers = userEnteredScore && (homeScore != enrichedGame.homeScore || awayScore != enrichedGame.awayScore)

        if resolvingUnsure {
            let found = "Found \(enrichedGame.awayTeam.fullName) @ \(enrichedGame.homeTeam.fullName)"
            if realScoreDiffers {
                notice = "\(found). Final was \(enrichedGame.awayScore)–\(enrichedGame.homeScore) — updated to match the official box score"
            } else {
                notice = found
            }
        } else if realScoreDiffers {
            notice = "Final was \(enrichedGame.awayScore)–\(enrichedGame.homeScore) — updated to match the official box score"
        } else {
            notice = nil
        }

        withAnimation(Theme.Motion.snappy) {
            verifyState = .verified(game: enrichedGame, notice: notice)
        }
    }

    private func saveUnverified() {
        let game = makeGame(isVerified: false, status: .completed)
        handleSaveOutcome(store.addManualGameDetailed(game), pending: game, unverified: true)
    }

    private func saveVerified(_ game: AttendedGame) {
        handleSaveOutcome(store.addManualGameDetailed(game), pending: game, unverified: false)
    }

    /// Routes every save attempt through visible feedback — an exact duplicate
    /// explains itself and closes; a near-duplicate asks before saving anyway.
    private func handleSaveOutcome(
        _ outcome: DiaryStore.ManualAddOutcome,
        pending: AttendedGame,
        unverified: Bool
    ) {
        switch outcome {
        case .added:
            if unverified {
                verifyState = .savedUnverified
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
            } else {
                dismiss()
            }
        case .exactDuplicate(let existing):
            exactDuplicate = existing
        case .nearDuplicate(let existing):
            nearDuplicateExisting = existing
            pendingSave = pending
            pendingSaveIsUnverified = unverified
        }
    }

    /// User confirmed the near-duplicate is a separate game — save it,
    /// skipping the fuzzy check (exact duplicates are still rejected).
    private func saveAnyway() {
        guard let pending = pendingSave else { return }
        nearDuplicateExisting = nil
        pendingSave = nil
        let outcome = store.addManualGameDetailed(pending, bypassNearDuplicateCheck: true)
        switch outcome {
        case .added:
            if pendingSaveIsUnverified {
                verifyState = .savedUnverified
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
            } else {
                dismiss()
            }
        case .exactDuplicate(let existing):
            exactDuplicate = existing
        case .nearDuplicate:
            break
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
            userRootedForHome: userRootedForNeither ? nil : userRootedForHome,
            section: section.isEmpty ? "—" : section,
            row: row.isEmpty ? "—" : row,
            seat: seat.isEmpty ? "—" : seat,
            confirmation: nil,
            weather: weather,
            firstPitchTempF: 0,
            attendance: 0,
            durationMinutes: 0,
            highlights: [],
            milestones: [],
            pitching: [],
            companions: companions.trimmingCharacters(in: .whitespaces),
            memory: memory.trimmingCharacters(in: .whitespaces),
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
                Text("Verified against the official box score")
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
            Text("We couldn't find a game between \(Team.by(id: home)?.fullName ?? home) and \(Team.by(id: away)?.fullName ?? away) on \(date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))).")
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
            Text("Saved. We'll verify it on the next refresh.")
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
                Divider()
                Button {
                    selection = ManualGameEntryView.unsureTeamId
                } label: {
                    Label("I'm not sure", systemImage: selection == ManualGameEntryView.unsureTeamId ? "checkmark" : "questionmark")
                }
            } label: {
                let isUnsure = selection == ManualGameEntryView.unsureTeamId
                let team = Team.by(id: selection) ?? .yankees
                HStack(spacing: 10) {
                    if isUnsure {
                        ZStack {
                            Circle().fill(Theme.cardElevated)
                            Circle().strokeBorder(Theme.textMuted.opacity(0.3), lineWidth: 1.5)
                            Image(systemName: "questionmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .frame(width: 36, height: 36)
                        Text("I'm not sure")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                    } else {
                        ZStack {
                            Circle().fill(team.primary)
                            Circle().strokeBorder(team.secondary, lineWidth: 1.5)
                            TeamLogoView(team: team, size: 36, showGloss: false)
                        }
                        .frame(width: 36, height: 36)
                        Text(team.fullName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
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
                .animation(Theme.Motion.snappy, value: value)
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

struct LabeledInput: View {
    let label: String
    @Binding var text: String
    var multiline: Bool = false
    var autocap: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caps(9, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(Theme.textMuted)
            if multiline {
                TextField("—", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .textInputAutocapitalization(autocap ? .sentences : .characters)
                    .autocorrectionDisabled(!autocap)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.cardElevated)
                    )
                    .foregroundStyle(Theme.textPrimary)
            } else {
                TextField("—", text: $text)
                    .textInputAutocapitalization(autocap ? .characters : .none)
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
}
