import Foundation
import UIKit
import GoogleSignIn

/// A lightweight Gmail message used by the ticket parser. Sendable & isolation-
/// free so it can be decoded and processed off the main actor.
nonisolated struct EmailMessage: Sendable, Hashable {
    let id: String
    let subject: String
    let from: String
    let snippet: String
    let internalDate: Date
}

nonisolated enum GmailError: LocalizedError {
    case notConfigured
    case noPresenter
    case scopeDenied
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Gmail sign-in isn't configured yet."
        case .noPresenter: return "Couldn't present the Google sign-in screen."
        case .scopeDenied: return "Read-only mail access is required to find your tickets."
        case .http(let code): return "Gmail request failed (\(code))."
        }
    }
}

/// A connected Google account after a successful, authorized sign-in.
nonisolated struct GoogleAccount: Sendable {
    let email: String
    let accessToken: String
}

/// Wraps Google Sign-In + the Gmail REST API to read ticket-related receipts.
/// Only the read-only Gmail scope is requested. Message bodies are never stored;
/// we keep just the subject/sender/snippet long enough to detect attended games.
@MainActor
final class GmailService {
    static let shared = GmailService()
    private init() {}

    private let gmailScope = "https://www.googleapis.com/auth/gmail.readonly"

    var isConfigured: Bool { AppConfig.gmailScanningEnabled }

    /// Configure the shared GIDSignIn instance. Safe to call multiple times.
    func configureIfNeeded() {
        guard let clientID = AppConfig.googleClientID else { return }
        if GIDSignIn.sharedInstance.configuration?.clientID != clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    /// Restore a previous session silently at launch, if any.
    func restorePreviousSignIn() async {
        configureIfNeeded()
        _ = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
    }

    /// Sign in (or reuse an existing session) and ensure the read-only Gmail
    /// scope has been granted, then return a fresh access token.
    func signInAndAuthorize() async throws -> GoogleAccount {
        guard AppConfig.googleClientID != nil else { throw GmailError.notConfigured }
        configureIfNeeded()
        guard let presenter = Self.topViewController() else { throw GmailError.noPresenter }

        var user: GIDGoogleUser
        if let current = GIDSignIn.sharedInstance.currentUser {
            user = current
        } else {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: [gmailScope]
            )
            user = result.user
        }

        if !(user.grantedScopes?.contains(gmailScope) ?? false) {
            let result = try await user.addScopes([gmailScope], presenting: presenter)
            user = result.user
        }
        guard user.grantedScopes?.contains(gmailScope) == true else {
            throw GmailError.scopeDenied
        }

        let refreshed = try await user.refreshTokensIfNeeded()
        return GoogleAccount(
            email: refreshed.profile?.email ?? user.profile?.email ?? "Gmail",
            accessToken: refreshed.accessToken.tokenString
        )
    }

    /// Sign out of the active Google session.
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    // MARK: - Gmail REST

    /// Search the mailbox for ticket-receipt emails from common ticketing
    /// platforms and team apps, returning lightweight message summaries.
    nonisolated func fetchTicketMessages(accessToken: String, maxMessages: Int = 80) async throws -> [EmailMessage] {
        let query = Self.searchQuery
        guard let listURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=\(maxMessages)&q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)") else {
            return []
        }
        let listData = try await Self.get(listURL, token: accessToken)
        let list = try JSONDecoder().decode(MessageList.self, from: listData)
        let ids = (list.messages ?? []).prefix(maxMessages).map(\.id)

        var messages: [EmailMessage] = []
        try await withThrowingTaskGroup(of: EmailMessage?.self) { group in
            for id in ids {
                group.addTask {
                    try? await Self.fetchMessage(id: id, token: accessToken)
                }
            }
            for try await message in group {
                if let message { messages.append(message) }
            }
        }
        return messages.sorted { $0.internalDate > $1.internalDate }
    }

    nonisolated private static func fetchMessage(id: String, token: String) async throws -> EmailMessage? {
        guard let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date") else {
            return nil
        }
        let data = try await get(url, token: token)
        let raw = try JSONDecoder().decode(RawMessage.self, from: data)
        let headers = raw.payload?.headers ?? []
        func header(_ name: String) -> String {
            headers.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value ?? ""
        }
        let internalDate: Date = {
            if let ms = Double(raw.internalDate ?? "") { return Date(timeIntervalSince1970: ms / 1000) }
            return .now
        }()
        return EmailMessage(
            id: id,
            subject: header("Subject"),
            from: header("From"),
            snippet: raw.snippet ?? "",
            internalDate: internalDate
        )
    }

    nonisolated private static func get(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw GmailError.http(http.statusCode)
        }
        return data
    }

    /// Gmail search query targeting ticket receipts across the major platforms.
    nonisolated private static var searchQuery: String {
        let senders = [
            "ticketmaster.com", "seatgeek.com", "stubhub.com", "axs.com",
            "vividseats.com", "gametime.co", "tickpick.com", "mlb.com",
            "tickets.com", "ballpark"
        ]
        let fromClause = senders.map { "from:\($0)" }.joined(separator: " OR ")
        let subjectClause = "subject:(tickets OR ticket OR \"order confirmed\" OR \"order confirmation\" OR \"your seats\" OR \"mobile tickets\")"
        return "(\(fromClause) OR \(subjectClause)) newer_than:12y"
    }

    // MARK: - Decodable DTOs

    nonisolated private struct MessageList: Decodable { let messages: [IDRef]? }
    nonisolated private struct IDRef: Decodable { let id: String }
    nonisolated private struct RawMessage: Decodable {
        let snippet: String?
        let internalDate: String?
        let payload: Payload?
        struct Payload: Decodable { let headers: [Header]? }
        struct Header: Decodable { let name: String; let value: String }
    }

    // MARK: - Presenter

    static func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController
        if let nav = root as? UINavigationController {
            return topViewController(nav.visibleViewController)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(selected)
        }
        if let presented = root?.presentedViewController {
            return topViewController(presented)
        }
        return root
    }
}
