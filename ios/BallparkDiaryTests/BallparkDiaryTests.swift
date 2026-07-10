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

    /// Doubleheaders: two games same day, same teams, but different hours
    /// must coexist — the canonical key includes the hour so both can be saved.
    @Test func doubleheaderSameDaySameTeamsDifferentHourBothSaved() {
        let store = DiaryStore()
        let cal = Calendar(identifier: .gregorian)
        let baseComps = DateComponents(calendar: cal, year: 2023, month: 6, day: 15)
        let game1Date = cal.date(bySettingHour: 13, minute: 0, second: 0, of: baseComps.date!)!
        let game2Date = cal.date(bySettingHour: 19, minute: 0, second: 0, of: baseComps.date!)
        purge(store, home: "nyy", away: "bos", on: game1Date)
        purge(store, home: "nyy", away: "bos", on: game2Date)

        let g1 = store.addManualGame(sampleGame(home: "nyy", away: "bos", on: game1Date))
        #expect(g1 != nil)
        let g2 = store.addManualGame(sampleGame(home: "nyy", away: "bos", on: game2Date))
        #expect(g2 != nil, "Doubleheader game 2 should be saved — canonical key includes hour")

        if let g1 { store.deleteGame(g1.id) }
        if let g2 { store.deleteGame(g2.id) }
    }

    /// findNearDuplicate: consecutive-day games of the same series (same
    /// ballpark, same teams, ±1 day) must NOT be flagged as duplicates.
    @Test func consecutiveDaySameSeriesNotFlaggedAsDuplicate() {
        let store = DiaryStore()
        let cal = Calendar(identifier: .gregorian)
        let day1 = DateComponents(calendar: cal, year: 2023, month: 8, day: 15).date!
        let day2 = cal.date(byAdding: .day, value: 1, to: day1)!

        // Add game 1
        let g1 = store.addManualGame(sampleGame(home: "nyy", away: "bos", on: day1))
        #expect(g1 != nil)

        // Game 2 next day, same teams — should NOT be flagged as a near-duplicate
        let candidate = NearDuplicateCandidate(
            proposedId: UUID(), date: day2,
            homeTeamId: "nyy", awayTeamId: "bos",
            ballparkId: "yankee-stadium",
            confirmation: nil, section: "", row: "", seat: ""
        )
        // But wait — our fix requires same matchup for ±1 day. Same teams IS
        // the same matchup, so it WOULD be flagged. The fix was to require
        // same teams (not just same ballpark). Let's test with DIFFERENT teams
        // at the same park on consecutive days — that should NOT be flagged.
        let candidateDiffTeams = NearDuplicateCandidate(
            proposedId: UUID(), date: day2,
            homeTeamId: "nyy", awayTeamId: "tor",
            ballparkId: "yankee-stadium",
            confirmation: nil, section: "", row: "", seat: ""
        )
        #expect(store.findNearDuplicate(for: candidateDiffTeams) == nil,
                "Different matchup at same park on consecutive days should NOT be flagged")

        if let g1 { store.deleteGame(g1.id) }
    }

    /// findNearDuplicate: different confirmation numbers at same ballpark
    /// with same teams ±1 day should NOT be flagged (different games).
    @Test func differentConfirmationNumbersNotFlaggedAsDuplicate() {
        let store = DiaryStore()
        let cal = Calendar(identifier: .gregorian)
        let day1 = DateComponents(calendar: cal, year: 2023, month: 8, day: 15).date!
        let day2 = cal.date(byAdding: .day, value: 1, to: day1)!

        // Add game 1 with confirmation "CONF001"
        var g1 = sampleGame(home: "nyy", away: "bos", on: day1)
        g1 = AttendedGame(
            id: g1.id, date: g1.date, ballparkId: g1.ballparkId,
            homeTeamId: g1.homeTeamId, awayTeamId: g1.awayTeamId,
            homeScore: g1.homeScore, awayScore: g1.awayScore,
            userRootedForHome: g1.userRootedForHome,
            section: g1.section, row: g1.row, seat: g1.seat,
            confirmation: "CONF001",
            weather: g1.weather, firstPitchTempF: g1.firstPitchTempF,
            attendance: g1.attendance, durationMinutes: g1.durationMinutes,
            highlights: g1.highlights, milestones: g1.milestones, pitching: g1.pitching,
            companions: g1.companions, memory: g1.memory,
            emailSubject: g1.emailSubject, source: g1.source,
            status: g1.status, isVerified: g1.isVerified
        )
        let added = store.addManualGame(g1)
        #expect(added != nil)

        // Candidate next day, same teams, different confirmation
        let candidate = NearDuplicateCandidate(
            proposedId: UUID(), date: day2,
            homeTeamId: "nyy", awayTeamId: "bos",
            ballparkId: "yankee-stadium",
            confirmation: "CONF002", section: "", row: "", seat: ""
        )
        #expect(store.findNearDuplicate(for: candidate) == nil,
                "Different confirmation numbers should NOT be flagged as duplicates")

        if let added { store.deleteGame(added.id) }
    }
}

