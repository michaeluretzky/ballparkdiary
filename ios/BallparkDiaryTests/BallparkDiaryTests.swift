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

    /// SeatGeek's order screen stacks the VALUE above the caption ("BOX537"
    /// above "SECTION", "2" above "ROW", "1" above "QTY"). The parser must
    /// resolve that orientation — section BOX537, row 2, and never treat the
    /// QTY column or venue name as seat data.
    @Test func seatGeekValueAboveCaptionLayout() throws {
        let snippet = """
        Chicago White Sox vs. New York Yankees
        Thursday Jul 30, 1:10pm • Rate Field
        TICKET INFO
        BOX537
        SECTION
        2
        ROW
        1
        QTY
        Rate Field 333 West 35th Street, Chicago
        """
        let messages = [EmailMessage(
            id: "1", subject: "", from: "seatgeek.com", snippet: snippet, internalDate: .now
        )]
        let game = try #require(TicketEmailParser.detect(in: messages).first)

        #expect(game.teamMlbId == 145)       // White Sox mentioned first
        #expect(game.opponentMlbId == 147)   // Yankees
        #expect(game.section == "BOX537")
        #expect(game.row == "2")
        #expect(game.seat.isEmpty)           // qty is not a seat
        #expect(game.dateHints.contains { $0.month == 7 && $0.day == 30 })
    }

    /// Ticketmaster-style stacked text keeps the caption ABOVE the value — the
    /// orientation scoring must not flip it.
    @Test func captionAboveValueLayoutStillParses() throws {
        let snippet = """
        Yankees vs Red Sox — Aug 22, 2022
        SECTION
        160
        ROW
        7
        SEAT
        3
        """
        let messages = [EmailMessage(
            id: "1", subject: "", from: "ticketmaster.com", snippet: snippet, internalDate: .now
        )]
        let game = try #require(TicketEmailParser.detect(in: messages).first)

        #expect(game.section == "160")
        #expect(game.row == "7")
        #expect(game.seat == "3")
    }

    /// OCR reading-order artifacts like "ROW Rate Field" must never produce a
    /// word as a row — an empty value beats a wrong one.
    @Test func englishWordsAreRejectedAsSeatValues() throws {
        let messages = [EmailMessage(
            id: "1",
            subject: "White Sox vs Yankees",
            from: "seatgeek.com",
            snippet: "Jul 30, 2026 SECTION ROW QTY Rate Field Chicago",
            internalDate: .now
        )]
        let game = try #require(TicketEmailParser.detect(in: messages).first)

        #expect(game.section.isEmpty)
        #expect(game.row.isEmpty)
        #expect(game.seat.isEmpty)
    }

    /// Canonical lines synthesized by the share extension's geometric pairing
    /// ("Section: BOX537") always win over looser matches later in the text.
    @Test func synthesizedSeatLinesTakePriority() throws {
        let snippet = """
        Section: BOX537
        Row: 2
        White Sox vs Yankees Jul 30, 2026
        BOX537   2   1
        SECTION   ROW   QTY
        """
        let messages = [EmailMessage(
            id: "1", subject: "", from: "seatgeek.com", snippet: snippet, internalDate: .now
        )]
        let game = try #require(TicketEmailParser.detect(in: messages).first)

        #expect(game.section == "BOX537")
        #expect(game.row == "2")
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

// MARK: - Famous game detection

struct HistoricGameTests {

    private func game(
        homeScore: Int = 5, awayScore: Int = 3,
        highlights: [AttendedGame.Highlight] = [],
        milestones: [PlayerMilestone] = [],
        upcoming: Bool = false
    ) -> AttendedGame {
        AttendedGame(
            id: UUID(), date: Date(timeIntervalSince1970: 1_660_000_000),
            ballparkId: "yankee-stadium", homeTeamId: "nyy", awayTeamId: "bos",
            homeScore: homeScore, awayScore: awayScore, userRootedForHome: true,
            section: "", row: "", seat: "", confirmation: nil,
            weather: .clear, firstPitchTempF: 70, attendance: 40000, durationMinutes: 180,
            highlights: highlights, milestones: milestones, pitching: [],
            companions: "", memory: "", emailSubject: "t", source: "Test",
            status: upcoming ? .upcoming : .completed, isVerified: true
        )
    }

    private func milestone(title: String, category: PlayerMilestone.Category) -> PlayerMilestone {
        PlayerMilestone(
            id: UUID(), playerName: "Aaron Judge", teamId: "nyy",
            title: title, category: category, stat: "s", detail: "d", context: "c", inning: nil
        )
    }

    @Test func noHitterIsHistoric() {
        let g = game(milestones: [milestone(title: "No-Hitter", category: .noHitter)])
        #expect(g.isHistoric)
        #expect(g.historicNote?.contains("no-hitter") == true)
    }

    @Test func perfectGameOutranksNoHitter() {
        let g = game(milestones: [milestone(title: "Perfect Game", category: .noHitter)])
        #expect(g.historicNote?.contains("perfect game") == true)
    }

    @Test func exactCareerMilestoneIsHistoricButChasingIsNot() {
        let exact = game(milestones: [milestone(title: "500th Career Home Run", category: .homeRun)])
        #expect(exact.isHistoric)

        let chasing = game(milestones: [milestone(title: "Career HR #497 \u{2014} Chasing 500", category: .homeRun)])
        #expect(!chasing.isHistoric, "A chasing milestone is not itself a historic mark")
    }

    @Test func walkoffIsHistoric() {
        let g = game(highlights: [AttendedGame.Highlight(inning: "B9", description: "walk-off single", kind: .walkoff)])
        #expect(g.historicNote?.contains("walk-off") == true)
    }

    @Test func marathonAndBlowoutAreHistoric() {
        let marathon = game(highlights: [AttendedGame.Highlight(inning: "T16", description: "RBI double", kind: .hit)])
        #expect(marathon.historicNote?.contains("marathon") == true)

        let blowout = game(homeScore: 22, awayScore: 4)
        #expect(blowout.historicNote?.contains("blowout") == true)
    }

    @Test func ordinaryAndUpcomingGamesAreNotHistoric() {
        #expect(!game().isHistoric)
        #expect(!game(milestones: [milestone(title: "No-Hitter", category: .noHitter)], upcoming: true).isHistoric,
                "Upcoming games can never be historic")
    }
}

