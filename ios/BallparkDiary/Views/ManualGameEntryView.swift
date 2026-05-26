import SwiftUI

/// Manual game entry form for ballparks visited before digital ticketing,
/// stub-and-paper ticket games, or anything not surfaced by an inbox scan.
/// Saved games are merged into the same diary as scanned ones and update all
/// totals immediately.
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

    enum Field: Hashable { case section, row, seat, notes }

    private var ballpark: Ballpark { Ballpark.by(id: ballparkId) ?? Ballpark.all[0] }
    private var resolvedHomeTeamId: String {
        homeTeamId.isEmpty ? ballpark.team.id : homeTeamId
    }
    private var canSave: Bool { resolvedHomeTeamId != awayTeamId }

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
                            .tint(Theme.clay)
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
                                if !canSave {
                                    Text("Home and away can't be the same team.")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.foul)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }

                        FormCard(title: "Final score") {
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

                        FormCard(title: "Weather") {
                            Picker("Weather", selection: $weather) {
                                ForEach(AttendedGame.Weather.allCases, id: \.self) { w in
                                    Label(w.rawValue, systemImage: w.symbol).tag(w)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.clay)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        FormCard(title: "Memory (optional)") {
                            TextField("What do you remember from this game?",
                                      text: $notes, axis: .vertical)
                                .lineLimit(3...5)
                                .focused($focusedField, equals: .notes)
                                .foregroundStyle(Theme.textPrimary)
                        }

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
                    Button("Save", action: save)
                        .fontWeight(.heavy)
                        .foregroundStyle(canSave ? Theme.clay : Theme.textMuted)
                        .disabled(!canSave)
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

    private func save() {
        guard canSave else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let highlights: [AttendedGame.Highlight] = trimmedNotes.isEmpty ? [] : [
            .init(inning: "—", description: trimmedNotes, kind: .hit)
        ]
        let game = AttendedGame(
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
            weather: weather,
            firstPitchTempF: 72,
            attendance: ballpark.capacity,
            durationMinutes: 180,
            highlights: highlights,
            milestones: [],
            emailSubject: "Manual entry · \(ballpark.name)",
            source: "Manual entry"
        )
        store.addManualGame(game)
        dismiss()
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

            Text("For games older than digital tickets, paper stubs, or any game we missed.")
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
