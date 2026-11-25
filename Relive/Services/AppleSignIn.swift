import AuthenticationServices
import CryptoKit
import UIKit

/// Sign in with Apple. Apple gives the app a signed ID token that Supabase checks, a stable
/// user id private to this app, and the person's name the first time only. The app never
/// sees their Apple ID, password or phone number.
enum AppleSignIn {
    struct Credential {
        var idToken: String
        /// The raw nonce. Apple gets its SHA-256; Supabase gets this, and checks they match.
        var nonce: String
        /// Only sent the first time someone signs in to this app with Apple.
        var name: String?
    }

    enum Failure: LocalizedError {
        case noToken

        var errorDescription: String? { "Apple didn't send a sign-in token. Try again." }
    }

    /// A random string that ties one Apple request to one Supabase sign-in, so a stolen
    /// token can't be replayed.
    static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Asks for the name only; the app has no use for the email.
    static func configure(_ request: ASAuthorizationAppleIDRequest, nonce: String) {
        request.requestedScopes = [.fullName]
        request.nonce = sha256(nonce)
    }

    static func credential(from authorization: ASAuthorization, nonce: String) throws -> Credential {
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = apple.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else { throw Failure.noToken }
        var name: String?
        if let parts = apple.fullName {
            let formatted = PersonNameComponentsFormatter().string(from: parts)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            name = formatted.isEmpty ? nil : formatted
        }
        return Credential(idToken: token, nonce: nonce, name: name)
    }

    /// True when someone dismissed the Apple sheet, which isn't worth an error message.
    static func wasCancelled(_ error: Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }

    /// Runs the Apple sheet from anywhere (a menu item, say), outside the Apple button.
    @MainActor
    static func request() async throws -> Credential {
        try await Runner().run()
    }

    @MainActor
    private final class Runner: NSObject, ASAuthorizationControllerDelegate,
                                ASAuthorizationControllerPresentationContextProviding {
        private var continuation: CheckedContinuation<Credential, Error>?
        private let nonce = AppleSignIn.makeNonce()
        private var keepAlive: Runner?

        func run() async throws -> Credential {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                keepAlive = self
                let request = ASAuthorizationAppleIDProvider().createRequest()
                AppleSignIn.configure(request, nonce: nonce)
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }
        }

        nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            MainActor.assumeIsolated {
                UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                    .first ?? ASPresentationAnchor()
            }
        }

        nonisolated func authorizationController(controller: ASAuthorizationController,
                                                 didCompleteWithAuthorization authorization: ASAuthorization) {
            MainActor.assumeIsolated {
                finish { try AppleSignIn.credential(from: authorization, nonce: nonce) }
            }
        }

        nonisolated func authorizationController(controller: ASAuthorizationController,
                                                 didCompleteWithError error: Error) {
            MainActor.assumeIsolated {
                finish { throw error }
            }
        }

        private func finish(_ result: () throws -> Credential) {
            continuation?.resume(with: Result { try result() })
            continuation = nil
            keepAlive = nil
        }
    }
}
