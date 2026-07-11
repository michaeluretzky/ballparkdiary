import Foundation

/// Simulator-only demo diary used for App Store screenshot capture.
///
/// When the app launches on a **simulator** with an empty diary, a realistic
/// sample diary is loaded so marketing screenshots show real usage instead of
/// empty states. This code path is compiled out of device builds entirely —
/// real users can never see it.
extension DiaryStore {
    /// Seeds an in-memory demo diary on simulator when the diary is empty.
    /// No-op on physical devices and whenever the user already has games.
    func seedDemoDiaryIfNeeded() {
        #if targetEnvironment(simulator)
        guard games.isEmpty, connectedInboxes.isEmpty else { return }

        let sharedInboxId = UUID()
        let manualInboxId = UUID()

        let sharedGames = DiaryStore.demoSharedGames
        let manualGames = DiaryStore.demoManualGames

        gamesByInbox[sharedInboxId] = sharedGames
        gamesByInbox[manualInboxId] = manualGames
        connectedInboxes = [
            ConnectedInbox(
                id: sharedInboxId,
                email: "Shared tickets",
                provider: .shared,
                ticketsFound: sharedGames.count,
                connectedAt: DiaryStore.demoDate(2025, 4, 12)
            ),
            ConnectedInbox(
                id: manualInboxId,
                email: "Manual entries",
                provider: .manual,
                ticketsFound: manualGames.count,
                connectedAt: DiaryStore.demoDate(2025, 4, 12)
            ),
        ]
        #endif
    }
}

