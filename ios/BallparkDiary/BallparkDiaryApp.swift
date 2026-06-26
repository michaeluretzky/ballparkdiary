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
                    // Opened from share extension — import any shared tickets,
                    // then switch to Diary so the user can verify the new game.
                    Task {
                        await store.refresh(force: true)
                        store.requestedTab = "diary"
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await store.refresh() }
                    }
                }
        }
    }
}
