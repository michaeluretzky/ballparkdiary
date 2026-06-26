import SwiftUI

/// The Share Extension UI. Reads whatever the user shared, extracts ticket text
/// on-device, saves it to the App Group for the main app to import, and shows a
/// branded confirmation. When the user taps "Open Diary" the main app launches
/// via a custom URL scheme and imports the ticket automatically.
struct ShareView: View {
    let extensionContext: NSExtensionContext?

    @State private var phase: Phase = .working
    @State private var savedCount: Int = 0
    @State private var matchupSummary: String = ""
    @State private var pulse: Bool = false

    // Match the main app's Theme — no hardcoded colors.
    private static let nightDeep = Color(red: 0.024, green: 0.047, blue: 0.118)
    private static let night     = Color(red: 0.043, green: 0.082, blue: 0.188)
    private static let clay      = Color(red: 0.878, green: 0.478, blue: 0.169)
    private static let lights    = Color(red: 0.961, green: 0.784, blue: 0.259)
    private static let grass     = Color(red: 0.290, green: 0.486, blue: 0.227)
    private static let chalk     = Color(red: 0.961, green: 0.953, blue: 0.937)
    private static let muted     = Color(red: 0.439, green: 0.490, blue: 0.604)

    enum Phase: Equatable {
        case working
        case saved(count: Int)
        case nothingFound
    }

    var body: some View {
        ZStack {
            // Night stadium background
            LinearGradient(
                colors: [Self.nightDeep, Self.night],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Subtle vignette
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.35)],
                center: .center,
                startRadius: 80,
                endRadius: 400
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon area
                iconView
                    .padding(.bottom, 28)

                // Title
                Text(titleText)
                    .font(.system(size: 22, weight: .black, design: .serif))
                    .foregroundStyle(Self.chalk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // Subtitle
                Text(subtitleText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Self.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 10)

                // Matchup summary (when we have it)
                if !matchupSummary.isEmpty, case .saved = phase {
                    Text(matchupSummary)
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundStyle(Self.chalk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .padding(.horizontal, 32)
                }

                // Action buttons
                if phase != .working {
                    VStack(spacing: 12) {
                        Button(action: openApp) {
                            HStack(spacing: 8) {
                                Image(systemName: "book.closed.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Open Diary")
                                    .font(.system(size: 17, weight: .heavy))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Self.clay)
                            )
                        }

                        Button(action: close) {
                            Text("Close")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Self.muted)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                }

                Spacer()
            }
            .padding(.vertical, 40)
        }
        .task { await run() }
    }

    // MARK: - Icon

