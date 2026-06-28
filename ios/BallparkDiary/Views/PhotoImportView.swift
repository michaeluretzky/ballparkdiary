import SwiftUI
import UIKit
import CoreLocation

/// Add a game from a single photo. The user picks a snapshot they took at the
/// ballpark; the app reads the photo's embedded GPS + date, pins the stadium,
/// and matches the date against the free MLB Stats API to recover the exact
/// matchup — then lets the user review and save it. Entirely free, on-device
/// metadata; only the score lookup hits the public MLB API.
struct PhotoImportView: View {
    @Environment(DiaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .intro
    @State private var showPicker: Bool = false
    @State private var previewImage: UIImage?
    @State private var heading: Double?

    enum Phase: Equatable {
        case intro
        case analyzing
        case resolved(game: AttendedGame, parkId: String)
        case noLocation
        case tooFar(parkId: String, miles: Double)
        case noGame(parkId: String, date: Date)
        case saved(matchup: String)
        case duplicate
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

                        if let previewImage {
                            PhotoPreview(image: previewImage)
                        }

                        content

                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Photo Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .sheet(isPresented: $showPicker) {
                PhotoMetadataPicker { result in
                    handlePick(result)
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Phase content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .intro:
            IntroCard { showPicker = true }

        case .analyzing:
            AnalyzingCard()

        case let .resolved(game, parkId):
            ResolvedCard(
                game: game,
                park: Ballpark.by(id: parkId) ?? game.ballpark,
                heading: heading,
                onSave: { save(game) },
                onRetry: { reset() }
            )

        case .noLocation:
            NoticeCard(
                symbol: "location.slash.fill",
                tint: Theme.foul,
                title: "No location in this photo",
                message: "This picture doesn't carry GPS data, so we can't pin the stadium. Photos taken with Location turned on work best. You can still add the game by hand.",
                primaryLabel: "Pick another photo",
                primaryAction: { reset() }
            )

        case let .tooFar(parkId, miles):
            NoticeCard(
                symbol: "mappin.slash",
                tint: Theme.lights,
                title: "Doesn't look like a ballpark",
                message: "The nearest MLB park to this photo is \(Ballpark.by(id: parkId)?.name ?? "unknown"), about \(milesText(miles)) away — too far to be a game photo. Try a picture you took inside the stadium.",
                primaryLabel: "Pick another photo",
                primaryAction: { reset() }
            )

        case let .noGame(parkId, date):
            NoticeCard(
                symbol: "calendar.badge.exclamationmark",
                tint: Theme.lights,
                title: "Found the park, not the game",
                message: "This looks like \(Ballpark.by(id: parkId)?.name ?? "a ballpark"), but there's no MLB game on record for \(date.formatted(.dateTime.month().day().year())). It may have been a different event — or you can add it manually.",
                primaryLabel: "Pick another photo",
                primaryAction: { reset() }
            )

        case let .saved(matchup):
            SavedCard(matchup: matchup)

        case .duplicate:
            NoticeCard(
                symbol: "checkmark.circle.fill",
                tint: Theme.grass,
                title: "Already in your diary",
                message: "This game is already saved — no need to add it twice.",
                primaryLabel: "Pick another photo",
                primaryAction: { reset() }
            )
        }
    }

    // MARK: - Logic

    private func reset() {
        previewImage = nil
        heading = nil
        phase = .intro
        showPicker = true
    }

    private func handlePick(_ result: PhotoPickResult?) {
        guard let result else { return } // user cancelled
        if let data = result.imageData { previewImage = UIImage(data: data) }
        heading = result.heading

        guard let coordinate = result.coordinate else {
            phase = .noLocation
            return
        }
        guard let match = PhotoGameLocator.shared.nearestPark(to: coordinate) else {
            phase = .noLocation
            return
        }
        if match.miles > PhotoGameLocator.maxParkRadiusMiles {
            phase = .tooFar(parkId: match.park.id, miles: match.miles)
            return
        }

        let park = match.park
        guard let date = result.captureDate else {
            phase = .noGame(parkId: park.id, date: .now)
            return
        }

        phase = .analyzing
        Task { @MainActor in
            guard let gameResult = await PhotoGameLocator.shared.resolveGame(ballpark: park, around: date) else {
                phase = .noGame(parkId: park.id, date: date)
                return
            }
            guard var game = AttendedGame.from(
                result: gameResult,
                ballpark: park,
                source: "Photo match",
                emailSubject: "Photo · \(park.name)",
                favoriteTeamId: store.favoriteTeamId
            ) else {
                phase = .noGame(parkId: park.id, date: date)
                return
            }
            // Enrich finished games with verified box-score facts immediately.
            if !game.isUpcoming,
               let details = await MLBStatsService.shared.details(forGamePk: gameResult.gamePk) {
                game = game.enriched(with: details)
            }
            phase = .resolved(game: game, parkId: park.id)
        }
    }

    private func save(_ game: AttendedGame) {
        if store.addManualGame(game) != nil {
            store.lastImportedGameId = game.id
            let matchup = "\(game.awayTeam.fullName) @ \(game.homeTeam.fullName)"
            phase = .saved(matchup: matchup)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { dismiss() }
        } else {
            phase = .duplicate
        }
    }

    private func milesText(_ miles: Double) -> String {
        miles < 1 ? "\(Int(miles * 5280)) ft" : String(format: "%.1f mi", miles)
    }
}

// MARK: - Header

private struct Header: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.badge.magnifyingglass")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.lights)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.lights.opacity(0.18)))

            Text("ADD A GAME FROM A PHOTO")
                .font(.caps(11, weight: .heavy))
                .tracking(4)
                .foregroundStyle(Theme.clay)

            Text("Pick a photo you took at the ballpark — we'll read its location and date to find the game.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
        }
        .padding(.top, 4)
    }
}

