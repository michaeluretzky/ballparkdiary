import SwiftUI

/// Static MLB team reference, including brand colors used across the app.
struct Team: Identifiable, Hashable {
    let id: String
    let city: String
    let name: String         // e.g. "Yankees"
    let abbreviation: String // e.g. "NYY"
    let logoMark: String     // Distinctive cap letter mark, e.g. "NY", "B", "LA"
    let primaryHex: String
    let secondaryHex: String

    var fullName: String { city.isEmpty ? name : "\(city) \(name)" }
    var primary: Color { Color(hex: primaryHex) }
    var secondary: Color { Color(hex: secondaryHex) }
}

extension Team {
    // AL East
    static let yankees    = Team(id: "nyy", city: "New York",     name: "Yankees",      abbreviation: "NYY", logoMark: "NY",  primaryHex: "#0C2340", secondaryHex: "#C4CED4")
    static let redSox     = Team(id: "bos", city: "Boston",       name: "Red Sox",      abbreviation: "BOS", logoMark: "B",   primaryHex: "#BD3039", secondaryHex: "#0C2340")
    static let blueJays   = Team(id: "tor", city: "Toronto",      name: "Blue Jays",    abbreviation: "TOR", logoMark: "T",   primaryHex: "#134A8E", secondaryHex: "#E8291C")
    static let orioles    = Team(id: "bal", city: "Baltimore",    name: "Orioles",      abbreviation: "BAL", logoMark: "O",   primaryHex: "#DF4601", secondaryHex: "#000000")
    static let rays       = Team(id: "tb",  city: "Tampa Bay",    name: "Rays",         abbreviation: "TB",  logoMark: "TB",  primaryHex: "#092C5C", secondaryHex: "#8FBCE6")
    // AL Central
    static let guardians  = Team(id: "cle", city: "Cleveland",    name: "Guardians",    abbreviation: "CLE", logoMark: "C",   primaryHex: "#00385D", secondaryHex: "#E50022")
    static let tigers     = Team(id: "det", city: "Detroit",      name: "Tigers",       abbreviation: "DET", logoMark: "D",   primaryHex: "#0C2340", secondaryHex: "#FA4616")
    static let royals     = Team(id: "kc",  city: "Kansas City",  name: "Royals",       abbreviation: "KC",  logoMark: "KC",  primaryHex: "#004687", secondaryHex: "#BD9B60")
    static let twins      = Team(id: "min", city: "Minnesota",    name: "Twins",        abbreviation: "MIN", logoMark: "TC",  primaryHex: "#002B5C", secondaryHex: "#D31145")
    static let whiteSox   = Team(id: "cws", city: "Chicago",      name: "White Sox",    abbreviation: "CWS", logoMark: "SOX", primaryHex: "#27251F", secondaryHex: "#C4CED4")
    // AL West
    static let astros     = Team(id: "hou", city: "Houston",      name: "Astros",       abbreviation: "HOU", logoMark: "H",   primaryHex: "#002D62", secondaryHex: "#EB6E1F")
    static let angels     = Team(id: "laa", city: "Los Angeles",  name: "Angels",       abbreviation: "LAA", logoMark: "A",   primaryHex: "#BA0021", secondaryHex: "#003263")
    static let athletics  = Team(id: "ath", city: "",             name: "Athletics",    abbreviation: "ATH", logoMark: "A's", primaryHex: "#003831", secondaryHex: "#EFB21E")
    static let mariners   = Team(id: "sea", city: "Seattle",      name: "Mariners",     abbreviation: "SEA", logoMark: "S",   primaryHex: "#0C2C56", secondaryHex: "#005C5C")
    static let rangers    = Team(id: "tex", city: "Texas",        name: "Rangers",      abbreviation: "TEX", logoMark: "T",   primaryHex: "#003278", secondaryHex: "#C0111F")
    // NL East
    static let braves     = Team(id: "atl", city: "Atlanta",      name: "Braves",       abbreviation: "ATL", logoMark: "A",   primaryHex: "#13274F", secondaryHex: "#CE1141")
    static let marlins    = Team(id: "mia", city: "Miami",        name: "Marlins",      abbreviation: "MIA", logoMark: "M",   primaryHex: "#00A3E0", secondaryHex: "#EF3340")
    static let mets       = Team(id: "nym", city: "New York",     name: "Mets",         abbreviation: "NYM", logoMark: "NY",  primaryHex: "#002D72", secondaryHex: "#FF5910")
    static let phillies   = Team(id: "phi", city: "Philadelphia", name: "Phillies",     abbreviation: "PHI", logoMark: "P",   primaryHex: "#E81828", secondaryHex: "#002D72")
    static let nationals  = Team(id: "wsh", city: "Washington",   name: "Nationals",    abbreviation: "WSH", logoMark: "W",   primaryHex: "#AB0003", secondaryHex: "#14225A")
    // NL Central
    static let cubs       = Team(id: "chc", city: "Chicago",      name: "Cubs",         abbreviation: "CHC", logoMark: "C",   primaryHex: "#0E3386", secondaryHex: "#CC3433")
    static let reds       = Team(id: "cin", city: "Cincinnati",   name: "Reds",         abbreviation: "CIN", logoMark: "C",   primaryHex: "#C6011F", secondaryHex: "#000000")
    static let brewers    = Team(id: "mil", city: "Milwaukee",    name: "Brewers",      abbreviation: "MIL", logoMark: "M",   primaryHex: "#12284B", secondaryHex: "#FFC52F")
    static let pirates    = Team(id: "pit", city: "Pittsburgh",   name: "Pirates",      abbreviation: "PIT", logoMark: "P",   primaryHex: "#27251F", secondaryHex: "#FDB827")
    static let cardinals  = Team(id: "stl", city: "St. Louis",    name: "Cardinals",    abbreviation: "STL", logoMark: "STL", primaryHex: "#C41E3A", secondaryHex: "#0C2340")
    // NL West
    static let diamondbacks = Team(id: "ari", city: "Arizona",    name: "Diamondbacks", abbreviation: "ARI", logoMark: "A",   primaryHex: "#A71930", secondaryHex: "#E3D4AD")
    static let rockies    = Team(id: "col", city: "Colorado",     name: "Rockies",      abbreviation: "COL", logoMark: "CR",  primaryHex: "#33006F", secondaryHex: "#C4CED4")
    static let dodgers    = Team(id: "lad", city: "Los Angeles",  name: "Dodgers",      abbreviation: "LAD", logoMark: "LA",  primaryHex: "#005A9C", secondaryHex: "#EF3E42")
    static let padres     = Team(id: "sd",  city: "San Diego",    name: "Padres",       abbreviation: "SD",  logoMark: "SD",  primaryHex: "#2F241D", secondaryHex: "#FFC425")
    static let giants     = Team(id: "sf",  city: "San Francisco", name: "Giants",      abbreviation: "SF",  logoMark: "SF",  primaryHex: "#FD5A1E", secondaryHex: "#27251F")

