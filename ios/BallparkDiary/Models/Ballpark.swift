import Foundation
import CoreLocation
import SwiftUI

/// One of the 30 MLB ballparks. Static reference data.
struct Ballpark: Identifiable, Hashable {
    let id: String           // short slug, e.g. "yankee-stadium"
    let name: String
    let nickname: String?    // e.g. "The House That Ruth Built"
    let team: Team
    let city: String
    let state: String
    let latitude: Double
    let longitude: Double
    let capacity: Int
    let opened: Int          // year
    let surface: String      // "Grass", "Artificial Turf"
    let roof: RoofType
    let illustration: IllustrationStyle
    let trivia: String

    /// Real stadium photo from Wikipedia Commons (640px thumbnail).
    var photoURL: URL? { Self.photoURLs[id] }

    /// Locally bundled stadium photo asset (generated or curated).
    var photoAssetName: String? { Self.photoAssets[id] }

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }

    enum RoofType: String { case open = "Open Air", retractable = "Retractable", dome = "Dome" }

    /// Visual identity for stadium-specific illustrations.
    enum IllustrationStyle: Hashable {
        /// Pre-war classic parks with manual scoreboards and ivy walls
        case classic(marqueeColor: String)
        /// Retro-classic parks built in the Camden Yards era (brick + steel)
        case retroClassic
        /// Modern parks with clean lines and big screens
        case modern
        /// Parks with a retractable roof
        case retractable
        /// Fully enclosed domes
        case dome
        /// Parks with a signature landmark visible behind the stadium
        case landmark(String) // e.g. "Gateway Arch", "Roberto Clemente Bridge"

        /// Parks known for outfield water features (McCovey Cove, Kauffman fountains)
        var hasWaterFeature: Bool {
            switch self {
            case .landmark(let l): return l.contains("Cove") || l.contains("Fountain")
            default: return false
            }
        }
    }
}

