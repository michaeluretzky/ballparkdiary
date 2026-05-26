import SwiftUI

@main
struct BallparkDiaryApp: App {
    @State private var store = DiaryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.clay)
        }
    }
}
