import Foundation

/// What the app needs from a server. `SupabaseBackend` is the real one; the app also runs
/// without any backend (everything stays on this phone) when none is configured.
protocol TripBackend: Sendable {
    /// Signs this phone in (reusing its earlier identity if there is one) and saves your name.
    func signIn(name: String) async throws -> Member
    /// Signs in with an Apple ID token. If this phone already has an anonymous account it's
    /// linked to the Apple ID so its trips carry over; if that Apple ID already has an account,
    /// this signs into that one instead. `name` is saved only for a brand-new profile.
    func signInWithApple(idToken: String, nonce: String, name: String?) async throws -> Member
    /// Your identity if this phone is already signed in and has a profile; `nil` otherwise.
    func restore() async throws -> Member?
    /// Creates the trip on the server and returns the invite code the server minted for it.
    func createTrip(_ trip: Trip) async throws -> String
    /// Joins the trip with this invite code and returns it, or `nil` if no trip has that code.
    func joinTrip(code: String) async throws -> Trip?
    /// Every trip you belong to, with its members and photos.
    func fetchTrips() async throws -> [Trip]
    func fetchTrip(id: UUID) async throws -> Trip?
    /// Uploads a (compressed) JPEG and records it in the album. Safe to repeat for the same photo.
    /// Returns the photo's path in the shared album.
    func uploadPhoto(_ photo: TripPhoto, tripID: UUID, jpeg: Data) async throws -> String
    func downloadPhoto(path: String) async throws -> Data

    // Owner and member actions. The server checks who's asking.
    func updateTrip(_ trip: Trip) async throws
    func removeMember(_ userID: UUID, tripID: UUID) async throws
    func transferTrip(_ tripID: UUID, to userID: UUID) async throws
    func leaveTrip(_ tripID: UUID) async throws
    func deleteTrip(_ tripID: UUID) async throws
    /// Takes one of your photos out of the album and deletes its file.
    func deletePhoto(_ photo: TripPhoto, tripID: UUID) async throws
    /// Uploads a cover JPEG under your folder of the trip and returns its path.
    func uploadCover(tripID: UUID, jpeg: Data) async throws -> String
    /// Deletes a file you uploaded (an old cover). Failures are ignored by callers.
    func deleteFile(path: String) async throws
}

enum BackendError: LocalizedError, Equatable {
    case signedOut
    case http(status: Int, message: String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .signedOut:
            return "You're signed out. Reopen the app to sign back in."
        case .http(let status, let message):
            return message.isEmpty ? "The server said no (\(status))." : message
        case .badResponse:
            return "The server sent something unexpected."
        }
    }
}

struct SupabaseConfig: Sendable, Equatable {
    var url: URL
    var anonKey: String

    /// Reads `SupabaseURL` and `SupabaseAnonKey` from Info.plist. `nil` while they're blank,
    /// which keeps the app in local-only mode.
    static func fromBundle(_ bundle: Bundle = .main) -> SupabaseConfig? {
        func value(_ key: String) -> String {
            (bundle.object(forInfoDictionaryKey: key) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        guard let url = URL(string: value("SupabaseURL")), url.scheme == "https", url.host != nil else {
            return nil
        }
        let key = value("SupabaseAnonKey")
        guard !key.isEmpty else { return nil }
        return SupabaseConfig(url: url, anonKey: key)
    }
}