extension Ballpark {
    static let all: [Ballpark] = [
        .init(id: "yankee-stadium", name: "Yankee Stadium", nickname: "The House That Ruth Built (II)", team: .yankees, city: "Bronx", state: "NY", latitude: 40.8296, longitude: -73.9262, capacity: 46_537, opened: 2009, surface: "Grass", roof: .open, illustration: .modern, trivia: "27 World Series banners fly above the bleachers."),
        .init(id: "fenway-park", name: "Fenway Park", nickname: "America's Most Beloved Ballpark", team: .redSox, city: "Boston", state: "MA", latitude: 42.3467, longitude: -71.0972, capacity: 37_755, opened: 1912, surface: "Grass", roof: .open, illustration: .classic(marqueeColor: "#BD3039"), trivia: "The 37-foot Green Monster in left field opened with the park in 1912."),
        .init(id: "wrigley-field", name: "Wrigley Field", nickname: "The Friendly Confines", team: .cubs, city: "Chicago", state: "IL", latitude: 41.9484, longitude: -87.6553, capacity: 41_649, opened: 1914, surface: "Grass", roof: .open, illustration: .classic(marqueeColor: "#CC3433"), trivia: "Ivy was planted on the outfield walls by Bill Veeck in 1937."),
        .init(id: "dodger-stadium", name: "Dodger Stadium", nickname: "Chavez Ravine", team: .dodgers, city: "Los Angeles", state: "CA", latitude: 34.0739, longitude: -118.2400, capacity: 56_000, opened: 1962, surface: "Grass", roof: .open, illustration: .landmark("San Gabriel Mountains"), trivia: "The largest capacity in MLB; sunsets over center field are legendary."),
        .init(id: "oracle-park", name: "Oracle Park", nickname: "The Yard by the Bay", team: .giants, city: "San Francisco", state: "CA", latitude: 37.7786, longitude: -122.3893, capacity: 41_915, opened: 2000, surface: "Grass", roof: .open, illustration: .landmark("McCovey Cove"), trivia: "McCovey Cove sits beyond right field — kayakers wait there for splash hits."),
        .init(id: "camden-yards", name: "Oriole Park at Camden Yards", nickname: "Camden Yards", team: .orioles, city: "Baltimore", state: "MD", latitude: 39.2839, longitude: -76.6217, capacity: 44_970, opened: 1992, surface: "Grass", roof: .open, illustration: .landmark("B&O Warehouse"), trivia: "Kicked off the retro-classic ballpark era; the B&O Warehouse sits 460 ft from home."),
        .init(id: "pnc-park", name: "PNC Park", nickname: "The Best View in Baseball", team: .pirates, city: "Pittsburgh", state: "PA", latitude: 40.4469, longitude: -80.0057, capacity: 38_747, opened: 2001, surface: "Grass", roof: .open, illustration: .landmark("Clemente Bridge"), trivia: "The Roberto Clemente Bridge closes for foot traffic on game days."),
        .init(id: "citi-field", name: "Citi Field", nickname: "Flushing", team: .mets, city: "Queens", state: "NY", latitude: 40.7571, longitude: -73.8458, capacity: 41_922, opened: 2009, surface: "Grass", roof: .open, illustration: .modern, trivia: "The Home Run Apple rises from center field after every Mets dinger."),
        .init(id: "citizens-bank-park", name: "Citizens Bank Park", nickname: "The Bank", team: .phillies, city: "Philadelphia", state: "PA", latitude: 39.9061, longitude: -75.1665, capacity: 42_901, opened: 2004, surface: "Grass", roof: .open, illustration: .modern, trivia: "The Liberty Bell lights up and rings after every Phillies home run."),
        .init(id: "truist-park", name: "Truist Park", nickname: "The Battery", team: .braves, city: "Atlanta", state: "GA", latitude: 33.8908, longitude: -84.4678, capacity: 41_084, opened: 2017, surface: "Grass", roof: .open, illustration: .modern, trivia: "Surrounded by The Battery — a mixed-use district built around the stadium."),
        .init(id: "nationals-park", name: "Nationals Park", nickname: "The Yard", team: .nationals, city: "Washington", state: "DC", latitude: 38.8730, longitude: -77.0074, capacity: 41_376, opened: 2008, surface: "Grass", roof: .open, illustration: .landmark("Capitol"), trivia: "The Presidents Race happens in the 4th inning every game."),
        .init(id: "loandepot-park", name: "loanDepot park", nickname: "The Fish Tank", team: .marlins, city: "Miami", state: "FL", latitude: 25.7781, longitude: -80.2197, capacity: 36_742, opened: 2012, surface: "Grass", roof: .retractable, illustration: .retractable, trivia: "Two 450-gallon aquariums sit behind home plate."),
        .init(id: "tropicana-field", name: "Tropicana Field", nickname: "The Trop", team: .rays, city: "St. Petersburg", state: "FL", latitude: 27.7682, longitude: -82.6534, capacity: 25_000, opened: 1990, surface: "Artificial Turf", roof: .dome, illustration: .dome, trivia: "Catwalks above the field are in play — and have caused many odd rulings."),
        .init(id: "rogers-centre", name: "Rogers Centre", nickname: "The Dome", team: .blueJays, city: "Toronto", state: "ON", latitude: 43.6414, longitude: -79.3894, capacity: 41_500, opened: 1989, surface: "Grass", roof: .retractable, illustration: .landmark("CN Tower"), trivia: "The first stadium with a fully retractable motorized roof."),
        .init(id: "progressive-field", name: "Progressive Field", nickname: "The Prog", team: .guardians, city: "Cleveland", state: "OH", latitude: 41.4962, longitude: -81.6852, capacity: 34_788, opened: 1994, surface: "Grass", roof: .open, illustration: .retroClassic, trivia: "Heritage Park beyond center field honors the franchise's Hall of Famers."),
        .init(id: "comerica-park", name: "Comerica Park", nickname: "The CoPa", team: .tigers, city: "Detroit", state: "MI", latitude: 42.3390, longitude: -83.0485, capacity: 41_083, opened: 2000, surface: "Grass", roof: .open, illustration: .landmark("Downtown Detroit"), trivia: "Two giant tiger statues guard the main entrance, eyes glowing at night."),
        .init(id: "american-family-field", name: "American Family Field", nickname: "Miller Park (forever)", team: .brewers, city: "Milwaukee", state: "WI", latitude: 43.0280, longitude: -87.9712, capacity: 41_900, opened: 2001, surface: "Grass", roof: .retractable, illustration: .retractable, trivia: "Bernie Brewer still slides down a yellow slide after every home run."),
        .init(id: "target-field", name: "Target Field", nickname: "The Jewel Box", team: .twins, city: "Minneapolis", state: "MN", latitude: 44.9817, longitude: -93.2776, capacity: 38_544, opened: 2010, surface: "Grass", roof: .open, illustration: .landmark("Minneapolis Skyline"), trivia: "Hidden in downtown — the smallest footprint of any MLB park."),
        .init(id: "rate-field", name: "Guaranteed Rate Field", nickname: "Sox Park", team: .whiteSox, city: "Chicago", state: "IL", latitude: 41.8299, longitude: -87.6338, capacity: 40_615, opened: 1991, surface: "Grass", roof: .open, illustration: .modern, trivia: "Home of the famous exploding scoreboard, a Bill Veeck original."),
        .init(id: "kauffman-stadium", name: "Kauffman Stadium", nickname: "The K", team: .royals, city: "Kansas City", state: "MO", latitude: 39.0517, longitude: -94.4803, capacity: 37_903, opened: 1973, surface: "Grass", roof: .open, illustration: .landmark("Fountains"), trivia: "The 322-foot wide outfield waterfall is the largest privately funded fountain in the world."),
        .init(id: "minute-maid-park", name: "Daikin Park", nickname: "The Juice Box", team: .astros, city: "Houston", state: "TX", latitude: 29.7572, longitude: -95.3553, capacity: 41_168, opened: 2000, surface: "Grass", roof: .retractable, illustration: .landmark("Houston Skyline"), trivia: "A vintage locomotive runs along the left field tracks after Astros home runs."),
        .init(id: "globe-life-field", name: "Globe Life Field", nickname: "The Globe", team: .rangers, city: "Arlington", state: "TX", latitude: 32.7474, longitude: -97.0824, capacity: 40_300, opened: 2020, surface: "Artificial Turf", roof: .retractable, illustration: .retractable, trivia: "Hosted the entire 2020 World Series during the pandemic-era neutral site."),
        .init(id: "busch-stadium", name: "Busch Stadium", nickname: "The New Busch", team: .cardinals, city: "St. Louis", state: "MO", latitude: 38.6226, longitude: -90.1928, capacity: 44_494, opened: 2006, surface: "Grass", roof: .open, illustration: .landmark("Gateway Arch"), trivia: "The Gateway Arch frames the view beyond center field."),
        .init(id: "great-american-ball-park", name: "Great American Ball Park", nickname: "The GABP", team: .reds, city: "Cincinnati", state: "OH", latitude: 39.0975, longitude: -84.5066, capacity: 42_319, opened: 2003, surface: "Grass", roof: .open, illustration: .landmark("Ohio River"), trivia: "Riverboat smokestacks beyond center field fire when a Red goes deep."),
        .init(id: "chase-field", name: "Chase Field", nickname: "The BOB", team: .diamondbacks, city: "Phoenix", state: "AZ", latitude: 33.4453, longitude: -112.0667, capacity: 48_519, opened: 1998, surface: "Artificial Turf", roof: .retractable, illustration: .retractable, trivia: "The only MLB ballpark with a swimming pool beyond the outfield wall."),
        .init(id: "coors-field", name: "Coors Field", nickname: "The Mile High Yard", team: .rockies, city: "Denver", state: "CO", latitude: 39.7559, longitude: -104.9942, capacity: 50_445, opened: 1995, surface: "Grass", roof: .open, illustration: .landmark("Rocky Mountains"), trivia: "The 20th-row purple seats in the upper deck mark exactly one mile above sea level."),
        .init(id: "petco-park", name: "Petco Park", nickname: "America's Ballpark", team: .padres, city: "San Diego", state: "CA", latitude: 32.7073, longitude: -117.1566, capacity: 40_209, opened: 2004, surface: "Grass", roof: .open, illustration: .landmark("Coronado Bridge"), trivia: "The 1909 Western Metal Supply Co. building is preserved inside the left field corner."),
        .init(id: "angel-stadium", name: "Angel Stadium", nickname: "The Big A", team: .angels, city: "Anaheim", state: "CA", latitude: 33.8003, longitude: -117.8827, capacity: 45_517, opened: 1966, surface: "Grass", roof: .open, illustration: .landmark("The Big A"), trivia: "The Big A scoreboard out beyond the parking lot is the third-largest in the majors."),
        .init(id: "t-mobile-park", name: "T-Mobile Park", nickname: "The Safe", team: .mariners, city: "Seattle", state: "WA", latitude: 47.5914, longitude: -122.3325, capacity: 47_929, opened: 1999, surface: "Grass", roof: .retractable, illustration: .landmark("Space Needle"), trivia: "The roof is an umbrella, not a lid — it shelters but doesn't enclose."),
        .init(id: "sutter-health-park", name: "Sutter Health Park", nickname: "The A's New Home", team: .athletics, city: "Sacramento", state: "CA", latitude: 38.5800, longitude: -121.5130, capacity: 14_014, opened: 2000, surface: "Grass", roof: .open, illustration: .landmark("Tower Bridge"), trivia: "The smallest park in the majors during the Athletics' transitional years.")
    ]

