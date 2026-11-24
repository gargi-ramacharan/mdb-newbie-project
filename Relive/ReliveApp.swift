import SwiftUI

enum AppInfo {
    static let name = "Re:live"
}

@main
struct ReliveApp: App {
    @State private var store = TripStore()

    init() {
        // Navigation titles in ink, semibold and set tight like the app's other titles,
        // in every bar state (at rest, scrolled, and compact).
        do {
            let large = UIFont.systemFont(ofSize: 34, weight: .semibold)
            let inline = UIFont.systemFont(ofSize: 17, weight: .semibold)
            let ink = UIColor(Theme.ink)
            let inlineAttributes: [NSAttributedString.Key: Any] = [.font: inline, .foregroundColor: ink]
            let scrolled = UINavigationBarAppearance()
            scrolled.configureWithOpaqueBackground()
            scrolled.backgroundColor = UIColor(Theme.paper)
            scrolled.shadowColor = ink.withAlphaComponent(0.08)
            let atRest = UINavigationBarAppearance()
            atRest.configureWithTransparentBackground()
            for appearance in [scrolled, atRest] {
                appearance.titleTextAttributes = inlineAttributes
                appearance.largeTitleTextAttributes = [.font: large, .foregroundColor: ink]
            }
            let bar = UINavigationBar.appearance()
            bar.standardAppearance = scrolled
            bar.compactAppearance = scrolled
            bar.scrollEdgeAppearance = atRest
            bar.compactScrollEdgeAppearance = atRest
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                // Set explicitly: customising the navigation bar at launch makes UIKit
                // fall back to system blue for the app-wide accent.
                .tint(Color("AccentColor"))
                // Paper is always light.
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @Environment(TripStore.self) private var store
    /// Invite code from a `relive://join/CODE` link, held until you're signed in.
    @State private var incomingCode: String?

    var body: some View {
        Group {
            if store.me == nil {
                OnboardingView()
            } else {
                HomeView(incomingCode: $incomingCode)
            }
        }
        .onOpenURL { url in
            guard url.scheme == "relive", url.host == "join" else { return }
            incomingCode = url.lastPathComponent
        }
    }
}