// MARK: - Photo preview

private struct PhotoPreview: View {
    let image: UIImage

    var body: some View {
        Color(.secondarySystemBackground)
            .frame(height: 180)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Intro

private struct IntroCard: View {
    let onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HowStep(number: "1", text: "Choose a photo you snapped at the stadium.")
                HowStep(number: "2", text: "We read its hidden GPS to pin the exact ballpark.")
                HowStep(number: "3", text: "The date is matched to the real MLB box score.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.cardElevated)
            )

            Button(action: onPick) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 16, weight: .bold))
                    Text("Choose a photo")
                        .font(.system(size: 16, weight: .heavy))
                }
                .foregroundStyle(Theme.nightDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.lights)
                )
            }
            .buttonStyle(.plain)

            Text("Nothing leaves your phone except a public score lookup. The photo and its location stay on your device.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(16)
        .nightCard()
    }
}

private struct HowStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.lights)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.lights.opacity(0.16)))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Analyzing

private struct AnalyzingCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ProgressView().tint(Theme.lights)
            VStack(alignment: .leading, spacing: 2) {
                Text("Reading the photo…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Pinning the ballpark and matching the box score")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .nightCard()
    }
}

// MARK: - Resolved

private struct ResolvedCard: View {
    let game: AttendedGame
    let park: Ballpark
    let heading: Double?
    let onSave: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.grass)
                    Text("We found your game")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.grass)
                    Spacer()
                }

                // Matchup
                HStack(spacing: 14) {
                    TeamLogoView(team: game.awayTeam, size: 44, showGloss: false)
                    VStack(spacing: 2) {
                        Text(game.isUpcoming ? "vs" : "\(game.awayScore) – \(game.homeScore)")
                            .font(.scoreboard(22, weight: .black))
                            .foregroundStyle(Theme.textPrimary)
                        Text(game.date.formatted(.dateTime.month().day().year()))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    TeamLogoView(team: game.homeTeam, size: 44, showGloss: false)
                }

                Divider().overlay(Color.white.opacity(0.08))

                DetailRow(icon: "building.columns.fill", label: "Ballpark", value: park.name)
                DetailRow(icon: "mappin.and.ellipse", label: "City", value: "\(park.city), \(park.state)")
                if let heading {
                    DetailRow(
                        icon: "location.north.line.fill",
                        label: "Camera faced",
                        value: PhotoGameLocator.compassLabel(forHeading: heading)
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.cardElevated)
            )

            Button(action: onSave) {
                Text("Add to my diary")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.nightDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.grass)
                    )
            }
            .buttonStyle(.plain)

            Button(action: onRetry) {
                Text("That's not it — pick another photo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .nightCard()
    }
}

private struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.clay)
                .frame(width: 22)
            Text(label.uppercased())
                .font(.caps(9, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Theme.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Notice & Saved

private struct NoticeCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    let primaryLabel: String
    let primaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: primaryAction) {
                Text(primaryLabel)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.nightDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.lights)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(16)
        .nightCard()
    }
}

private struct SavedCard: View {
    let matchup: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.grass)
            Text("Added to your diary")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text(matchup)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
        .nightCard()
    }
}
