import SwiftUI
import RevenueCat

@main
struct BallparkDiaryApp: App {
    @State private var store = DiaryStore()
    @State private var storeKit = StoreViewModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
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
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await store.refresh() }
                    }
                }
        }
    }
}
