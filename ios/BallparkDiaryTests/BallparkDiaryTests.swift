//
//  BallparkDiaryTests.swift
//  BallparkDiaryTests
//
//  Unit coverage for the pure logic that protects diary integrity: ticket
//  parsing (dates, teams, seats), milestone detection, game construction, and
//  cross-source deduplication. These are the functions most likely to silently
//  regress and corrupt a user's diary, so they get real assertions.
//

import Testing
import Foundation
@testable import BallparkDiary

// MARK: - Ticket parser: date extraction

struct DateHintTests {

    /// A spelled-out date must win, and a seat range like "Seats 11-12" must not
    /// be mis-read as a November 12 date.
    @Test func seatRangeIsNotParsedAsDate() {
        let hints = TicketEmailParser.extractDateHints(
            from: "Yankees vs Red Sox Section 12 Row 5 Seats 11-12 Aug 22, 2022"
        )
        #expect(hints.contains { $0.month == 8 && $0.day == 22 && $0.year == 2022 })
        #expect(!hints.contains { $0.month == 11 && $0.day == 12 })
    }

    /// When a fully-qualified date (explicit 4-digit year) is present, bare
    /// numeric M/D candidates without a year are dropped.
    @Test func explicitYearSuppressesBareNumericDate() {
        let hints = TicketEmailParser.extractDateHints(from: "Game 8/22/2022 — gates 9/1")
        #expect(hints.contains { $0.month == 8 && $0.day == 22 && $0.year == 2022 })
        #expect(!hints.contains { $0.month == 9 && $0.day == 1 })
    }

    /// Impossible calendar dates are rejected outright (no Feb 30, no month 13).
    @Test func invalidCalendarDatesAreRejected() {
        #expect(TicketEmailParser.extractDateHints(from: "see you 2/30 at the park").isEmpty)
        #expect(TicketEmailParser.extractDateHints(from: "kickoff 13/40/2022").isEmpty)
    }

    /// Two-digit years are normalized into the 2000s.
    @Test func twoDigitYearIsNormalized() {
        let hints = TicketEmailParser.extractDateHints(from: "8/22/22")
        #expect(hints.contains { $0.month == 8 && $0.day == 22 && $0.year == 2022 })
    }
}

// MARK: - Ticket parser: team + seat detection

struct TicketDetectionTests {

    /// Word-boundary matching: "helmets" must not register as the Mets, and
    /// "hundreds" must not register as the Reds — so with no real team in the
    /// text, nothing is detected.
    @Test func noFalseTeamMatchesFromSubstrings() {
        let messages = [EmailMessage(
            id: "1",
            subject: "Free helmets giveaway",
            from: "promo@ballpark.com",
            snippet: "Hundreds of fans, Aug 5 2023",
            internalDate: .now
        )]
        #expect(TicketEmailParser.detect(in: messages).isEmpty)
    }

    /// A real matchup yields one candidate with the teams in mention order, the
    /// ticket date, and the parsed seat + confirmation.
    @Test func detectsMatchupSeatAndConfirmation() throws {
        let messages = [EmailMessage(
            id: "1",
            subject: "Yankees vs Red Sox",
            from: "orders@ticketmaster.com",
            snippet: "Aug 22, 2022 Section 12 Row 4 Seat 9 Confirmation ABC123",
            internalDate: .now
        )]
        let detected = TicketEmailParser.detect(in: messages)
        let game = try #require(detected.first)

        #expect(game.teamMlbId == 147)        // Yankees mentioned first
        #expect(game.opponentMlbId == 111)    // Red Sox
        #expect(game.section == "12")
        #expect(game.row == "4")
        #expect(game.seat == "9")
        #expect(game.confirmation == "ABC123")
        #expect(game.dateHints.contains { $0.month == 8 && $0.day == 22 && $0.year == 2022 })
        #expect(game.source == "Ticketmaster")
    }

    /// A ticket with a team but no readable date is intentionally dropped — we
    /// never invent a date the ticket doesn't carry.
    @Test func matchupWithoutDateIsNotDetected() {
        let messages = [EmailMessage(
            id: "1", subject: "Yankees vs Red Sox", from: "x", snippet: "great seats", internalDate: .now
        )]
        #expect(TicketEmailParser.detect(in: messages).isEmpty)
    }
}

// MARK: - Milestone & weather derivation

struct MilestoneTests {

    private func details(homeRuns: [HomeRunPlay] = [], pitching: [PitchingLine] = []) -> GameDetails {
        GameDetails(
            attendance: 40000, durationMinutes: 180, tempF: 72,
            weatherCondition: "Clear", dayNight: "day",
            homeMlbId: 147, awayMlbId: 111,
            scoringPlays: [], homeRuns: homeRuns, pitching: pitching
        )
    }

    private func homeRun(careerTotal: Int?) -> HomeRunPlay {
        HomeRunPlay(
            inning: 5, halfInning: "bottom", batter: "Aaron Judge", batterMlbId: 592450,
            battingTeamMlbId: 147, rbi: 1, seasonHomeRunNumber: 20,
            careerHomeRunTotal: careerTotal, description: "Judge homers (20)"
        )
    }

    private func pitchingLine(
        ip: String = "9.0", hits: Int = 4, runs: Int = 1, walks: Int = 1,
        k: Int = 8, hbp: Int = 0, pitches: Int = 105, cg: Int = 0, sho: Int = 0
    ) -> PitchingLine {
        PitchingLine(
            name: "Gerrit Cole", teamMlbId: 147, inningsPitched: ip,
            hits: hits, runs: runs, walks: walks, strikeOuts: k, hitBatsmen: hbp,
            pitches: pitches, battersFaced: 30, completeGames: cg, shutouts: sho, isWinner: true
        )
    }