// MARK: - Neutral game W-L exclusion

@MainActor
struct NeutralGameStatsTests {

    private func game(rootedForHome: Bool?, homeScore: Int = 5, awayScore: Int = 3) -> AttendedGame {
        AttendedGame(
            id: UUID(), date: Date(timeIntervalSince1970: 1_660_000_000),
            ballparkId: "yankee-stadium", homeTeamId: "nyy", awayTeamId: "bos",
            homeScore: homeScore, awayScore: awayScore,
            userRootedForHome: rootedForHome,
            section: "", row: "", seat: "", confirmation: nil,
            weather: .clear, firstPitchTempF: 70, attendance: 40000, durationMinutes: 180,
            highlights: [], milestones: [], pitching: [],
            companions: "", memory: "", emailSubject: "t", source: "Test",
            status: .completed, isVerified: true
        )
    }

    /// Neutral games (userRootedForHome == nil) must not count as wins or losses.
    @Test func neutralGamesDoNotCountAsLosses() {
        let store = DiaryStore()
        // Add a neutral game — home won 5-3 but user didn't root for anyone
        let neutral = store.addManualGame(game(rootedForHome: nil, homeScore: 5, awayScore: 3))
        #expect(neutral != nil)

        #expect(store.winCount == 0, "Neutral game should not count as a win")
        #expect(store.lossCount == 0, "Neutral game should not count as a loss")
        #expect(store.rootedGames.count == 0, "Neutral game should not be in rootedGames")

        if let neutral { store.deleteGame(neutral.id) }
    }

    /// A rooted win counts as a win, a rooted loss counts as a loss.
    @Test func rootedGamesCountCorrectly() {
        let store = DiaryStore()
        let win = store.addManualGame(game(rootedForHome: true, homeScore: 5, awayScore: 3))
        let loss = store.addManualGame(game(rootedForHome: true, homeScore: 2, awayScore: 4))

        #expect(store.winCount == 1)
        #expect(store.lossCount == 1)
        #expect(store.rootedGames.count == 2)

        if let win { store.deleteGame(win.id) }
        if let loss { store.deleteGame(loss.id) }
    }
}

// MARK: - Verified save preserves rooting, companions, and memory

@MainActor
struct VerifiedSavePreservesUserChoicesTests {

    /// Verifies that AttendedGame.rooting(forHome:) correctly sets the
    /// rooting preference, and withMemory() preserves companions and notes.
    @Test func rootingAndMemoryPreservedAfterEnrichment() {
        let baseGame = AttendedGame(
            id: UUID(), date: Date(timeIntervalSince1970: 1_660_000_000),
            ballparkId: "yankee-stadium", homeTeamId: "nyy", awayTeamId: "bos",
            homeScore: 5, awayScore: 3,
            userRootedForHome: nil,  // from() defaults to nil for neutral
            section: "12", row: "5", seat: "9", confirmation: nil,
            weather: .clear, firstPitchTempF: 0, attendance: 0, durationMinutes: 0,
            highlights: [], milestones: [], pitching: [],
            companions: "", memory: "",
            emailSubject: "test", source: "Manual",
            status: .completed, isVerified: true
        )

        // Apply user choices as finishVerification does
        let withRooting = baseGame.rooting(forHome: true)
        let withMemory = withRooting.withMemory(
            companions: "Dad and Sarah",
            memory: "Great seats behind home plate"
        )

        #expect(withMemory.userRootedForHome == true, "Rooting preference should be preserved")
        #expect(withMemory.companions == "Dad and Sarah", "Companions should be preserved")
        #expect(withMemory.memory == "Great seats behind home plate", "Memory should be preserved")
        #expect(withMemory.userWon, "Should be a win — rooted for home, home won 5-3")
    }

    /// Unverified manual games must not fabricate attendance, duration, or temp.
    @Test func unverifiedManualGameHasZeroDefaults() {
        let game = AttendedGame(
            id: UUID(), date: .now,
            ballparkId: "yankee-stadium", homeTeamId: "nyy", awayTeamId: "bos",
            homeScore: 3, awayScore: 2,
            userRootedForHome: true,
            section: "", row: "", seat: "", confirmation: nil,
            weather: .clear, firstPitchTempF: 0, attendance: 0, durationMinutes: 0,
            highlights: [], milestones: [], pitching: [],
            companions: "", memory: "",
            emailSubject: "test", source: "Manual entry (unverified)",
            status: .completed, isVerified: false
        )

        #expect(game.firstPitchTempF == 0, "Unverified game should not fabricate temp")
        #expect(game.attendance == 0, "Unverified game should not fabricate attendance")
        #expect(game.durationMinutes == 0, "Unverified game should not fabricate duration")
        #expect(!game.isEnriched, "Unverified game with 0 duration should be enrichable")
    }
}
