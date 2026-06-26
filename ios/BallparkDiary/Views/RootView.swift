import SwiftUI

/// Top-level container. Gates the experience behind the inbox-scan onboarding,
/// then routes into the four main tabs (Map / Diary / Stats / Inboxes).
struct RootView: View {
    @Environment(DiaryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ZStack {
            Theme.nightGradient.ignoresSafeArea()

            if store.hasCompletedOnboarding {
                MainTabsView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.5), value: store.hasCompletedOnboarding)
    }
}

struct MainTabsView: View {
    @Environment(DiaryStore.self) private var store
    @State private var selection: Tab = .map

    enum Tab: Hashable { case map, diary, stats, inboxes, profile }

    var body: some View {
        TabView(selection: $selection) {
            MapView()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(Tab.map)

            DiaryView()
                .tabItem { Label("Diary", systemImage: "book.closed.fill") }
                .tag(Tab.diary)

            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis.ascending") }
                .tag(Tab.stats)

            InboxesView()
                .tabItem { Label("Sources", systemImage: "tray.full.fill") }
                .tag(Tab.inboxes)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(Tab.profile)
        }
        .tint(Theme.clay)
        .onChange(of: store.requestedTab) { _, newValue in
            guard let tab = newValue else { return }
            switch tab {
            case "diary": selection = .diary
            case "map": selection = .map
            case "stats": selection = .stats
            case "inboxes": selection = .inboxes
            case "profile": selection = .profile
            default: break
            }
            store.requestedTab = nil
        }
    }
}
