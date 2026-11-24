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
    /// Invite code from an invite link, held until you're signed in.
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
        .actionProblemAlert()
        // Invite links: relive://join/CODE, and https://<invite domain>/join/CODE once a
        // domain is set up (universal links arrive through both of these).
        .onOpenURL { url in
            if let code = InviteLink.code(in: url, host: InviteLink.configuredHost) { incomingCode = code }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL, let code = InviteLink.code(in: url, host: InviteLink.configuredHost) {
                incomingCode = code
            }
        }
    }
}
