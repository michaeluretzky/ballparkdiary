import Foundation

/// A ticket candidate parsed server-side from a forwarded email. Mirrors the
/// backend `DetectedCandidate` shape and maps to the same `DetectedGame` the
/// on-device MLB confirmation pipeline already understands. Isolation-free so
/// it can be decoded off the main actor.
nonisolated struct ForwardedCandidate: Decodable, Sendable {
    let id: String
    let teamMlbId: Int
    let opponentMlbId: Int?
    let candidateDates: [String]
    let source: String
    let subject: String

    var detectedGame: DetectedGame {
        let formatter = ISO8601DateFormatter()
        let dates = candidateDates.compactMap { formatter.date(from: $0) }
        return DetectedGame(
            candidateDates: dates.isEmpty ? [.now] : dates,
            teamMlbId: teamMlbId,
            opponentMlbId: opponentMlbId,
            source: source,
            subject: subject
        )
    }
}

/// Talks to the Ballpark Diary backend that receives forwarded ticket emails.
/// The user forwards receipts to `<token>@<domain>`; the backend parses them
/// and queues candidates which we fetch, confirm against the MLB schedule, and
/// acknowledge. No mailbox access — and therefore no Google verification.
nonisolated struct ForwardingService: Sendable {
    static let shared = ForwardingService()

    struct Registration: Sendable {
        let configured: Bool
        let address: String?
    }

    private var baseURL: URL? {
        let raw = Config.EXPO_PUBLIC_RORK_FUNCTIONS_URL.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    var isBackendConfigured: Bool { baseURL != nil }

    /// Confirm the forwarding address for a token (the backend appends the
    /// configured inbound domain).
    func register(token: String) async throws -> Registration {
        guard let base = baseURL else { return Registration(configured: false, address: nil) }
        let url = base.appendingPathComponent("register")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let finalURL = comps?.url else { return Registration(configured: false, address: nil) }
        let data = try await get(finalURL)
        let dto = try JSONDecoder().decode(RegisterDTO.self, from: data)
        return Registration(configured: dto.configured, address: dto.address)
    }

    /// Fetch ticket candidates parsed from emails forwarded to this token.
    func pending(token: String) async throws -> [ForwardedCandidate] {
        guard let base = baseURL else { return [] }
        let url = base.appendingPathComponent("pending")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let finalURL = comps?.url else { return [] }
        let data = try await get(finalURL)
        return try JSONDecoder().decode(PendingDTO.self, from: data).candidates
    }

    /// Mark candidates as imported so they aren't returned again.
    func acknowledge(token: String, ids: [String]) async {
        guard let base = baseURL, !ids.isEmpty else { return }
        let url = base.appendingPathComponent("ack")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let finalURL = comps?.url else { return }
        var request = URLRequest(url: finalURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["ids": ids])
        _ = try? await URLSession.shared.data(for: request)
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private struct RegisterDTO: Decodable { let configured: Bool; let address: String? }
    private struct PendingDTO: Decodable { let candidates: [ForwardedCandidate] }
}