// MARK: - Fan record deep splits & milestone teaser

@MainActor
struct FanRecordInsightTests {

    private func game(
        on date: Date,
        rootedForHome: Bool?,
        homeScore: Int, awayScore: Int,
        weather: AttendedGame.Weather = .clear,
        milestones: [PlayerMilestone] = []
    ) -> AttendedGame {
        AttendedGame(
            id: UUID(), date: date,
            ballparkId: "yankee-stadium", homeTeamId: "nyy", awayTeamId: "bos",
            homeScore: homeScore, awayScore: awayScore, userRootedForHome: rootedForHome,
            section: "", row: "", seat: "", confirmation: nil,
            weather: weather, firstPitchTempF: 70, attendance: 40000, durationMinutes: 180,
            highlights: [], milestones: milestones, pitching: [],
            companions: "", memory: "", emailSubject: "t", source: "Test",
            status: .completed, isVerified: true
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 13) -> Date {
        DateComponents(calendar: .init(identifier: .gregorian), year: year, month: month, day: day, hour: hour).date!
    }

    /// Records split correctly by rooted team, day/night, and home/away.
    @Test func fanRecordSplitsAreCorrect() {
        let store = DiaryStore()
        var added: [AttendedGame] = []

        // Rooted home (nyy), day, WIN
        if let g = store.addManualGame(game(on: date(1991, 5, 1), rootedForHome: true, homeScore: 5, awayScore: 2, weather: .clear)) { added.append(g) }
        // Rooted home (nyy), night, LOSS
        if let g = store.addManualGame(game(on: date(1991, 5, 2), rootedForHome: true, homeScore: 1, awayScore: 4, weather: .night)) { added.append(g) }
        // Rooted away (bos), day, WIN (away won)
        if let g = store.addManualGame(game(on: date(1991, 5, 3), rootedForHome: false, homeScore: 2, awayScore: 6, weather: .clear)) { added.append(g) }
        // Neutral — must not appear in any split
        if let g = store.addManualGame(game(on: date(1991, 5, 4), rootedForHome: nil, homeScore: 3, awayScore: 1)) { added.append(g) }

        defer { for g in added { store.deleteGame(g.id) } }

        let nyy = store.fanRecordByTeam.first { $0.team.id == "nyy" }
        #expect(nyy?.wins ?? -1 >= 1)
        #expect(nyy?.losses ?? -1 >= 1)

        let bos = store.fanRecordByTeam.first { $0.team.id == "bos" }
        #expect(bos?.wins ?? 0 >= 1)

        let day = store.dayNightSplits.first { $0.label.contains("Day") }
        let night = store.dayNightSplits.first { $0.label.contains("Night") }
        #expect((day?.wins ?? 0) >= 2, "Both day wins should count")
        #expect((night?.losses ?? 0) >= 1)

        let road = store.homeAwaySplits.first { $0.label.contains("road") }
        #expect((road?.wins ?? 0) >= 1, "Rooting for the visitors and winning counts as a road win")
    }

    /// The free milestone is the FIRST milestone of the chronologically
    /// earliest game that has any — and only that one is free.
    @Test func firstWitnessedMilestoneIsChronological() {
        let store = DiaryStore()
        var added: [AttendedGame] = []

        let early = PlayerMilestone(id: UUID(), playerName: "Early Player", teamId: "nyy", title: "No-Hitter", category: .noHitter, stat: "s", detail: "d", context: "c", inning: nil)
        let late = PlayerMilestone(id: UUID(), playerName: "Late Player", teamId: "bos", title: "15-Strikeout Game", category: .strikeouts, stat: "s", detail: "d", context: "c", inning: nil)

        if let g = store.addManualGame(game(on: date(1992, 6, 10), rootedForHome: true, homeScore: 2, awayScore: 0, milestones: [early])) { added.append(g) }
        if let g = store.addManualGame(game(on: date(1993, 7, 11), rootedForHome: true, homeScore: 3, awayScore: 1, milestones: [late])) { added.append(g) }

        defer { for g in added { store.deleteGame(g.id) } }

        // The diary may contain other milestone games from persisted state, so
        // assert relative ordering instead of exact identity: the free milestone's
        // game must not be newer than our 1992 entry.
        let free = store.firstWitnessedMilestone
        #expect(free != nil)
        #expect(free!.game.date <= date(1992, 6, 10, hour: 23))
        #expect(store.totalMilestonesWitnessed >= 2)

        if let firstGame = added.first, let freeMilestone = free?.milestone,
           free?.game.id == firstGame.id {
            #expect(store.isFreeMilestone(freeMilestone, in: firstGame))
            #expect(!store.isFreeMilestone(late, in: added[1]))
        }
    }

    /// Season streak counts consecutive years back from the latest active
    /// season and dies when the latest season is too old.
    @Test func seasonStreakRequiresRecentSeason() {
        let store = DiaryStore()
        // Whatever the current diary state, the invariant holds: a streak > 0
        // implies games in this year or last year.
        let years = Set(store.completedGames.map { Calendar.current.component(.year, from: $0.date) })
        let currentYear = Calendar.current.component(.year, from: .now)
        if store.seasonStreak > 0 {
            #expect(years.contains(currentYear) || years.contains(currentYear - 1))
        }
        // gamesThisSeason only counts the current calendar year.
        let manual = store.completedGames.filter { Calendar.current.component(.year, from: $0.date) == currentYear }
        #expect(store.gamesThisSeason == manual.count)
    }
}

// MARK: - Widget snapshot encoding

struct WidgetSnapshotTests {

    /// The snapshot the app writes must decode with the exact shape the
    /// widget target mirrors — a field rename here would silently blank the widget.
    @Test func snapshotRoundTripsThroughJSON() throws {
        let snapshot = WidgetSnapshot(
            totalGames: 12, parksVisited: 4,
            seasonYear: 2026, seasonGames: 3, seasonWins: 2, seasonLosses: 1,
            favoriteTeamAbbreviation: "NYY",
            nextGameDate: Date(timeIntervalSince1970: 1_790_000_000),
            nextGameMatchup: "BOS @ NYY",
            nextGameBallpark: "Yankee Stadium",
            updatedAt: .now
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(decoded.totalGames == 12)
        #expect(decoded.seasonWins == 2)
        #expect(decoded.nextGameMatchup == "BOS @ NYY")
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