#if targetEnvironment(simulator)
private extension DiaryStore {
    static func demoDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 19) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 5
        return Calendar.current.date(from: components) ?? Date()
    }

    static func demoGame(
        date: Date,
        ballparkId: String,
        home: Team,
        away: Team,
        homeScore: Int,
        awayScore: Int,
        rootedForHome: Bool?,
        section: String,
        row: String,
        seat: String,
        confirmation: String?,
        weather: AttendedGame.Weather,
        tempF: Int,
        attendance: Int,
        duration: Int,
        highlights: [AttendedGame.Highlight],
        milestones: [PlayerMilestone] = [],
        companions: String = "",
        memory: String = "",
        source: String,
        status: AttendedGame.Status = .completed
    ) -> AttendedGame {
        AttendedGame(
            id: UUID(),
            date: date,
            ballparkId: ballparkId,
            homeTeamId: home.id,
            awayTeamId: away.id,
            homeScore: homeScore,
            awayScore: awayScore,
            userRootedForHome: rootedForHome,
            section: section, row: row, seat: seat,
            confirmation: confirmation,
            weather: weather,
            firstPitchTempF: tempF,
            attendance: attendance,
            durationMinutes: duration,
            highlights: highlights,
            milestones: milestones,
            pitching: [],
            companions: companions,
            memory: memory,
            emailSubject: "Your \(away.name) at \(home.name) tickets",
            source: source,
            status: status,
            isVerified: true
        )
    }

    /// Games imported from shared tickets — rich, verified entries.
    static var demoSharedGames: [AttendedGame] {
        [
            // Upcoming ticket — shows the "vs" state on the diary.
            demoGame(
                date: demoDate(2026, 7, 24, hour: 19),
                ballparkId: "yankee-stadium",
                home: .yankees, away: .redSox,
                homeScore: 0, awayScore: 0,
                rootedForHome: true,
                section: "420A", row: "3", seat: "11",
                confirmation: "QK4T7M",
                weather: .night, tempF: 0, attendance: 0, duration: 0,
                highlights: [],
                source: "StubHub",
                status: .upcoming
            ),
            demoGame(
                date: demoDate(2026, 6, 27),
                ballparkId: "yankee-stadium",
                home: .yankees, away: .redSox,
                homeScore: 7, awayScore: 4,
                rootedForHome: true,
                section: "214", row: "8", seat: "5",
                confirmation: "8H7XK2",
                weather: .night, tempF: 78, attendance: 46_208, duration: 188,
                highlights: [
                    .init(inning: "B3", description: "Judge two-run homer to deep right-center (434 ft)", kind: .homeRun),
                    .init(inning: "B6", description: "Volpe RBI double off the wall in left", kind: .hit),
                ],
                companions: "Dad",
                memory: "First game of the summer. Judge crushed one right at us in 214 — Dad still has the video.",
                source: "Ticketmaster"
            ),
            demoGame(
                date: demoDate(2026, 6, 14, hour: 13),
                ballparkId: "citi-field",
                home: .mets, away: .yankees,
                homeScore: 3, awayScore: 5,
                rootedForHome: false,
                section: "126", row: "14", seat: "9",
                confirmation: "M3PZ81",
                weather: .clear, tempF: 84, attendance: 41_312, duration: 172,
                highlights: [
                    .init(inning: "T7", description: "Stanton solo shot into the second deck", kind: .homeRun),
                ],
                companions: "Sarah",
                memory: "Subway Series in the sun. Bragging rights for a year.",
                source: "SeatGeek"
            ),
            demoGame(
                date: demoDate(2026, 5, 30),
                ballparkId: "fenway-park",
                home: .redSox, away: .yankees,
                homeScore: 6, awayScore: 2,
                rootedForHome: false,
                section: "GS 32", row: "7", seat: "18",
                confirmation: "FNW552",
                weather: .partlyCloudy, tempF: 66, attendance: 36_419, duration: 181,
                highlights: [
                    .init(inning: "B4", description: "Devers three-run homer over the Monster", kind: .homeRun),
                ],
                memory: "The Monster seats were worth every penny, even in a loss.",
                source: "StubHub"
            ),
            demoGame(
                date: demoDate(2026, 5, 9),
                ballparkId: "camden-yards",
                home: .orioles, away: .yankees,
                homeScore: 4, awayScore: 9,
                rootedForHome: false,
                section: "36", row: "12", seat: "3",
                confirmation: "CY19R8",
                weather: .night, tempF: 71, attendance: 33_876, duration: 196,
                highlights: [
                    .init(inning: "T5", description: "Soto grand slam to right field", kind: .homeRun),
                    .init(inning: "T8", description: "Rice back-to-back blast to center", kind: .homeRun),
                ],
                source: "MLB Ballpark"
            ),
            demoGame(
                date: demoDate(2026, 4, 18, hour: 13),
                ballparkId: "yankee-stadium",
                home: .yankees, away: .rays,
                homeScore: 3, awayScore: 1,
                rootedForHome: true,
                section: "205", row: "2", seat: "14",
                confirmation: "YS8842",
                weather: .clear, tempF: 61, attendance: 42_105, duration: 165,
                highlights: [
                    .init(inning: "P", description: "Cole: 7.0 IP, 4 H, 1 R, 11 K on 98 pitches", kind: .pitching),
                ],
                milestones: [
                    PlayerMilestone(
                        id: UUID(),
                        playerName: "Gerrit Cole",
                        teamId: "nyy",
                        title: "2000th Career Strikeout",
                        category: .strikeouts,
                        stat: "K #2000",
                        detail: "Cole froze the side in the 6th to reach 2,000 career strikeouts.",
                        context: "You were there for Gerrit Cole's 2,000th career strikeout — a club fewer than 90 pitchers have ever joined.",
                        inning: "T6"
                    ),
                ],
                companions: "Mike",
                memory: "Cole was untouchable. The whole stadium stood for K #2000.",
                source: "Ticketmaster"
            ),
            demoGame(
                date: demoDate(2025, 9, 21, hour: 13),
                ballparkId: "wrigley-field",
                home: .cubs, away: .cardinals,
                homeScore: 8, awayScore: 6,
                rootedForHome: nil,
                section: "224", row: "6", seat: "101",
                confirmation: "WRG774",
                weather: .clear, tempF: 72, attendance: 39_882, duration: 202,
                highlights: [
                    .init(inning: "B2", description: "Happ opposite-field homer onto Sheffield", kind: .homeRun),
                    .init(inning: "T6", description: "Goldschmidt two-run shot to left", kind: .homeRun),
                ],
                companions: "College crew",
                memory: "Wrigley in September with the ivy turning. Slugfest, sunburn, no regrets.",
                source: "Gametime"
            ),
            demoGame(
                date: demoDate(2025, 8, 16),
                ballparkId: "dodger-stadium",
                home: .dodgers, away: .padres,
                homeScore: 3, awayScore: 2,
                rootedForHome: nil,
                section: "6FD", row: "C", seat: "8",
                confirmation: "LAD316",
                weather: .night, tempF: 79, attendance: 52_240, duration: 158,
                highlights: [
                    .init(inning: "B8", description: "Ohtani go-ahead solo homer to right", kind: .homeRun),
                ],
                memory: "Sunset over the outfield pavilion, then Ohtani ended it. Perfect night.",
                source: "SeatGeek"
            ),
            demoGame(
                date: demoDate(2025, 8, 14),
                ballparkId: "oracle-park",
                home: .giants, away: .padres,
                homeScore: 5, awayScore: 4,
                rootedForHome: nil,
                section: "VB 331", row: "9", seat: "2",
                confirmation: "SFG909",
                weather: .partlyCloudy, tempF: 62, attendance: 38_114, duration: 190,
                highlights: [
                    .init(inning: "B9", description: "Walk-off single splashes off the right-field wall", kind: .walkoff),
                ],
                memory: "Kayaks in McCovey Cove and a walk-off. California trip peaked here.",
                source: "StubHub"
            ),
            demoGame(
                date: demoDate(2025, 7, 4, hour: 13),
                ballparkId: "yankee-stadium",
                home: .yankees, away: .astros,
                homeScore: 6, awayScore: 5,
                rootedForHome: true,
                section: "233", row: "11", seat: "7",
                confirmation: "JUL4TH",
                weather: .clear, tempF: 88, attendance: 47_309, duration: 214,
                highlights: [
                    .init(inning: "B9", description: "Judge walk-off blast to left-center — fireworks after", kind: .walkoff),
                    .init(inning: "T4", description: "Altuve solo homer to left", kind: .homeRun),
                ],
                companions: "Dad, Uncle Joe",
                memory: "Fourth of July walk-off. Loudest I've ever heard the Stadium.",
                source: "Ticketmaster"
            ),
            demoGame(
                date: demoDate(2025, 6, 8, hour: 13),
                ballparkId: "pnc-park",
                home: .pirates, away: .yankees,
                homeScore: 7, awayScore: 3,
                rootedForHome: false,
                section: "144", row: "E", seat: "12",
                confirmation: "PNC183",
                weather: .clear, tempF: 75, attendance: 30_556, duration: 169,
                highlights: [
                    .init(inning: "B1", description: "Cruz 452-ft homer into the Allegheny", kind: .homeRun),
                ],
                memory: "Best view in baseball is real. Worth the road trip even in a loss.",
                source: "Vivid Seats"
            ),
        ]
    }

    /// Games the user typed in by hand — older memories with fewer details.
    static var demoManualGames: [AttendedGame] {
        [
            demoGame(
                date: demoDate(2025, 4, 12, hour: 13),
                ballparkId: "truist-park",
                home: .braves, away: .phillies,
                homeScore: 2, awayScore: 1,
                rootedForHome: nil,
                section: "115", row: "20", seat: "6",
                confirmation: nil,
                weather: .clear, tempF: 68, attendance: 40_133, duration: 151,
                highlights: [
                    .init(inning: "P", description: "Pitchers' duel — 19 combined strikeouts", kind: .pitching),
                ],
                memory: "Work trip detour. The Battery before the game was a blast.",
                source: "Added by hand"
            ),
            demoGame(
                date: demoDate(2024, 8, 10, hour: 13),
                ballparkId: "yankee-stadium",
                home: .yankees, away: .tigers,
                homeScore: 10, awayScore: 3,
                rootedForHome: true,
                section: "107", row: "4", seat: "1",
                confirmation: nil,
                weather: .clear, tempF: 86, attendance: 44_871, duration: 177,
                highlights: [
                    .init(inning: "B5", description: "Three homers in one inning — Judge, Wells, Chisholm", kind: .homeRun),
                ],
                companions: "Dad",
                memory: "The game that started this diary. Kept the paper stub in my wallet for a year.",
                source: "Added by hand"
            ),
        ]
    }
}
#endif