    @ViewBuilder
    private var iconView: some View {
        switch phase {
        case .working:
            ZStack {
                Circle()
                    .fill(Self.clay.opacity(0.08))
                    .frame(width: 90, height: 90)
                    .scaleEffect(pulse ? 1.12 : 0.88)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }

                Circle()
                    .strokeBorder(Self.clay.opacity(0.25), lineWidth: 2)
                    .frame(width: 90, height: 90)

                BaseballMark(size: 40)
                    .shadow(color: Self.clay.opacity(0.4), radius: 10)
            }
        case .saved:
            ZStack {
                Circle()
                    .fill(Self.grass.opacity(0.10))
                    .frame(width: 90, height: 90)

                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Self.grass, Self.lights, Self.grass],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 90, height: 90)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Self.grass)
            }
        case .nothingFound:
            ZStack {
                Circle()
                    .fill(Self.muted.opacity(0.08))
                    .frame(width: 90, height: 90)

                Circle()
                    .strokeBorder(Self.muted.opacity(0.2), lineWidth: 2)
                    .frame(width: 90, height: 90)

                Image(systemName: "ticket")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Self.muted)
            }
        }
    }

    // MARK: - Copy

    private var titleText: String {
        switch phase {
        case .working: return "Reading your ticket…"
        case .saved(let count): return count == 1 ? "Ticket queued" : "\(count) tickets queued"
        case .nothingFound: return "No matchup found"
        }
    }

    private var subtitleText: String {
        switch phase {
        case .working:
            return "Everything stays on your device — no accounts, no uploads."
        case .saved:
            return "Open your diary to confirm against the real box score."
        case .nothingFound:
            return "Couldn't detect a matchup. You can add this one by hand."
        }
    }

    // MARK: - Actions

    private func run() async {
        let extracted = await TicketContentExtractor.extract(from: extensionContext)
        let usable = extracted.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usable.isEmpty else {
            withAnimation(.snappy) { phase = .nothingFound }
            return
        }

        // Quick local parse for the matchup preview
        matchupSummary = matchupFrom(usable.first?.text ?? "")

        for item in usable {
            SharedTicketStore.append(
                SharedTicketPayload(
                    id: UUID().uuidString,
                    text: item.text,
                    sourceHint: item.sourceHint,
                    receivedAt: .now
                )
            )
        }
        savedCount = usable.count
        withAnimation(.snappy) {
            phase = .saved(count: usable.count)
        }

        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif

        // Auto-open the main app after a short confirmation pause.
        try? await Task.sleep(for: .seconds(1.2))
        openApp()
    }

    /// Quick visual summary of detected teams for the confirmation screen.
    private func matchupFrom(_ text: String) -> String {
        // Lightweight team detection — same keywords as the full parser.
        let lower = text.lowercased()
        let keywords: [(String, String)] = [
            ("arizona", "ARI"), ("dbacks", "ARI"), ("d-backs", "ARI"),
            ("atlanta", "ATL"), ("braves", "ATL"),
            ("baltimore", "BAL"), ("orioles", "BAL"),
            ("boston", "BOS"), ("red sox", "BOS"),
            ("cubs", "CHC"), ("chicago cubs", "CHC"),
            ("white sox", "CHW"), ("chicago white sox", "CHW"),
            ("cincinnati", "CIN"), ("reds", "CIN"),
            ("cleveland", "CLE"), ("guardians", "CLE"),
            ("colorado", "COL"), ("rockies", "COL"),
            ("detroit", "DET"), ("tigers", "DET"),
            ("houston", "HOU"), ("astros", "HOU"),
            ("kansas city", "KC"), ("royals", "KC"),
            ("angels", "LAA"), ("los angeles angels", "LAA"),
            ("dodgers", "LAD"), ("los angeles dodgers", "LAD"),
            ("miami", "MIA"), ("marlins", "MIA"),
            ("milwaukee", "MIL"), ("brewers", "MIL"),
            ("minnesota", "MIN"), ("twins", "MIN"),
            ("mets", "NYM"), ("new york mets", "NYM"),
            ("yankees", "NYY"), ("new york yankees", "NYY"),
            ("oakland", "OAK"), ("athletics", "OAK"), ("a's", "OAK"),
            ("philadelphia", "PHI"), ("phillies", "PHI"),
            ("pittsburgh", "PIT"), ("pirates", "PIT"),
            ("padres", "SD"), ("san diego", "SD"),
            ("giants", "SF"), ("san francisco", "SF"),
            ("seattle", "SEA"), ("mariners", "SEA"),
            ("cardinals", "STL"), ("st. louis", "STL"), ("st louis", "STL"),
            ("rays", "TB"), ("tampa bay", "TB"),
            ("texas", "TEX"), ("rangers", "TEX"),
            ("blue jays", "TOR"), ("toronto", "TOR"),
            ("nationals", "WSH"), ("washington", "WSH"),
        ]
        var found: [(idx: Int, abbr: String)] = []
        let ns = lower as NSString
        for (needle, abbr) in keywords {
            // Word-boundary match so "helmets" doesn't hit "mets", "hundreds"
            // doesn't hit "reds", etc. — mirrors the main parser's strictness.
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: needle))\\b"
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                let match = regex.firstMatch(in: lower, range: NSRange(location: 0, length: ns.length))
            else { continue }
            found.append((match.range.location, abbr))
        }
        found.sort { $0.idx < $1.idx }
        let unique = found.reduce(into: [String]()) { acc, item in
            if !acc.contains(item.abbr) { acc.append(item.abbr) }
        }
        guard unique.count >= 2 else { return "" }
        return "\(unique.first!) vs \(unique.last!)"
    }

    /// Opens the main Ballpark Diary app via its custom URL scheme.
    /// Dismisses the extension afterward so the user lands in the main app.
    private func openApp() {
        guard let url = URL(string: "ballparkdiary://import") else {
            close()
            return
        }
        // The completion handler is critical — without it, open(_:completionHandler:)
        // can silently fail on some iOS versions. Dismiss the extension afterward.
        extensionContext?.open(url) { [extensionContext] _ in
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

/// Quick baseball icon for the share extension — matches the main app's mark.
private struct BaseballMark: View {
    let size: CGFloat
    private static let clay  = Color(red: 0.878, green: 0.478, blue: 0.169)
    private static let chalk = Color(red: 0.961, green: 0.953, blue: 0.937)

    var body: some View {
        ZStack {
            Circle()
                .fill(Self.chalk)
                .frame(width: size, height: size)
            // Seams
            Path { path in
                let s = size * 0.3
                path.move(to: CGPoint(x: size * 0.5 - s, y: 0))
                path.addQuadCurve(to: CGPoint(x: size * 0.5 + s, y: size),
                                 control: CGPoint(x: size * 0.5 - s * 0.6, y: size * 0.5))
                path.move(to: CGPoint(x: size * 0.5 + s, y: 0))
                path.addQuadCurve(to: CGPoint(x: size * 0.5 - s, y: size),
                                 control: CGPoint(x: size * 0.5 + s * 0.6, y: size * 0.5))
            }
            .stroke(Self.clay, lineWidth: size * 0.04)
        }
    }
}