    static func by(id: String) -> Ballpark? {
        all.first(where: { $0.id == id })
    }

    /// The current home ballpark for a given team slug.
    static func by(teamId: String) -> Ballpark? {
        all.first(where: { $0.team.id == teamId })
    }

    /// Find a ballpark by venue name from the MLB API (handles international venues).
    static func by(venueName: String) -> Ballpark? {
        let lower = venueName.lowercased()
        // Direct slug match
        if let direct = all.first(where: { $0.id == lower.replacingOccurrences(of: " ", with: "-") }) { return direct }
        // Venue name substring match
        if let byName = all.first(where: { lower.contains($0.name.lowercased()) || $0.name.lowercased().contains(lower) }) { return byName }
        return nil
    }

    // MARK: - Stadium photos (Wikipedia Commons)

    /// Locally bundled stadium photos (generated images in Assets.xcassets).
    static let photoAssets: [String: String] = [
        "citi-field":               "citi_field_baseball_stadium",
        "citizens-bank-park":        "citizens_bank_park",
        "american-family-field":     "exterior_professional_architectural",
        "target-field":              "target_field_stadium",
        "rate-field":                "guaranteed_rate_field_stadium",
        "minute-maid-park":          "astros_stadium_houston",
        "globe-life-field":          "globe_life_field_stadium",
        "busch-stadium":             "busch_stadium_cardinals",
        "great-american-ball-park":  "great_american_ball_park",
        "chase-field":               "chase_field_stadium",
        "coors-field":               "coors_field_stadium",
        "t-mobile-park":             "tmobile_park_stadium",
        "sutter-health-park":        "baseball_stadium_tower_bridge",
    ]

