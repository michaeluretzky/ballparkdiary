import Foundation
import SwiftUI

/// The mail provider a user can connect to scan for ticket receipts.
enum InboxProvider: String, CaseIterable, Hashable, Identifiable, Codable {
    case gmail
    case icloud
    case outlook
    case yahoo
    case other
    case manual

    var id: String { rawValue }

    /// Providers shown in the connect/login UI. Manual is excluded — it has
    /// its own dedicated CTA because it doesn't involve scanning an inbox.
    static var connectable: [InboxProvider] {
        allCases.filter { $0 != .manual }
    }

    var name: String {
        switch self {
        case .gmail: return "Gmail"
        case .icloud: return "iCloud Mail"
        case .outlook: return "Outlook"
        case .yahoo: return "Yahoo Mail"
        case .other: return "Other email"
        case .manual: return "Manual entries"
        }
    }

    var symbol: String {
        switch self {
        case .gmail: return "envelope.fill"
        case .icloud: return "icloud.fill"
        case .outlook: return "tray.fill"
        case .yahoo: return "envelope.open.fill"
        case .other: return "at"
        case .manual: return "square.and.pencil"
        }
    }

    var brandColor: Color {
        switch self {
        case .gmail: return Color(hex: "#EA4335")
        case .icloud: return Color(hex: "#3FA9F5")
        case .outlook: return Color(hex: "#0072C6")
        case .yahoo: return Color(hex: "#6001D2")
        case .other: return Color(hex: "#E07A2B")
        case .manual: return Color(hex: "#F5C842")
        }
    }

    var domain: String {
        switch self {
        case .gmail: return "gmail.com"
        case .icloud: return "icloud.com"
        case .outlook: return "outlook.com"
        case .yahoo: return "yahoo.com"
        case .other: return "email.com"
        case .manual: return "manual"
        }
    }

    var blurb: String {
        switch self {
        case .other: return "Any IMAP provider · Fastmail, ProtonMail, work email"
        case .manual: return "For games older than digital tickets"
        default: return name
        }
    }
}

/// A single connected inbox. Each one contributes its attended games into the
/// shared diary, but stats are always computed across all connected inboxes.
struct ConnectedInbox: Identifiable, Hashable, Codable {
    let id: UUID
    var email: String
    let provider: InboxProvider
    var ticketsFound: Int
    let connectedAt: Date
}