    @Test func roundCareerHomeRunMilestoneIsFlagged() {
        let milestones = AttendedGame.milestones(from: details(homeRuns: [homeRun(careerTotal: 500)]))
        #expect(milestones.contains { $0.category == .homeRun && $0.stat == "HR #500" })
    }

    @Test func homeRunWithoutCareerTotalProducesNoMilestone() {
        let milestones = AttendedGame.milestones(from: details(homeRuns: [homeRun(careerTotal: nil)]))
        #expect(milestones.isEmpty)
    }

    @Test func perfectGameIsDetected() {
        let line = pitchingLine(hits: 0, runs: 0, walks: 0, hbp: 0, cg: 1, sho: 1)
        let milestones = AttendedGame.milestones(from: details(pitching: [line]))
        #expect(milestones.contains { $0.title == "Perfect Game" && $0.category == .noHitter })
    }

    @Test func highStrikeoutGameIsDetected() {
        let line = pitchingLine(k: 15, cg: 0)
        let milestones = AttendedGame.milestones(from: details(pitching: [line]))
        #expect(milestones.contains { $0.category == .strikeouts && $0.title == "15-Strikeout Game" })
    }

    @Test func weatherMapsConditionsAndRoofs() {
        #expect(AttendedGame.weather(condition: "Rain", dayNight: "night", roof: .open) == .rain)
        #expect(AttendedGame.weather(condition: "Clear", dayNight: "day", roof: .open) == .clear)
        #expect(AttendedGame.weather(condition: "Clear", dayNight: "night", roof: .open) == .night)
        #expect(AttendedGame.weather(condition: "Sunny", dayNight: "day", roof: .dome) == .dome)
    }
}

// MARK: - Building attended games from MLB results

struct AttendedGameBuildTests {

    private func result(final: Bool, home: Int = 5, away: Int = 3) -> MLBGameResult {
        MLBGameResult(
            gamePk: 1, date: Date(timeIntervalSince1970: 1_660_000_000),
            homeMlbId: 147, awayMlbId: 111, homeScore: home, awayScore: away,
            venueName: "Yankee Stadium", dayNight: "night", isFinal: final
        )
    }

    @Test func upcomingGameHasNoScore() throws {
        let game = try #require(AttendedGame.from(
            result: result(final: false), source: "Test", emailSubject: "s", favoriteTeamId: "nyy"
        ))
        #expect(game.isUpcoming)
        #expect(game.scoreString == "vs")
        #expect(game.homeScore == 0 && game.awayScore == 0)
    }

    @Test func finishedGameCarriesScoreAndRooting() throws {
        let game = try #require(AttendedGame.from(
            result: result(final: true, home: 5, away: 3),
            source: "Test", emailSubject: "s", favoriteTeamId: "nyy"
        ))
        #expect(!game.isUpcoming)
        #expect(game.homeTeamId == "nyy" && game.awayTeamId == "bos")
        #expect(game.userRootedForHome)        // favorite is the home team
        #expect(game.userWon)                   // home rooted for, 5 > 3
    }
}

// MARK: - Diary deduplication

@MainActor
struct DiaryDedupTests {

    private func sampleGame(home: String, away: String, on date: Date) -> AttendedGame {
        AttendedGame(
            id: UUID(), date: date,
            ballparkId: "yankee-stadium", homeTeamId: home, awayTeamId: away,
            homeScore: 4, awayScore: 2, userRootedForHome: true,
            section: "1", row: "1", seat: "1", confirmation: nil,
            weather: .clear, firstPitchTempF: 70, attendance: 40000, durationMinutes: 180,
            highlights: [], milestones: [], emailSubject: "test", source: "Test",
            status: .completed, isVerified: true
        )
    }

    private func purge(_ store: DiaryStore, home: String, away: String, on date: Date) {
        let cal = Calendar(identifier: .gregorian)
        let target = cal.dateComponents([.year, .month, .day], from: date)
        for game in store.games {
            let c = cal.dateComponents([.year, .month, .day], from: game.date)
            let sameTeams = Set([game.homeTeamId, game.awayTeamId]) == Set([home, away])
            if sameTeams, c == target { store.deleteGame(game.id) }
        }
    }

    /// A second game on the same day with the same two teams is rejected, even
    /// with a different id — that's the canonical-key dedup contract.
    @Test func duplicateManualGameIsRejected() {
        let store = DiaryStore()
        let date = DateComponents(calendar: .init(identifier: .gregorian), year: 1995, month: 6, day: 15).date!
        purge(store, home: "nyy", away: "bos", on: date)

        let first = store.addManualGame(sampleGame(home: "nyy", away: "bos", on: date))
        #expect(first != nil)
        let countAfterFirst = store.games.count
        #expect(store.hasGame(day: date, homeTeamId: "nyy", awayTeamId: "bos"))

        let second = store.addManualGame(sampleGame(home: "nyy", away: "bos", on: date))
        #expect(second == nil)
        #expect(store.games.count == countAfterFirst)

        store.deleteGame(first!.id)   // clean up persisted state
    }

    /// Dedup is orientation-independent: home/away swapped is still the same game.
    @Test func swappedHomeAwayIsStillADuplicate() {
        let store = DiaryStore()
        let date = DateComponents(calendar: .init(identifier: .gregorian), year: 1996, month: 7, day: 4).date!
        purge(store, home: "nyy", away: "bos", on: date)

        let first = store.addManualGame(sampleGame(home: "nyy", away: "bos", on: date))
        #expect(first != nil)
        let swapped = store.addManualGame(sampleGame(home: "bos", away: "nyy", on: date))
        #expect(swapped == nil)

        store.deleteGame(first!.id)
    }
}
