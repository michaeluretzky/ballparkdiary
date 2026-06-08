import SwiftUI
import GoogleSignIn

@main
struct BallparkDiaryApp: App {
    @State private var store = DiaryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.clay)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .task {
                    await GmailService.shared.restorePreviousSignIn()
                }
        }
    }
}
