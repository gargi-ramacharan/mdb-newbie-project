import SwiftUI

enum AppInfo {
    static let name = "Re:live"
}

@main
struct ReliveApp: App {
    @State private var store = TripStore()

    init() {
        // Navigation titles use the same condensed face as the rest of the app's titles,
        // in every bar state (at rest, scrolled, and compact).
        if let large = UIFont(name: "DINCondensed-Bold", size: 46),
           let inline = UIFont(name: "DINCondensed-Bold", size: 24) {
            // DIN Condensed draws high in its line box, so nudge the inline title down.
            let inlineAttributes: [NSAttributedString.Key: Any] = [.font: inline, .baselineOffset: -3]
            let scrolled = UINavigationBarAppearance()
            scrolled.configureWithDefaultBackground()
            let atRest = UINavigationBarAppearance()
            atRest.configureWithTransparentBackground()
            for appearance in [scrolled, atRest] {
                appearance.titleTextAttributes = inlineAttributes
                appearance.largeTitleTextAttributes = [.font: large]
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
        }
    }
}

struct RootView: View {
    @Environment(TripStore.self) private var store
    /// Invite code from a `relive://join/CODE` link, held until you're signed in.
    @State private var incomingCode: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.me == nil {
                OnboardingView()
            } else {
                HomeView(incomingCode: $incomingCode)
            }
        }
        // Checked on open and whenever the app comes back, not in the background:
        // sign in if needed, pull the friends' latest photos, send up any of yours that are waiting.
        .task(id: "\(scenePhase)-\(store.me?.id.uuidString ?? "")") {
            guard scenePhase == .active else { return }
            if store.me != nil { await store.bootstrap() }
        }
        .onOpenURL { url in
            guard url.scheme == "relive", url.host == "join" else { return }
            incomingCode = url.lastPathComponent
        }
    }
}
