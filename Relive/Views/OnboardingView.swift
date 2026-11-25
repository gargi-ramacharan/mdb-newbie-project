import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    @Environment(TripStore.self) private var store
    @State private var name = ""
    @State private var signingIn = false
    @State private var problem: String?
    /// The nonce for the Apple request in flight.
    @State private var nonce = AppleSignIn.makeNonce()
    @State private var showingCredits = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Wordmark(size: 88, color: Theme.thermal)
                Text("Everyone's trip photos in one album, on one map.")
                    .font(.title3)
                    .foregroundStyle(Theme.thermal.opacity(0.85))
                // The postcards' licenses ask for their photographers to be named.
                Button("Photo credits") { showingCredits = true }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.thermal.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 56)

            // Postcards drift through the gap, tucked under the top of the form card.
            // Drawn over the gap rather than laid out in it, so it never squeezes the text or form.
            Spacer(minLength: 24)
                .overlay(alignment: .bottom) {
                    PlaceCarousel()
                        .frame(maxHeight: 300)
                        .padding(.top, 12)
                        .padding(.bottom, -36)
                }

            // The form sits on a white card rising from the bottom edge.
            VStack(alignment: .leading, spacing: 10) {
                Text("Your name")
                    .font(.subheadline.weight(.semibold))
                TextField("", text: $name, prompt: Text("First and last").foregroundStyle(Theme.ink.opacity(0.35)))
                    .font(Theme.title(30))
                    .tracking(-0.6)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.go)
                    .onSubmit { start() }
                Rectangle()
                    .frame(height: 1.5)
                if let problem {
                    Text(problem)
                        .font(.footnote.weight(.semibold))
                } else {
                    Text(store.hasBackend
                         ? "Shown to friends on your trips. Leave it blank to use the name on your Apple account."
                         : "It's printed on every trip receipt you share.")
                        .font(.footnote)
                        .opacity(0.7)
                }
                if store.hasBackend {
                    appleButton
                    Button("Continue without an account") { start() }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .opacity(trimmedName.isEmpty ? 0.35 : 1)
                        .disabled(trimmedName.isEmpty || signingIn)
                } else {
                    startButton
                }
            }
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 20)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                    .fill(Theme.thermal)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(Theme.ink.ignoresSafeArea())
        .sheet(isPresented: $showingCredits) { PhotoCreditsView() }
    }

    /// Sign in with Apple: one tap, works on every device, and shares only a name.
    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            nonce = AppleSignIn.makeNonce()
            AppleSignIn.configure(request, nonce: nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                Task { await finishApple(authorization) }
            case .failure(let error):
                if !AppleSignIn.wasCancelled(error) { problem = error.localizedDescription }
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 54)
        .clipShape(Capsule())
        .disabled(signingIn)
        .overlay { if signingIn { ProgressView() } }
        .padding(.top, 10)
    }

    private var startButton: some View {
                Button {
                    start()
                } label: {
                    Group {
                        if signingIn {
                            ProgressView().tint(.white)
                        } else {
                            Text("Start")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.ink, in: Capsule())
                }
                .opacity(trimmedName.isEmpty ? 0.35 : 1)
                .disabled(trimmedName.isEmpty || signingIn)
                .padding(.top, 10)
    }

    private func finishApple(_ authorization: ASAuthorization) async {
        signingIn = true
        problem = nil
        defer { signingIn = false }
        do {
            let credential = try AppleSignIn.credential(from: authorization, nonce: nonce)
            // A name typed here wins over the one Apple shares.
            let chosen = trimmedName.isEmpty ? credential.name : trimmedName
            try await store.signInWithApple(idToken: credential.idToken, nonce: credential.nonce, name: chosen)
        } catch {
            problem = error is URLError
                ? "Couldn't reach the server. Check your connection and try again."
                : error.localizedDescription
        }
    }

    private func start() {
        guard !trimmedName.isEmpty, !signingIn else { return }
        signingIn = true
        problem = nil
        Task {
            do {
                try await store.signIn(name: trimmedName)
            } catch {
                problem = error is URLError
                    ? "Couldn't reach the server. Check your connection and try again."
                    : error.localizedDescription
            }
            signingIn = false
        }
    }
}
