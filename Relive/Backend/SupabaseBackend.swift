import Foundation
import Security

struct Session: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: UUID
}

/// Where the sign-in session is kept between launches.
protocol SessionStorage: Sendable {
    func load() -> Session?
    func save(_ session: Session?)
}

/// Keeps the session in the Keychain, so a reinstall keeps your identity (and your trips).
struct KeychainSessionStorage: SessionStorage {
    var service = "com.relive.app.session"
    private let account = "supabase"

    private var match: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> Session? {
        var query = match
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    func save(_ session: Session?) {
        SecItemDelete(match as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var add = match
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Talks to Supabase over plain HTTPS (GoTrue for sign-in, PostgREST for tables and functions,
/// Storage for photos), so the app needs no third-party package.
actor SupabaseBackend: TripBackend {
    private let config: SupabaseConfig
    private let urlSession: URLSession
    private let storage: SessionStorage
    private var session: Session?
    private var refreshing: Task<Session, Error>?

    static let bucket = "trip-photos"

    init(config: SupabaseConfig, urlSession: URLSession = .shared, storage: SessionStorage = KeychainSessionStorage()) {
        self.config = config
        self.urlSession = urlSession
        self.storage = storage
        self.session = storage.load()
    }

    // MARK: Sign-in

    func restore() async throws -> Member? {
        guard session != nil else { return nil }
        do {
            let rows: [Wire.ProfileRow] = try await select("profiles", [
                URLQueryItem(name: "select", value: "id,name"),
                URLQueryItem(name: "id", value: "eq.\(try userID().uuidString.lowercased())"),
            ])
            guard let row = rows.first else { return nil }
            return Member(id: row.id, name: row.name, copy: 0)
        } catch BackendError.signedOut {
            return nil
        }
    }

    func signIn(name: String) async throws -> Member {
        if let existing = try await restore() {
            if existing.name != name { try await saveProfile(id: existing.id, name: name) }
            return Member(id: existing.id, name: name, copy: 0)
        }
        if session == nil {
            let fresh: AuthResponse = try decode(
                try await send("POST", "/auth/v1/signup", body: Data("{}".utf8), auth: false)
            )
            setSession(fresh.session())
        }
        let id = try userID()
        try await saveProfile(id: id, name: name)
        return Member(id: id, name: name, copy: 0)
    }

    func signInWithApple(idToken: String, nonce: String, name: String?) async throws -> Member {
        var linked = false
        if session != nil {
            // Attach the Apple ID to this phone's anonymous account, so its trips carry over.
            // Needs "Allow manual linking" on the project. If the Apple ID already belongs to
            // another account (say, from another phone), the server refuses and we sign into it.
            do {
                let data = try await send(
                    "POST", "/auth/v1/token",
                    query: [URLQueryItem(name: "grant_type", value: "id_token")],
                    body: try Wire.encoder.encode(Wire.AppleTokenBody(id_token: idToken, nonce: nonce, link_identity: true))
                )
                if let fresh = try? Wire.decoder.decode(AuthResponse.self, from: data) {
                    setSession(fresh.session())
                }
                linked = true
            } catch BackendError.http(let status, _) where (400..<500).contains(status) && status != 401 {
                linked = false
            } catch BackendError.signedOut {
                linked = false
            }
        }
        if !linked {
            let data = try await perform(
                "POST", "/auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "id_token")],
                body: try Wire.encoder.encode(Wire.AppleTokenBody(id_token: idToken, nonce: nonce)),
                contentType: "application/json", headers: [:], token: config.anonKey
            )
            setSession(try (decode(data) as AuthResponse).session())
        }
        if let existing = try await restore() { return existing }
        let id = try userID()
        let chosen = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (chosen?.isEmpty == false ? chosen : nil) ?? "Traveler"
        try await saveProfile(id: id, name: finalName)
        return Member(id: id, name: finalName, copy: 0)
    }

    private func saveProfile(id: UUID, name: String) async throws {
        _ = try await send(
            "POST", "/rest/v1/profiles",
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            body: try Wire.encoder.encode(Wire.ProfileRow(id: id, name: name)),
            headers: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    // MARK: Trips

    func createTrip(_ trip: Trip) async throws -> String {
        let args = Wire.CreateTripArgs(p_id: trip.id, p_name: trip.name, p_start: trip.startDate,
                                       p_end: trip.endDate, p_places: trip.places)
        let data = try await send("POST", "/rest/v1/rpc/create_trip", body: try Wire.encoder.encode(args))
        return try decode(data)
    }

    func joinTrip(code: String) async throws -> Trip? {
        let args = Wire.JoinTripArgs(p_code: code)
        let data = try await send("POST", "/rest/v1/rpc/join_trip", body: try Wire.encoder.encode(args))
        let joined: UUID? = try decode(data)
        guard let id = joined else { return nil }
        return try await fetchTrip(id: id)
    }

    func fetchTrips() async throws -> [Trip] {
        let rows: [Wire.TripRow] = try await select("trips", [
            URLQueryItem(name: "select", value: Wire.tripSelect),
            URLQueryItem(name: "order", value: "start_date.desc"),
        ])
        return rows.map { $0.makeTrip() }
    }

    func fetchTrip(id: UUID) async throws -> Trip? {
        let rows: [Wire.TripRow] = try await select("trips", [
            URLQueryItem(name: "select", value: Wire.tripSelect),
            URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())"),
        ])
        return rows.first?.makeTrip()
    }

    // MARK: Photos

    func uploadPhoto(_ photo: TripPhoto, tripID: UUID, jpeg: Data) async throws -> String {
        let path = AlbumPath.path(tripID: tripID, ownerID: photo.ownerID, photoID: photo.id)
        // The file first, then the row that makes it show up in everyone's album. If the app
        // dies in between, the next attempt overwrites the file and adds the row.
        _ = try await send(
            "POST", "/storage/v1/object/\(Self.bucket)/\(path)",
            body: jpeg, contentType: "image/jpeg", headers: ["x-upsert": "true"]
        )
        _ = try await send(
            "POST", "/rest/v1/photos",
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            body: try Wire.encoder.encode(Wire.PhotoRow(photo: photo, tripID: tripID, path: path)),
            headers: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
        return path
    }

    func downloadPhoto(path: String) async throws -> Data {
        try await send("GET", "/storage/v1/object/authenticated/\(Self.bucket)/\(path)", contentType: nil)
    }

    // MARK: Owner and member actions

    func updateTrip(_ trip: Trip) async throws {
        let args = Wire.UpdateTripArgs(
            p_id: trip.id, p_name: trip.name, p_start: trip.startDate, p_end: trip.endDate,
            p_places: trip.places, p_cover_photo_id: trip.coverPhotoID, p_cover_path: trip.coverPath
        )
        _ = try await send("POST", "/rest/v1/rpc/update_trip", body: try Wire.encoder.encode(args))
    }

    func removeMember(_ userID: UUID, tripID: UUID) async throws {
        _ = try await send("POST", "/rest/v1/rpc/remove_member",
                           body: try Wire.encoder.encode(Wire.TripMemberArgs(p_trip: tripID, p_user: userID)))
    }

    func transferTrip(_ tripID: UUID, to userID: UUID) async throws {
        _ = try await send("POST", "/rest/v1/rpc/transfer_trip",
                           body: try Wire.encoder.encode(Wire.TripMemberArgs(p_trip: tripID, p_user: userID)))
    }

    func leaveTrip(_ tripID: UUID) async throws {
        _ = try await send("POST", "/rest/v1/rpc/leave_trip",
                           body: try Wire.encoder.encode(Wire.TripArg(p_trip: tripID)))
    }

    func deleteTrip(_ tripID: UUID) async throws {
        _ = try await send("POST", "/rest/v1/rpc/delete_trip",
                           body: try Wire.encoder.encode(Wire.TripArg(p_trip: tripID)))
    }

    func deletePhoto(_ photo: TripPhoto, tripID: UUID) async throws {
        _ = try await send(
            "DELETE", "/rest/v1/photos",
            query: [URLQueryItem(name: "id", value: "eq.\(photo.id.uuidString.lowercased())")],
            contentType: nil
        )
        if let path = photo.remotePath { try? await deleteFile(path: path) }
    }

    func uploadCover(tripID: UUID, jpeg: Data) async throws -> String {
        let path = "\(tripID.uuidString.lowercased())/\(try userID().uuidString.lowercased())/cover-\(UUID().uuidString.lowercased()).jpg"
        _ = try await send("POST", "/storage/v1/object/\(Self.bucket)/\(path)",
                           body: jpeg, contentType: "image/jpeg", headers: ["x-upsert": "true"])
        return path
    }

    func deleteFile(path: String) async throws {
        _ = try await send("DELETE", "/storage/v1/object/\(Self.bucket)/\(path)", contentType: nil)
    }

    // MARK: HTTP

    private func select<T: Decodable>(_ table: String, _ query: [URLQueryItem]) async throws -> [T] {
        try decode(try await send("GET", "/rest/v1/\(table)", query: query, contentType: nil))
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try Wire.decoder.decode(T.self, from: data)
        } catch {
            throw BackendError.badResponse
        }
    }

    private func userID() throws -> UUID {
        guard let session else { throw BackendError.signedOut }
        return session.userID
    }

    /// Sends a request as the signed-in user, refreshing the token first if it is about to expire
    /// and once more if the server says it already has.
    private func send(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
        contentType: String? = "application/json", headers: [String: String] = [:], auth: Bool = true
    ) async throws -> Data {
        var retried = false
        while true {
            let token = auth ? try await validToken() : config.anonKey
            do {
                return try await perform(method, path, query: query, body: body, contentType: contentType,
                                         headers: headers, token: token)
            } catch BackendError.http(let status, _) where status == 401 && auth && !retried {
                retried = true
                _ = try await refreshSession()
            }
        }
    }

    private func perform(
        _ method: String, _ path: String, query: [URLQueryItem], body: Data?,
        contentType: String?, headers: [String: String], token: String
    ) async throws -> Data {
        guard var components = URLComponents(url: config.url, resolvingAgainstBaseURL: false) else {
            throw BackendError.badResponse
        }
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw BackendError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        // Signed-in requests carry the user's token. Before sign-in the apikey header is enough,
        // and a new-style publishable key (sb_publishable_…) isn't a token, so it doesn't go here.
        if token != config.anonKey {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let contentType, body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.http(status: http.statusCode, message: Self.message(in: data))
        }
        return data
    }

    /// Supabase puts its error text under a few different keys depending on the service.
    private static func message(in data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        for key in ["message", "msg", "error_description", "error"] {
            if let text = json[key] as? String, !text.isEmpty { return text }
        }
        return ""
    }

    // MARK: Token

    private func validToken() async throws -> String {
        guard let session else { throw BackendError.signedOut }
        if session.expiresAt.timeIntervalSinceNow > 60 { return session.accessToken }
        return try await refreshSession().accessToken
    }

    /// Trades the refresh token for a new session. Calls that overlap share one request, because
    /// a refresh token can be used only once.
    private func refreshSession() async throws -> Session {
        if let refreshing { return try await refreshing.value }
        guard let current = session else { throw BackendError.signedOut }
        let task = Task { () throws -> Session in
            do {
                let data = try await perform(
                    "POST", "/auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                    body: try JSONEncoder().encode(["refresh_token": current.refreshToken]),
                    contentType: "application/json", headers: [:], token: config.anonKey
                )
                let response: AuthResponse = try decode(data)
                return response.session()
            } catch BackendError.http(let status, _) where (400..<500).contains(status) {
                // The refresh token is no good any more: this phone has to start over.
                throw BackendError.signedOut
            }
        }
        refreshing = task
        defer { refreshing = nil }
        do {
            let fresh = try await task.value
            setSession(fresh)
            return fresh
        } catch BackendError.signedOut {
            setSession(nil)
            throw BackendError.signedOut
        }
    }

    private func setSession(_ new: Session?) {
        session = new
        storage.save(new)
    }

    private struct AuthResponse: Decodable {
        var accessToken: String
        var refreshToken: String
        var expiresIn: Double
        var user: User

        struct User: Decodable { var id: UUID }

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case user
        }

        func session() -> Session {
            Session(accessToken: accessToken, refreshToken: refreshToken,
                    expiresAt: Date().addingTimeInterval(expiresIn), userID: user.id)
        }
    }
}
