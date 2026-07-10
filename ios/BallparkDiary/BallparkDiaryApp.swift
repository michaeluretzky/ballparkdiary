import SwiftUI
import RevenueCat

@main
struct BallparkDiaryApp: App {
    @State private var store = DiaryStore()
    @State private var storeKit = StoreViewModel()
    @State private var location = LocationService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if canImport(UIKit)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(Theme.nightDeep.opacity(0.95))
        // Slab-serif nav titles — falls back to system if the font is missing.
        var largeTitleAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white]
        var titleAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white]
        if let slabLarge = UIFont(name: "ZillaSlab-Bold", size: 32) {
            largeTitleAttributes[.font] = slabLarge
        }
        if let slabInline = UIFont(name: "ZillaSlab-Bold", size: 18) {
            titleAttributes[.font] = slabInline
        }
        appearance.largeTitleTextAttributes = largeTitleAttributes
        appearance.titleTextAttributes = titleAttributes
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        #endif

        #if DEBUG
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: Config.EXPO_PUBLIC_REVENUECAT_TEST_API_KEY)
        #else
        Purchases.configure(withAPIKey: Config.EXPO_PUBLIC_REVENUECAT_IOS_API_KEY)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(storeKit)
                .environment(location)
                .preferredColorScheme(.dark)
                .tint(Theme.clay)
                .task {
                    await store.refresh()
                }
                .onOpenURL { _ in
                    // Opened from share extension — switch to Diary immediately
                    // and import shared tickets with a brief delay to ensure
                    // App Group sync completes from the extension.
                    store.requestedTab = "diary"
                    Task {
                        // Small delay lets the share extension fully flush to App Group
                        try? await Task.sleep(for: .seconds(0.6))
                        let count = await store.importSharedTickets()
                        // If still nothing, retry once after a longer delay
                        if count == 0 {
                            try? await Task.sleep(for: .seconds(1.5))
                            _ = await store.importSharedTickets()
                        }
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Always drain any tickets the user shared while the app
                        // was backgrounded — the share extension can't reliably
                        // launch us, so importing on every foreground guarantees
                        // a shared screenshot/photo shows up the next time the
                        // user opens the app. Bypasses the refresh throttle.
                        Task {
                            let count = await store.importSharedTickets()
                            if count > 0 { store.requestedTab = "diary" }
                            await store.refresh()
                        }
                    }
                }
        }
    }
}
