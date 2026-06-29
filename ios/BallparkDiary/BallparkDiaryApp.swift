import SwiftUI
import RevenueCat

@main
struct BallparkDiaryApp: App {
    @State private var store = DiaryStore()
    @State private var storeKit = StoreViewModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if canImport(UIKit)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(Theme.nightDeep.opacity(0.95))
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
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