    /// Real stadium photos from Wikipedia Commons (full-resolution originals).
    /// All 30 MLB ballparks — ground-level exterior shots, no aerials.
    /// Using raw URLs because Wikipedia's thumbnail CDN returns 400
    /// from many client IPs; AsyncImage handles scaling on-device.
    static let photoURLs: [String: URL] = [
        "yankee-stadium":           URL(string: "https://upload.wikimedia.org/wikipedia/commons/3/3f/Yankee_stadium_exterior.jpg")!,
        "fenway-park":              URL(string: "https://upload.wikimedia.org/wikipedia/commons/4/4f/131023-F-PR861-033_Hanscom_participates_in_World_Series_pregame_events.jpg")!,
        "wrigley-field":            URL(string: "https://upload.wikimedia.org/wikipedia/commons/c/c9/Wrigley_Field_in_line_with_sign.jpg")!,
        "dodger-stadium":           URL(string: "https://upload.wikimedia.org/wikipedia/commons/5/50/Dodger_Stadium_and_Chavez_Ravine_far_view,_Chicago_Cubs_at_Los_Angeles_Dodgers,_(April_12,_2025).jpg")!,
        "oracle-park":              URL(string: "https://upload.wikimedia.org/wikipedia/commons/8/8e/Oracle_Park_2021.jpg")!,
        "camden-yards":             URL(string: "https://upload.wikimedia.org/wikipedia/commons/5/51/OrioleParkatCamdenYardsSummer2025.jpg")!,
        "pnc-park":                 URL(string: "https://upload.wikimedia.org/wikipedia/commons/0/0e/Pittsburgh_Pirates_park_%28Unsplash%29.jpg")!,
        "citi-field":               URL(string: "https://upload.wikimedia.org/wikipedia/commons/0/03/Citi_Field_main_entrance.jpg")!,
        "citizens-bank-park":       URL(string: "https://upload.wikimedia.org/wikipedia/commons/f/f6/Citizens_Bank_Park_2021.jpg")!,
        "truist-park":              URL(string: "https://upload.wikimedia.org/wikipedia/commons/0/04/Truist_Park_2025.jpg")!,
        "nationals-park":           URL(string: "https://upload.wikimedia.org/wikipedia/commons/f/f9/Nationals_Park_8.16.19_-_7.jpg")!,
        "loandepot-park":           URL(string: "https://upload.wikimedia.org/wikipedia/commons/5/53/LOAN_DEPOT_PARK.jpg")!,
        "tropicana-field":          URL(string: "https://upload.wikimedia.org/wikipedia/commons/5/5e/PXL_20220528_205520913.jpg")!,
        "rogers-centre":            URL(string: "https://upload.wikimedia.org/wikipedia/commons/1/1d/Rogers_Centre,_Toronto,_Ontario_%2821652480228%29.jpg")!,
        "progressive-field":        URL(string: "https://upload.wikimedia.org/wikipedia/commons/e/e6/2016-10-06_Progressive_Field_before_ALDS_Game_1_between_Cleveland_and_Boston.jpg")!,
        "comerica-park":            URL(string: "https://upload.wikimedia.org/wikipedia/commons/5/57/Comerica_Park,_Home_of_the_Detroit_Tigers_Baseball_Team.jpg")!,
        "american-family-field":    URL(string: "https://upload.wikimedia.org/wikipedia/commons/c/cc/Miller_Park_in_Milwaukee%2C_Wisconsin.jpg")!,
        "target-field":             URL(string: "https://upload.wikimedia.org/wikipedia/commons/1/17/Target_Field%2C_Minneapolis%2C_Minnesota_%2843167053335%29.jpg")!,
        "rate-field":               URL(string: "https://upload.wikimedia.org/wikipedia/commons/2/21/Guaranteed_Rate_Field_White_Sox_vs_NY_Mets_04.jpg")!,
        "kauffman-stadium":         URL(string: "https://upload.wikimedia.org/wikipedia/commons/3/35/Kauffman2017.jpg")!,
        "minute-maid-park":         URL(string: "https://upload.wikimedia.org/wikipedia/commons/1/10/Houston%2C_Texas_%282024%29_-_09.jpg")!,
        "globe-life-field":         URL(string: "https://upload.wikimedia.org/wikipedia/commons/a/a0/GlobeLifeField2021.jpg")!,
        "busch-stadium":            URL(string: "https://upload.wikimedia.org/wikipedia/commons/f/fb/Busch_Stadium_2022.jpg")!,
        "great-american-ball-park": URL(string: "https://upload.wikimedia.org/wikipedia/commons/4/4a/10Cincinnati_2015_%282%29.jpg")!,
        "chase-field":              URL(string: "https://upload.wikimedia.org/wikipedia/commons/a/a2/Reserve_A-10_Warthogs_Flyover_2023_World_Series_%288099146%29.jpg")!,
        "coors-field":              URL(string: "https://upload.wikimedia.org/wikipedia/commons/e/e2/Coors_Field_July_2015.jpg")!,
        "petco-park":               URL(string: "https://upload.wikimedia.org/wikipedia/commons/5/55/Petco_Park_Padres_Game.jpg")!,
        "angel-stadium":            URL(string: "https://upload.wikimedia.org/wikipedia/commons/4/4a/Angelstadiummarch2019.jpg")!,
        "t-mobile-park":            URL(string: "https://upload.wikimedia.org/wikipedia/commons/1/1a/Seattle_Safeco_Field_01.jpg")!,
        "sutter-health-park":       URL(string: "https://upload.wikimedia.org/wikipedia/commons/8/84/Outside_Sutter_Health_Park.jpg")!,
    ]

