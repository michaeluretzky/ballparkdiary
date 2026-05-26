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
    let trivia: String

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }

    enum RoofType: String { case open = "Open Air", retractable = "Retractable", dome = "Dome" }
}

extension Ballpark {
    static let all: [Ballpark] = [
        .init(id: "yankee-stadium", name: "Yankee Stadium", nickname: "The House That Ruth Built (II)", team: .yankees, city: "Bronx", state: "NY", latitude: 40.8296, longitude: -73.9262, capacity: 46_537, opened: 2009, surface: "Grass", roof: .open, trivia: "27 World Series banners fly above the bleachers."),
        .init(id: "fenway-park", name: "Fenway Park", nickname: "America's Most Beloved Ballpark", team: .redSox, city: "Boston", state: "MA", latitude: 42.3467, longitude: -71.0972, capacity: 37_755, opened: 1912, surface: "Grass", roof: .open, trivia: "The 37-foot Green Monster in left field opened with the park in 1912."),
        .init(id: "wrigley-field", name: "Wrigley Field", nickname: "The Friendly Confines", team: .cubs, city: "Chicago", state: "IL", latitude: 41.9484, longitude: -87.6553, capacity: 41_649, opened: 1914, surface: "Grass", roof: .open, trivia: "Ivy was planted on the outfield walls by Bill Veeck in 1937."),
        .init(id: "dodger-stadium", name: "Dodger Stadium", nickname: "Chavez Ravine", team: .dodgers, city: "Los Angeles", state: "CA", latitude: 34.0739, longitude: -118.2400, capacity: 56_000, opened: 1962, surface: "Grass", roof: .open, trivia: "The largest capacity in MLB; sunsets over center field are legendary."),
        .init(id: "oracle-park", name: "Oracle Park", nickname: "The Yard by the Bay", team: .giants, city: "San Francisco", state: "CA", latitude: 37.7786, longitude: -122.3893, capacity: 41_915, opened: 2000, surface: "Grass", roof: .open, trivia: "McCovey Cove sits beyond right field — kayakers wait there for splash hits."),
        .init(id: "camden-yards", name: "Oriole Park at Camden Yards", nickname: "Camden Yards", team: .orioles, city: "Baltimore", state: "MD", latitude: 39.2839, longitude: -76.6217, capacity: 44_970, opened: 1992, surface: "Grass", roof: .open, trivia: "Kicked off the retro-classic ballpark era; the B&O Warehouse sits 460 ft from home."),
        .init(id: "pnc-park", name: "PNC Park", nickname: "The Best View in Baseball", team: .pirates, city: "Pittsburgh", state: "PA", latitude: 40.4469, longitude: -80.0057, capacity: 38_747, opened: 2001, surface: "Grass", roof: .open, trivia: "The Roberto Clemente Bridge closes for foot traffic on game days."),
        .init(id: "citi-field", name: "Citi Field", nickname: "Flushing", team: .mets, city: "Queens", state: "NY", latitude: 40.7571, longitude: -73.8458, capacity: 41_922, opened: 2009, surface: "Grass", roof: .open, trivia: "The Home Run Apple rises from center field after every Mets dinger."),
        .init(id: "citizens-bank-park", name: "Citizens Bank Park", nickname: "The Bank", team: .phillies, city: "Philadelphia", state: "PA", latitude: 39.9061, longitude: -75.1665, capacity: 42_901, opened: 2004, surface: "Grass", roof: .open, trivia: "The Liberty Bell lights up and rings after every Phillies home run."),
        .init(id: "truist-park", name: "Truist Park", nickname: "The Battery", team: .braves, city: "Atlanta", state: "GA", latitude: 33.8908, longitude: -84.4678, capacity: 41_084, opened: 2017, surface: "Grass", roof: .open, trivia: "Surrounded by The Battery — a mixed-use district built around the stadium."),
        .init(id: "nationals-park", name: "Nationals Park", nickname: "The Yard", team: .nationals, city: "Washington", state: "DC", latitude: 38.8730, longitude: -77.0074, capacity: 41_376, opened: 2008, surface: "Grass", roof: .open, trivia: "The Presidents Race happens in the 4th inning every game."),
        .init(id: "loandepot-park", name: "loanDepot park", nickname: "The Fish Tank", team: .marlins, city: "Miami", state: "FL", latitude: 25.7781, longitude: -80.2197, capacity: 36_742, opened: 2012, surface: "Grass", roof: .retractable, trivia: "Two 450-gallon aquariums sit behind home plate."),
        .init(id: "tropicana-field", name: "Tropicana Field", nickname: "The Trop", team: .rays, city: "St. Petersburg", state: "FL", latitude: 27.7682, longitude: -82.6534, capacity: 25_000, opened: 1990, surface: "Artificial Turf", roof: .dome, trivia: "Catwalks above the field are in play — and have caused many odd rulings."),
        .init(id: "rogers-centre", name: "Rogers Centre", nickname: "The Dome", team: .blueJays, city: "Toronto", state: "ON", latitude: 43.6414, longitude: -79.3894, capacity: 41_500, opened: 1989, surface: "Grass", roof: .retractable, trivia: "The first stadium with a fully retractable motorized roof."),
        .init(id: "progressive-field", name: "Progressive Field", nickname: "The Prog", team: .guardians, city: "Cleveland", state: "OH", latitude: 41.4962, longitude: -81.6852, capacity: 34_788, opened: 1994, surface: "Grass", roof: .open, trivia: "Heritage Park beyond center field honors the franchise's Hall of Famers."),
        .init(id: "comerica-park", name: "Comerica Park", nickname: "The CoPa", team: .tigers, city: "Detroit", state: "MI", latitude: 42.3390, longitude: -83.0485, capacity: 41_083, opened: 2000, surface: "Grass", roof: .open, trivia: "Two giant tiger statues guard the main entrance, eyes glowing at night."),
        .init(id: "american-family-field", name: "American Family Field", nickname: "Miller Park (forever)", team: .brewers, city: "Milwaukee", state: "WI", latitude: 43.0280, longitude: -87.9712, capacity: 41_900, opened: 2001, surface: "Grass", roof: .retractable, trivia: "Bernie Brewer still slides down a yellow slide after every home run."),
        .init(id: "target-field", name: "Target Field", nickname: "The Jewel Box", team: .twins, city: "Minneapolis", state: "MN", latitude: 44.9817, longitude: -93.2776, capacity: 38_544, opened: 2010, surface: "Grass", roof: .open, trivia: "Hidden in downtown — the smallest footprint of any MLB park."),
        .init(id: "rate-field", name: "Guaranteed Rate Field", nickname: "Sox Park", team: .whiteSox, city: "Chicago", state: "IL", latitude: 41.8299, longitude: -87.6338, capacity: 40_615, opened: 1991, surface: "Grass", roof: .open, trivia: "Home of the famous exploding scoreboard, a Bill Veeck original."),
        .init(id: "kauffman-stadium", name: "Kauffman Stadium", nickname: "The K", team: .royals, city: "Kansas City", state: "MO", latitude: 39.0517, longitude: -94.4803, capacity: 37_903, opened: 1973, surface: "Grass", roof: .open, trivia: "The 322-foot wide outfield waterfall is the largest privately funded fountain in the world."),
        .init(id: "minute-maid-park", name: "Daikin Park", nickname: "The Juice Box", team: .astros, city: "Houston", state: "TX", latitude: 29.7572, longitude: -95.3553, capacity: 41_168, opened: 2000, surface: "Grass", roof: .retractable, trivia: "A vintage locomotive runs along the left field tracks after Astros home runs."),
        .init(id: "globe-life-field", name: "Globe Life Field", nickname: "The Globe", team: .rangers, city: "Arlington", state: "TX", latitude: 32.7474, longitude: -97.0824, capacity: 40_300, opened: 2020, surface: "Artificial Turf", roof: .retractable, trivia: "Hosted the entire 2020 World Series during the pandemic-era neutral site."),
        .init(id: "busch-stadium", name: "Busch Stadium", nickname: "The New Busch", team: .cardinals, city: "St. Louis", state: "MO", latitude: 38.6226, longitude: -90.1928, capacity: 44_494, opened: 2006, surface: "Grass", roof: .open, trivia: "The Gateway Arch frames the view beyond center field."),
        .init(id: "great-american-ball-park", name: "Great American Ball Park", nickname: "The GABP", team: .reds, city: "Cincinnati", state: "OH", latitude: 39.0975, longitude: -84.5066, capacity: 42_319, opened: 2003, surface: "Grass", roof: .open, trivia: "Riverboat smokestacks beyond center field fire when a Red goes deep."),
        .init(id: "chase-field", name: "Chase Field", nickname: "The BOB", team: .diamondbacks, city: "Phoenix", state: "AZ", latitude: 33.4453, longitude: -112.0667, capacity: 48_519, opened: 1998, surface: "Artificial Turf", roof: .retractable, trivia: "The only MLB ballpark with a swimming pool beyond the outfield wall."),
        .init(id: "coors-field", name: "Coors Field", nickname: "The Mile High Yard", team: .rockies, city: "Denver", state: "CO", latitude: 39.7559, longitude: -104.9942, capacity: 50_445, opened: 1995, surface: "Grass", roof: .open, trivia: "The 20th-row purple seats in the upper deck mark exactly one mile above sea level."),
        .init(id: "petco-park", name: "Petco Park", nickname: "America's Ballpark", team: .padres, city: "San Diego", state: "CA", latitude: 32.7073, longitude: -117.1566, capacity: 40_209, opened: 2004, surface: "Grass", roof: .open, trivia: "The 1909 Western Metal Supply Co. building is preserved inside the left field corner."),
        .init(id: "angel-stadium", name: "Angel Stadium", nickname: "The Big A", team: .angels, city: "Anaheim", state: "CA", latitude: 33.8003, longitude: -117.8827, capacity: 45_517, opened: 1966, surface: "Grass", roof: .open, trivia: "The Big A scoreboard out beyond the parking lot is the third-largest in the majors."),
        .init(id: "t-mobile-park", name: "T-Mobile Park", nickname: "The Safe", team: .mariners, city: "Seattle", state: "WA", latitude: 47.5914, longitude: -122.3325, capacity: 47_929, opened: 1999, surface: "Grass", roof: .retractable, trivia: "The roof is an umbrella, not a lid — it shelters but doesn't enclose."),
        .init(id: "sutter-health-park", name: "Sutter Health Park", nickname: "The A's New Home", team: .athletics, city: "Sacramento", state: "CA", latitude: 38.5800, longitude: -121.5130, capacity: 14_014, opened: 2000, surface: "Grass", roof: .open, trivia: "The smallest park in the majors during the Athletics' transitional years.")
    ]

    static func by(id: String) -> Ballpark? {
        all.first(where: { $0.id == id })
    }
}