    static let all: [Team] = [
        yankees, redSox, blueJays, orioles, rays,
        guardians, tigers, royals, twins, whiteSox,
        astros, angels, athletics, mariners, rangers,
        braves, marlins, mets, phillies, nationals,
        cubs, reds, brewers, pirates, cardinals,
        diamondbacks, rockies, dodgers, padres, giants
    ]

    static func by(id: String) -> Team? { all.first(where: { $0.id == id }) }

    /// Maps our internal slug ids to the numeric team ids used by the public
    /// MLB Stats API (statsapi.mlb.com). Used to enrich scanned games with the
    /// real final score, venue and date.
    static let mlbIds: [String: Int] = [
        "laa": 108, "ari": 109, "bal": 110, "bos": 111, "chc": 112,
        "cin": 113, "cle": 114, "col": 115, "det": 116, "hou": 117,
        "kc": 118, "lad": 119, "wsh": 120, "nym": 121, "ath": 133,
        "pit": 134, "sd": 135, "sea": 136, "sf": 137, "stl": 138,
        "tb": 139, "tex": 140, "tor": 141, "min": 142, "phi": 143,
        "atl": 144, "cws": 145, "mia": 146, "nyy": 147, "mil": 158
    ]

    /// The numeric MLB Stats API id for this team.
    var mlbId: Int { Team.mlbIds[id] ?? 0 }

    /// Reverse lookup: find a team from its MLB Stats API numeric id.
    static func by(mlbId: Int) -> Team? {
        guard let slug = mlbIds.first(where: { $0.value == mlbId })?.key else { return nil }
        return by(id: slug)
    }
}

extension Color {
    /// Construct a color from a 6-digit hex string (with or without leading '#').
    init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
