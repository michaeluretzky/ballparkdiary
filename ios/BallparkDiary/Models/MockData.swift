import Foundation

/// Mock-but-realistic data used by the inbox-scan flow. Each provider returns
/// a disjoint slice of attended games so that connecting additional inboxes
/// visibly grows the user's combined totals.
///
/// In a future version this would be replaced by a real Gmail/iCloud/Outlook
/// parser pulling matching purchase confirmations, with milestones backfilled
/// from the public MLB Stats API (statsapi.mlb.com).
enum MockData {

    // MARK: - Provider dispatch

    static func games(for provider: InboxProvider) -> [AttendedGame] {
        switch provider {
        case .gmail: return gmailGames
        case .icloud: return icloudGames
        case .outlook: return outlookGames
        case .yahoo: return yahooGames
        case .other: return otherGames
        case .forwarding, .manual: return []
        }
    }

    static func subjects(for provider: InboxProvider) -> [String] {
        switch provider {
        case .gmail: return gmailSubjects
        case .icloud: return icloudSubjects
        case .outlook: return outlookSubjects
        case .yahoo: return yahooSubjects
        case .other: return otherSubjects
        case .forwarding, .manual: return []
        }
    }

    // MARK: - Scan subjects (streamed during animation)

    static let gmailSubjects: [String] = [
        "Your StubHub order is confirmed — Yankees vs Red Sox",
        "MLB Ballpark App: Mobile tickets available",
        "Ticketmaster: Cubs vs Cardinals @ Wrigley Field",
        "Your SeatGeek tickets — Dodgers vs Giants",
        "Confirmation #88412: Phillies vs Mets at Citi Field",
        "Your trip to PNC Park is coming up"
    ]

    static let icloudSubjects: [String] = [
        "Your SeatGeek tickets — Giants vs Dodgers",
        "[Receipt] Yankees vs Orioles — Section 220B",
        "Resale confirmed: Yankees vs Blue Jays"
    ]

    static let outlookSubjects: [String] = [
        "StubHub: Astros vs Mariners — print at home",
        "Ticket transfer received — Braves vs Mets",
        "Your tickets — Rockies vs Phillies"
    ]

    static let yahooSubjects: [String] = [
        "Vivid Seats: Padres vs Dodgers — Petco Park",
        "Gametime tickets — Rays vs Yankees",
        "AXS confirmation — Mariners vs Astros"
    ]

    static let otherSubjects: [String] = [
        "TickPick: Order confirmed — Brewers vs Cubs",
        "Your Tickets.com order — Reds vs Pirates",
        "Fevo group buy — Nationals vs Marlins"
    ]