    // MARK: - Fun discoveries (ballpark quest facts)

    /// Curated fun facts for each ballpark — things to look forward to
    /// discovering when visiting for the first time.
    static let discoveries: [String: [String]] = [
        "yankee-stadium": ["Monument Park honors Ruth, Gehrig, DiMaggio, and Mantle.", "The frieze along the roof is a replica of the 1923 original facade."],
        "fenway-park": ["The lone red seat in the bleachers marks Ted Williams' 502 ft blast.", "Pesky's Pole in right field is just 302 feet from home."],
        "wrigley-field": ["The manual scoreboard has been operated by hand since 1937.", "Rooftop seats across Waveland Avenue have watched games since 1914."],
        "dodger-stadium": ["Parking attendants still direct 16,000 cars with hand signals.", "The hexagonal scoreboard was replaced in 1980 but remains iconic."],
        "oracle-park": ["McCovey Cove has registered over 160 splash hits since 2000.", "The giant glove in left field is 26 feet wide and 30 feet tall."],
        "camden-yards": ["The B&O Warehouse is the longest brick building on the East Coast.", "The warehouse has never been hit by a home run in a real game."],
        "pnc-park": ["You can watch the game for free from the Roberto Clemente Bridge.", "Just 38,747 seats — players call it the most intimate park."],
        "citi-field": ["The Jackie Robinson Rotunda's terrazzo floor is 70 feet wide.", "Shake Shack in center field has a legendary line."],
        "citizens-bank-park": ["The Phanatic's hot dog launcher can reach the upper deck.", "Ashburn Alley is a walk of fame for Phillies legends."],
        "truist-park": ["The Monument Garden honors Boston, Milwaukee, and Atlanta eras.", "The Chop House in right field serves BBQ overlooking the warning track."],
        "nationals-park": ["Upper deck views include the Capitol and Washington Monument.", "The Racing Presidents have logged over 1,000 races since 2006."],
        "loandepot-park": ["Two 450-gallon saltwater aquariums sit behind home plate.", "The Clevelander in left field is the only pool-party section in the NL."],
        "tropicana-field": ["Catwalks above the field are in play and have caused many odd rulings.", "The stingray touch tank in right-center holds 10,000 gallons."],
        "rogers-centre": ["Hotel rooms overlooking the field let you watch a game from bed.", "The 11,000-ton roof takes 20 minutes to open or close."],
        "progressive-field": ["Heritage Park honors Bob Feller and other franchise legends.", "The bleachers look straight at downtown's Terminal Tower."],
        "comerica-park": ["Two giant tiger statues guard the entrance, eyes glowing at night.", "The Chevrolet Fountain in center field dances to music."],
        "american-family-field": ["Bernie Brewer still slides down a yellow slide after every homer.", "The Sausage Race features five costumed racers since the '90s."],
        "target-field": ["The limestone exterior matches downtown Minneapolis architecture.", "Minnie and Paul shake hands after every Twins home run."],
        "rate-field": ["The exploding scoreboard was a Bill Veeck original.", "Fireworks blast off after every White Sox home run."],
        "kauffman-stadium": ["The 322-ft wide waterfall is the largest private fountain on Earth.", "The crown-shaped scoreboard is 106 feet tall."],
        "minute-maid-park": ["A vintage locomotive runs 800 feet of track after Astros homers.", "Tal's Hill once featured a 30-degree incline with a flagpole in play."],
        "globe-life-field": ["The ETFE roof lets in natural light while blocking Texas heat.", "One of only six MLB stadiums with a synthetic surface."],
        "busch-stadium": ["The Gateway Arch frames the view beyond center field.", "Ballpark Village next door is a 150,000 sq ft entertainment district."],
        "great-american-ball-park": ["Riverboat smokestacks fire flames after Reds home runs.", "The Gap in right field was left open for Ohio River views."],
        "chase-field": ["The only MLB park with a swimming pool beyond the outfield wall.", "The roof opens in about 4 minutes with two 200-hp motors."],
        "coors-field": ["Baseballs are stored in a humidor to counteract Denver's thin air.", "The purple row of seats marks exactly one mile above sea level."],
        "petco-park": ["The 1909 Western Metal Supply building is now the foul pole.", "The Park at the Park is a 2.7-acre public green space."],
        "angel-stadium": ["The Big A sign is the third-largest scoreboard in the majors.", "A rock pile in left-center mimics the Anaheim Hills."],
        "t-mobile-park": ["The retractable roof is an umbrella — it shelters but doesn't enclose.", "The Hit It Here Cafe is a two-story restaurant with field views."],
        "sutter-health-park": ["The gold Tower Bridge beyond left field honors Gold Rush history.", "Lawn seating in right field is one of the most affordable MLB experiences."],
    ]

    /// A random fun fact for this park.
    func discoveryFact() -> String {
        let list = Self.discoveries[id] ?? [trivia]
        return list.randomElement() ?? trivia
    }
}
