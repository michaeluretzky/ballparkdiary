import SwiftUI

/// The Share Extension UI. Reads whatever the user shared, extracts ticket text
/// on-device, saves it to the App Group for the main app to import, and shows a
/// quick branded confirmation. No accounts, no servers, no email access.
struct ShareView: View {
    let extensionContext: NSExtensionContext?

    @State private var phase: Phase = .working

    enum Phase: Equatable {
        case working
        case saved(count: Int, source: String)
        case nothingFound
    }

    private static let night = Color(red: 0.043, green: 0.082, blue: 0.188)
    private static let nightDeep = Color(red: 0.024, green: 0.047, blue: 0.118)
    private static let clay = Color(red: 0.878, green: 0.478, blue: 0.169)
    private static let grass = Color(red: 0.290, green: 0.486, blue: 0.227)
    private static let textPrimary = Color(red: 0.961, green: 0.953, blue: 0.937)
    private static let textSecondary = Color(red: 0.647, green: 0.690, blue: 0.788)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Self.nightDeep, Self.night],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                icon
                Text(title)
                    .font(.system(size: 22, weight: .heavy, design: .serif))
                    .foregroundStyle(Self.textPrimary)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Self.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                if phase != .working {
                    Button(action: close) {
                        Text("Done")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Self.clay)
                            )
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 6)
                }
            }
            .padding(.vertical, 40)
        }
        .task { await run() }
    }

    @ViewBuilder
    private var icon: some View {
        switch phase {
        case .working:
            ProgressView()
                .controlSize(.large)
                .tint(Self.clay)
        case .saved:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundStyle(Self.grass)
        case .nothingFound:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Self.textSecondary)
        }
    }

    private var title: String {
        switch phase {
        case .working: return "Reading your ticket…"
        case .saved: return "Added to Ballpark Diary"
        case .nothingFound: return "Saved for review"
        }
    }

    private var subtitle: String {
        switch phase {
        case .working:
            return "Scanning on your device — nothing leaves your phone."
        case let .saved(count, source):
            let noun = count == 1 ? "ticket" : "tickets"
            return "\(count) \(source) \(noun) queued. Open Ballpark Diary to see your game confirmed against the real box score."
        case .nothingFound:
            return "We couldn't read a matchup from that. Open Ballpark Diary and add it manually if needed."
        }
    }

    private func run() async {
        let extracted = await TicketContentExtractor.extract(from: extensionContext)
        let usable = extracted.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usable.isEmpty else {
            withAnimation(.snappy) { phase = .nothingFound }
            return
        }
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
        let source = usable.first?.sourceHint ?? "shared"
        withAnimation(.snappy) {
            phase = .saved(count: usable.count, source: source == "Shared ticket" ? "" : source)
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