    // MARK: - Game data per provider

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 19) -> Date {
        let cal = Calendar(identifier: .gregorian)
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: 5)) ?? Date()
    }

    /// Gmail — primary inbox, Yankees-heavy fan.
    static var gmailGames: [AttendedGame] {
        [
            AttendedGame(
                id: UUID(),
                date: date(2025, 9, 14, 13),
                ballparkId: "yankee-stadium",
                homeTeamId: Team.yankees.id, awayTeamId: Team.redSox.id,
                homeScore: 7, awayScore: 4,
                userRootedForHome: true,
                section: "227B", row: "4", seat: "12",
                weather: .clear, firstPitchTempF: 74, attendance: 46_213, durationMinutes: 198,
                highlights: [
                    .init(inning: "B3", description: "Aaron Judge 2-run HR to deep center (438 ft)", kind: .homeRun),
                    .init(inning: "B6", description: "Soto solo shot, right field porch", kind: .homeRun),
                    .init(inning: "T8", description: "Bullpen escape with bases loaded", kind: .pitching)
                ],
                milestones: [
                    PlayerMilestone(
                        id: UUID(),
                        playerName: "Aaron Judge",
                        teamId: Team.yankees.id,
                        title: "300th Career Home Run",
                        category: .homeRun,
                        stat: "HR #300",
                        detail: "Judge's 438-ft drive to dead center in the bottom of the 3rd became the 300th home run of his MLB career — reached in fewer games than any right-handed hitter in history.",
                        context: "Joins an exclusive club of fewer than 160 players to reach 300 career home runs. Among active right-handed hitters, only Mike Trout and Nolan Arenado were within range.",
                        inning: "B3"
                    )
                ],
                emailSubject: "[Receipt] Yankees vs Red Sox — Section 227B",
                source: "StubHub"
            ),
            AttendedGame(
                id: UUID(),
                date: date(2025, 8, 2, 19),
                ballparkId: "fenway-park",
                homeTeamId: Team.redSox.id, awayTeamId: Team.yankees.id,
                homeScore: 3, awayScore: 8,
                userRootedForHome: false,
                section: "Loge 132", row: "8", seat: "5",
                weather: .night, firstPitchTempF: 71, attendance: 37_412, durationMinutes: 211,
                highlights: [
                    .init(inning: "T1", description: "Soto leadoff double off the Monster", kind: .hit),
                    .init(inning: "T7", description: "Judge grand slam, light tower power", kind: .homeRun)
                ],
                milestones: [
                    PlayerMilestone(
                        id: UUID(),
                        playerName: "Aaron Judge",
                        teamId: Team.yankees.id,
                        title: "First career grand slam at Fenway",
                        category: .homeRun,
                        stat: "GS #4",
                        detail: "Judge's 7th-inning grand slam over the Green Monster's light tower was his first career slam at Fenway Park and his 4th overall.",
                        context: "Only the 7th visiting player to hit a grand slam over the Monster's light tower since the towers were installed in 1947.",
                        inning: "T7"
                    )
                ],
                emailSubject: "Boston Red Sox tickets — Fenway Park",
                source: "Red Sox Mobile"
            ),
            AttendedGame(
                id: UUID(),
                date: date(2025, 7, 11, 13),
                ballparkId: "wrigley-field",
                homeTeamId: Team.cubs.id, awayTeamId: Team.cardinals.id,
                homeScore: 5, awayScore: 6,
                userRootedForHome: true,
                section: "Bleachers RF", row: "—", seat: "GA",
                weather: .partlyCloudy, firstPitchTempF: 82, attendance: 39_004, durationMinutes: 188,
                highlights: [
                    .init(inning: "B5", description: "Suzuki HR onto Sheffield", kind: .homeRun),
                    .init(inning: "T9", description: "Arenado go-ahead double to the gap", kind: .hit)
                ],
                milestones: [
                    PlayerMilestone(
                        id: UUID(),
                        playerName: "Nolan Arenado",
                        teamId: Team.cardinals.id,
                        title: "1,500th Career Hit",
                        category: .hits,
                        stat: "H #1,500",
                        detail: "Arenado's go-ahead double in the top of the 9th was the 1,500th hit of his big-league career.",
                        context: "Reached the mark in his 13th MLB season — the 23rd active player to hit the milestone.",
                        inning: "T9"
                    )
                ],
                emailSubject: "Ticketmaster: Cubs vs Cardinals @ Wrigley Field",
                source: "Ticketmaster"
            ),
            AttendedGame(
                id: UUID(),
                date: date(2025, 6, 21, 19),
                ballparkId: "citi-field",
                homeTeamId: Team.mets.id, awayTeamId: Team.phillies.id,
                homeScore: 4, awayScore: 2,
                userRootedForHome: true,
                section: "514", row: "12", seat: "9",
                weather: .clear, firstPitchTempF: 78, attendance: 41_002, durationMinutes: 174,
                highlights: [
                    .init(inning: "B8", description: "Alonso 2-run HR — Home Run Apple rises", kind: .homeRun),
                    .init(inning: "T9", description: "Díaz 1-2-3 with the trumpets", kind: .pitching)
                ],
                milestones: [
                    PlayerMilestone(
                        id: UUID(),
                        playerName: "Pete Alonso",
                        teamId: Team.mets.id,
                        title: "225th Career Home Run",
                        category: .homeRun,
                        stat: "HR #225",
                        detail: "Alonso's 8th-inning blast made him the fastest Met ever to reach 225 home runs, passing Darryl Strawberry on the franchise all-time list.",
                        context: "Now sits 2nd on the Mets' career home run list, trailing only Darryl Strawberry's 252.",
                        inning: "B8"
                    ),
                    PlayerMilestone(
                        id: UUID(),
                        playerName: "Edwin Díaz",
                        teamId: Team.mets.id,
                        title: "200th Career Save",
                        category: .milestone,
                        stat: "SV #200",
                        detail: "Díaz's 1-2-3 9th locked down his 200th career save, the 4th-fastest closer to reach the mark.",
                        context: "Joins Francisco Rodríguez and Armando Benítez as the only Mets relievers to record 200 saves with the franchise.",
                        inning: "T9"
                    )
                ],
                emailSubject: "Confirmation #88412: Phillies vs Mets at Citi Field",
                source: "MLB Ballpark"
            ),
            AttendedGame(
                id: UUID(),
                date: date(2025, 5, 30, 19),
                ballparkId: "pnc-park",
                homeTeamId: Team.pirates.id, awayTeamId: Team.brewers.id,
                homeScore: 2, awayScore: 1,
                userRootedForHome: true,
                section: "115", row: "C", seat: "14",
                weather: .partlyCloudy, firstPitchTempF: 69, attendance: 31_244, durationMinutes: 162,
                highlights: [
                    .init(inning: "B9", description: "Reynolds walk-off single up the middle", kind: .walkoff),
                    .init(inning: "T6", description: "Skenes 11 strikeouts in 7 IP", kind: .pitching)
                ],
                milestones: [
                    PlayerMilestone(
                        id: UUID(),
                        playerName: "Paul Skenes",
                        teamId: Team.pirates.id,
                        title: "200th Career Strikeout",
                        category: .strikeouts,
                        stat: "K #200",
                        detail: "Skenes whiffed 11 over 7 IP, with his 4th-inning punch-out of Yelich serving as the 200th K of his young career.",
                        context: "Reached 200 career strikeouts in only 31 starts — the fewest by any starter in the live-ball era.",
                        inning: "T4"
                    )
                ],
                emailSubject: "Your trip to PNC Park is coming up",
                source: "SeatGeek"
            ),
            AttendedGame(
                id: UUID(),
                date: date(2024, 8, 18, 16),
                ballparkId: "dodger-stadium",
                homeTeamId: Team.dodgers.id, awayTeamId: Team.padres.id,
                homeScore: 5, awayScore: 9,
                userRootedForHome: false,
                section: "Reserve 23RS", row: "M", seat: "1",
                weather: .clear, firstPitchTempF: 88, attendance: 52_104, durationMinutes: 205,
                highlights: [
                    .init(inning: "T4", description: "Tatis Jr. 3-run HR to left", kind: .homeRun),
                    .init(inning: "B7", description: "Betts solo HR", kind: .homeRun)
                ],
                milestones: [
                    PlayerMilestone(
                        id: UUID(),
                        playerName: "Fernando Tatís Jr.",
                        teamId: Team.padres.id,
                        title: "150th Career Home Run",
                        category: .homeRun,
                        stat: "HR #150",
                        detail: "Tatís Jr.'s 3-run shot to left in the 4th was the 150th home run of his career, reached at age 25.",
                        context: "One of only 6 players in MLB history to record 150 home runs before turning 26.",
                        inning: "T4"
                    )
                ],
                emailSubject: "MLB.com: Your tickets for Padres vs Dodgers",
                source: "MLB.com"
            )
        ]
    }

    /// iCloud Mail — work-and-personal hybrid; mostly West Coast trips & extra Yankees games.
    static var icloudGames: [AttendedGame] {
        [
            AttendedGame(
                id: UUID(),
                date: date(2024, 7, 7, 13),
                ballparkId: "oracle-park",
                homeTeamId: Team.giants.id, awayTeamId: Team.dodgers.id,
                homeScore: 3, awayScore: 2,
                userRootedForHome: true,
                section: "VR 137", row: "9", seat: "20",
                weather: .partlyCloudy, firstPitchTempF: 64, attendance: 41_212, durationMinutes: 184,
                highlights: [
                    .init(inning: "B7", description: "Chapman splash hit into McCovey Cove", kind: .homeRun),
                    .init(inning: "T9", description: "Doval slams the door — 3 K's", kind: .pitching)
                ],
                milestones: [
                    PlayerMilestone(
                        id: UUID(),
                        playerName: "Matt Chapman",
                        teamId: Team.giants.id,
                        title: "Splash Hit #102",
                        category: .homeRun,
                        stat: "Cove #102",
                        detail: "Chapman's 7th-inning blast cleared the right-field wall and dropped into McCovey Cove — the 102nd splash hit in Oracle Park history.",
                        context: "Splash hits are tracked on the iconic right-field scoreboard. Barry Bonds owns the all-time record with 35.",
                        inning: "B7"
                    )
                ],
                emailSubject: "Your SeatGeek tickets — Giants vs Dodgers",
                source: "SeatGeek"
            ),
            AttendedGame(
                id: UUID(),
                date: date(2024, 5, 12, 19),
                ballparkId: "yankee-stadium",
                homeTeamId: Team.yankees.id, awayTeamId: Team.orioles.id,
                homeScore: 6, awayScore: 5,
                userRootedForHome: true,
                section: "220B", row: "9", seat: "7",
                weather: .clear, firstPitchTempF: 66, attendance: 44_812, durationMinutes: 218,
                highlights: [
                    .init(inning: "B10", description: "Volpe walk-off single to right", kind: .walkoff),
                    .init(inning: "T8", description: "Rutschman ties it with a 2-run double", kind: .hit)
                ],
                milestones: [
                    PlayerMilestone(
                        id: UUID(),
                        playerName: "Anthony Volpe",
                        teamId: Team.yankees.id,
                        title: "First Career Walk-Off Hit",
                        category: .hits,
                        stat: "Walk-off #1",
                        detail: "Volpe's 10th-inning single to right scored the winning run from second, the first walk-off hit of his MLB career.",
                        context: "At 23, Volpe became the youngest Yankees shortstop to record a walk-off hit since Derek Jeter in 1997.",
                        inning: "B10"
                    )
                ],
                emailSubject: "[Receipt] Yankees vs Orioles — Section 220B",
                source: "Yankees Ticket Exchange"
            ),
            AttendedGame(
                id: UUID(),
                date: date(2024, 4, 5, 13),
                ballparkId: "yankee-stadium",
                homeTeamId: Team.yankees.id, awayTeamId: Team.blueJays.id,
                homeScore: 4, awayScore: 6,
                userRootedForHome: true,
                section: "Bleachers 204", row: "12", seat: "1",
                weather: .cloudy, firstPitchTempF: 52, attendance: 40_117, durationMinutes: 195,
                highlights: [
                    .init(inning: "T6", description: "Guerrero Jr. 2-run HR to upper deck", kind: .homeRun)
                ],
                milestones: [],
                emailSubject: "Resale confirmed: Yankees vs Blue Jays",
                source: "StubHub"
            )
        ]
    }

    /// Outlook — older work account; archival games.
    static var outlookGames: [AttendedGame] {
        [
            AttendedGame(
                id: UUID(),
                date: date(2023, 9, 24, 13),
                ballparkId: "minute-maid-park",
                homeTeamId: Team.astros.id, awayTeamId: Team.mariners.id,
                homeScore: 4, awayScore: 3,
                userRootedForHome: true,
                section: "Crawford Boxes 100", row: "1", seat: "12",
                weather: .dome, firstPitchTempF: 72, attendance: 39_117, durationMinutes: 173,
                highlights: [
                    .init(inning: "B2", description: "Altuve HR into the Crawford Boxes", kind: .homeRun),
                    .init(inning: "T9", description: "Pressly K's the side", kind: .pitching)
                ],
                milestones: [
                    PlayerMilestone(
                        id: UUID(),
                        playerName: "José Altuve",
                        teamId: Team.astros.id,
                        title: "2,000th Career Hit",
                        category: .hits,
                        stat: "H #2,000",
                        detail: "Altuve's 2nd-inning home run into the Crawford Boxes was his 2,000th career hit — making him the first Astro to reach the mark in pinstripes.",
                        context: "The 295th player in MLB history to record 2,000 hits, and the first second baseman of his generation to do so before age 34.",
                        inning: "B2"
                    )
                ],
                emailSubject: "StubHub: Astros vs Mariners — print at home",
                source: "StubHub"
            ),
            AttendedGame(
                id: UUID(),
                date: date(2023, 6, 18, 19),
                ballparkId: "truist-park",
                homeTeamId: Team.braves.id, awayTeamId: Team.mets.id,
                homeScore: 8, awayScore: 2,
                userRootedForHome: true,
                section: "108", row: "20", seat: "4",
                weather: .clear, firstPitchTempF: 86, attendance: 41_004, durationMinutes: 181,
                highlights: [
                    .init(inning: "B1", description: "Acuña Jr. leadoff HR", kind: .homeRun),
                    .init(inning: "B5", description: "Olson 3-run HR", kind: .homeRun),
                    .init(inning: "B7", description: "Riley solo HR", kind: .homeRun)
                ],
                milestones: [
                    PlayerMilestone(
                        id: UUID(),
                        playerName: "Ronald Acuña Jr.",
                        teamId: Team.braves.id,
                        title: "30/30 Season Clinched",
                        category: .milestone,
                        stat: "30 HR / 30 SB",
                        detail: "Acuña's leadoff blast was his 30th home run of the season, completing a 30/30 campaign for the second time in his career.",
                        context: "Only player in MLB history with multiple 30/30/30 (HR/SB/2B) seasons before age 26.",
                        inning: "B1"
                    )
                ],
                emailSubject: "Ticket transfer received — Braves vs Mets",
                source: "MLB Ballpark"
            ),
            AttendedGame(
                id: UUID(),
                date: date(2023, 4, 22, 13),
                ballparkId: "citizens-bank-park",
                homeTeamId: Team.phillies.id, awayTeamId: Team.rockies.id,
                homeScore: 5, awayScore: 3,
                userRootedForHome: true,
                section: "203", row: "8", seat: "16",
                weather: .partlyCloudy, firstPitchTempF: 61, attendance: 41_900, durationMinutes: 167,
                highlights: [
                    .init(inning: "B4", description: "Harper 2-run double off the wall", kind: .hit),
                    .init(inning: "B6", description: "Schwarber HR — Liberty Bell rings", kind: .homeRun)
                ],
                milestones: [],
                emailSubject: "Your tickets — Rockies vs Phillies",
                source: "Phillies.com"
            )
        ]
    }

    /// Yahoo — secondary account; West-Coast resale buys.
    static var yahooGames: [AttendedGame] {
        [
            AttendedGame(
                id: UUID(),
                date: date(2024, 6, 4, 19),
                ballparkId: "petco-park",
                homeTeamId: Team.padres.id, awayTeamId: Team.dodgers.id,
                homeScore: 4, awayScore: 3,
                userRootedForHome: false,
                section: "Toyota Terrace 207", row: "12", seat: "9",
                weather: .clear, firstPitchTempF: 70, attendance: 44_512, durationMinutes: 192,
                highlights: [
                    .init(inning: "B8", description: "Machado go-ahead 2-run HR", kind: .homeRun),
                    .init(inning: "T9", description: "Ohtani triple to deep right-center", kind: .hit)
                ],
                milestones: [
                    PlayerMilestone(
                        id: UUID(),
                        playerName: "Manny Machado",
                        teamId: Team.padres.id,
                        title: "350th Career Home Run",
                        category: .homeRun,
                        stat: "HR #350",
                        detail: "Machado's go-ahead 2-run shot in the 8th was the 350th of his career — the 7th-fastest third baseman in history to reach the mark.",
                        context: "Joins Adrián Beltré, Mike Schmidt and Chipper Jones as the only third basemen to record 350 HRs before age 32.",
                        inning: "B8"
                    )
                ],
                emailSubject: "Vivid Seats: Padres vs Dodgers — Petco Park",
                source: "Vivid Seats"
            )
        ]
    }

    /// Other — generic ticketing platform receipts.
    static var otherGames: [AttendedGame] {
        [
            AttendedGame(
                id: UUID(),
                date: date(2024, 9, 7, 13),
                ballparkId: "american-family-field",
                homeTeamId: Team.brewers.id, awayTeamId: Team.cubs.id,
                homeScore: 6, awayScore: 5,
                userRootedForHome: true,
                section: "Loge Bleacher 222", row: "12", seat: "8",
                weather: .clear, firstPitchTempF: 76, attendance: 38_915, durationMinutes: 199,
                highlights: [
                    .init(inning: "B9", description: "Yelich walk-off 2-run HR — Bernie slides", kind: .walkoff)
                ],
                milestones: [
                    PlayerMilestone(
                        id: UUID(),
                        playerName: "Christian Yelich",
                        teamId: Team.brewers.id,
                        title: "First Walk-Off HR Since 2022",
                        category: .homeRun,
                        stat: "Walk-off HR",
                        detail: "Yelich ended a 642-day walk-off home run drought with a 2-run blast off the right-field foul pole.",
                        context: "His 3rd career walk-off home run and first as a Brewers' team captain.",
                        inning: "B9"
                    )
                ],
                emailSubject: "TickPick: Order confirmed — Brewers vs Cubs",
                source: "TickPick"
            )
        ]
    }
}
