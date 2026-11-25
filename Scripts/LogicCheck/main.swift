// Checks the non-UI logic without Xcode. From the repo root:
//   swiftc Relive/Core/*.swift Relive/Backend/*.swift Scripts/LogicCheck/main.swift -o /tmp/relive-check && /tmp/relive-check
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ok   \(what)" : "  FAIL \(what)")
    if !ok { failures += 1 }
}

let me = Member(name: "Test User", copy: 0)
var trip = SeedData.demoTrip(me: me)
let names = SeedData.demoPlaceNames

print("Seed")
check(trip.members.count == 4, "demo trip has 4 members")
check(trip.dayCount() == 3, "demo trip is 3 days")
check(trip.hasEnded(), "demo trip has ended")
check(trip.photos.allSatisfy { $0.ownerID != me.id }, "none of your photos are pooled before review")
check(trip.photos.allSatisfy { trip.interval().contains($0.takenAt) }, "all friend photos fall inside the trip dates")
check(trip.photos.filter(\.hasLocation).allSatisfy { trip.isNearPlaces(latitude: $0.latitude!, longitude: $0.longitude!) },
      "all located photos are near a trip place")

let roll = SeedData.demoCameraRoll(trip: trip, me: me)
check(roll.count == 11, "your demo camera roll has 11 photos (got \(roll.count))")
check(roll.filter { !$0.hasLocation }.count == 2, "2 of them have no location")

print("Geo")
let lisbonToSintra = Geo.distanceKm(38.7223, -9.1393, 38.8029, -9.3817)
check(abs(lisbonToSintra - 22.8) < 1, "Lisbon to Sintra is about 23 km (got \(lisbonToSintra))")
check(!trip.isNearPlaces(latitude: 41.1579, longitude: -8.6291), "Porto is outside the trip area")

print("Clustering")
let before = StopClusterer.stops(from: trip.photos)
check(before.count == 12, "friends' photos form 12 stops (got \(before.count))")
check(before.allSatisfy { names[$0.nameKey] != nil }, "every demo stop has a seeded name")
check(zip(before, before.dropFirst()).allSatisfy { $0.start <= $1.start }, "stops are in time order")

trip.photos += roll
let after = StopClusterer.stops(from: trip.photos)
check(after.count == 12, "adding your photos keeps 12 stops (got \(after.count))")
check(after.reduce(0) { $0 + $1.photos.count } == trip.photos.filter(\.hasLocation).count,
      "every located photo is in exactly one stop")

// Two people shooting at different places at the same time must not fragment stops.
let t0 = Date(timeIntervalSince1970: 1_700_000_000)
func p(_ min: Double, _ lat: Double, _ lon: Double) -> TripPhoto {
    TripPhoto(ownerID: me.id, takenAt: t0.addingTimeInterval(min * 60), latitude: lat, longitude: lon, ref: .asset("x"))
}
let interleaved = StopClusterer.stops(from: [p(0, 10, 10), p(1, 10.01, 10), p(2, 10, 10), p(3, 10.01, 10)])
check(interleaved.count == 2, "interleaved photos at two places make 2 stops (got \(interleaved.count))")
let revisit = StopClusterer.stops(from: [p(0, 10, 10), p(300, 10, 10)])
check(revisit.count == 2, "coming back 5 hours later is a new stop")

print("Time zones")
// A Tokyo trip must count its first morning and last night as trip days no matter
// which time zone this machine is in.
var tokyo = Calendar(identifier: .gregorian)
tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
func jst(_ day: Int, _ hour: Int) -> Date {
    tokyo.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
}
let tokyoTrip = Trip(
    name: "Tokyo", startDate: jst(14, 12), endDate: jst(16, 12),
    places: [Place(name: "Tokyo", latitude: 35.68, longitude: 139.76, timeZoneID: "Asia/Tokyo")],
    members: [me], inviteCode: "TOKYO1"
)
check(tokyoTrip.dayCount() == 3, "Tokyo trip is 3 days")
check(tokyoTrip.interval().contains(jst(14, 1)), "1 am on the first day in Tokyo is inside the trip")
check(tokyoTrip.interval().contains(jst(16, 23)), "11 pm on the last day in Tokyo is inside the trip")
check(!tokyoTrip.interval().contains(jst(13, 23)), "the night before is outside the trip")
check(tokyoTrip.dayNumber(for: jst(14, 1)) == 1 && tokyoTrip.dayNumber(for: jst(16, 23)) == 3, "day numbers follow Tokyo days")

print("Stats")
let stats = TripStats.compute(trip: trip, stops: after, names: names)
check(stats.photoCount == trip.photos.count, "photo count matches the album (\(stats.photoCount))")
check(stats.cities == ["Lisbon", "Sintra", "Cascais"], "cities in visit order (got \(stats.cities))")
check(stats.perMember.reduce(0) { $0 + $1.count } == stats.photoCount, "per-person counts add up")
check(stats.perMember.first!.count >= stats.perMember.last!.count, "per-person is sorted most first")
check(stats.busiestDayCount > 0 && stats.busiestDay != nil, "busiest day found (\(stats.busiestDayCount) photos)")
check(stats.furthestName == "Boca do Inferno", "furthest from start is Boca do Inferno (got \(stats.furthestName ?? "nil"))")
check(stats.furthestKm > 24 && stats.furthestKm < 27, "about 25 km from start (got \(stats.furthestKm))")
check(stats.pathKm > stats.furthestKm, "path is longer than the furthest hop (\(stats.pathKm) km)")

print("Codable")
let data = AppData(me: me, trips: [trip], placeNames: names)
let decoded = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
check(decoded.trips == data.trips && decoded.placeNames == data.placeNames, "app data survives a save and load")

print("Shared trips")
let shared = SeedData.sharedTrips()
let sharedNames = SeedData.sharedPlaceNames
check(shared.count == 5 && Set(shared.map(\.id)).count == 5, "5 shared trips with their own ids (got \(shared.count))")
check(shared.allSatisfy { $0.hasEnded() }, "every shared trip has ended")
check(shared.allSatisfy { t in t.photos.allSatisfy { t.interval().contains($0.takenAt) && t.member($0.ownerID) != nil } },
      "their photos fall inside the trip dates and belong to its members")
check(shared.allSatisfy { t in t.photos.allSatisfy { t.isNearPlaces(latitude: $0.latitude!, longitude: $0.longitude!) } },
      "their photos are all near the trip's place")
check(shared.allSatisfy { t in StopClusterer.stops(from: t.photos).allSatisfy { sharedNames[$0.nameKey] != nil } },
      "every shared stop has a seeded name")
check(Set(shared.flatMap { $0.photos.map(\.id) }).isDisjoint(with: trip.photos.map(\.id)), "shared photo ids don't clash with the demo trip")

print("Members")
var group = SeedData.demoTrip(me: me)
check(group.isOwner(me.id), "the first member owns a trip saved without an owner")
let groupFriend = group.members[1]
let friendPhotos = group.photos.filter { $0.ownerID == groupFriend.id }
check(!friendPhotos.isEmpty, "the friend has photos to take away")
group.coverPhotoID = friendPhotos[0].id
group.removeMember(me.id)
check(group.member(me.id) != nil, "the owner can't be removed")
group.removeMember(groupFriend.id)
check(group.member(groupFriend.id) == nil, "a removed member is off the trip")
check(group.photos.allSatisfy { $0.ownerID != groupFriend.id }, "their photos go with them")
check(group.coverPhotoID == nil, "a cover from their photos falls back to automatic")
group.makeOwner(groupFriend.id)
check(group.isOwner(me.id), "someone off the trip can't be made owner")
let next = group.members[1]
group.makeOwner(next.id)
check(group.isOwner(next.id) && !group.isOwner(me.id), "ownership can be handed to another member")
let trip2 = try! JSONDecoder().decode(Trip.self, from: JSONEncoder().encode(group))
check(trip2.ownerID == next.id, "the owner survives saving")

print("Invite codes")
let codes = (0..<2000).map { _ in InviteCode.random() }
check(codes.allSatisfy { $0.count == 6 && $0.allSatisfy(InviteCode.alphabet.contains) }, "codes are six characters from the alphabet")
check(!InviteCode.alphabet.contains(where: { "01OI".contains($0) }), "codes skip 0, O, 1 and I")

// MARK: Sync

print("Sync merge")
let friend = Member(name: "Friend One", copy: 1)
let pendingPhoto = TripPhoto(ownerID: me.id, takenAt: t0, latitude: 10, longitude: 10, ref: .asset("pending"))
let uploadedPhoto = TripPhoto(ownerID: me.id, takenAt: t0.addingTimeInterval(60), latitude: 10, longitude: 10, ref: .asset("done"))
var local = Trip(name: "Old name", startDate: t0, endDate: t0, places: [], members: [me],
                 inviteCode: "OLD123", photos: [pendingPhoto, uploadedPhoto])
local.skipped = [.asset("skipped")]
var uploadedOnServer = uploadedPhoto
uploadedOnServer.ref = .remote("t/me/done.jpg")
uploadedOnServer.remotePath = "t/me/done.jpg"
let friendPhoto = TripPhoto(ownerID: friend.id, takenAt: t0.addingTimeInterval(120), latitude: 10, longitude: 10,
                            ref: .remote("t/friend/x.jpg"), remotePath: "t/friend/x.jpg")
var remote = local
remote.name = "New name"
remote.members = [me, friend]
remote.photos = [uploadedOnServer, friendPhoto]
local.merge(remote: remote)
check(local.name == "New name" && local.members.count == 2, "trip details and members come from the server")
check(local.photos.count == 3, "pending + uploaded + friend's photo (got \(local.photos.count))")
check(local.photos.first { $0.id == pendingPhoto.id }?.remotePath == nil, "a photo still waiting to upload is kept")
check(local.photos.first { $0.id == uploadedPhoto.id }?.ref == .asset("done"), "your uploaded photo keeps its camera-roll reference")
check(local.photos.first { $0.id == uploadedPhoto.id }?.remotePath == "t/me/done.jpg", "and is marked uploaded")
check(local.photos.contains { $0.id == friendPhoto.id }, "a friend's photo arrives")
check(local.skipped == [.asset("skipped")], "skipped photos survive a sync")
check(local.photos.filter { $0.needsUpload(by: me.id) }.map(\.id) == [pendingPhoto.id], "only the unsent photo needs uploading")
check(!friendPhoto.needsUpload(by: me.id) && !friendPhoto.needsUpload(by: friend.id), "downloaded photos never need uploading")

var remapped = local
let newMe = UUID()
remapped.replacePerson(me.id, with: newMe)
check(remapped.members.contains { $0.id == newMe } && remapped.photos.filter { $0.ownerID == newMe }.count == 2
      && !remapped.members.contains { $0.id == me.id }, "a new account identity takes over your photos and membership")

let already = AlreadyUploaded(trip: remapped, owner: friend.id)
check(already.contains(t0.addingTimeInterval(120)) && already.contains(t0.addingTimeInterval(120.0004))
      && !already.contains(t0.addingTimeInterval(121)), "a camera-roll photo matching an album copy is recognised")
check(AlbumPath.path(tripID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
                     ownerID: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!,
                     photoID: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!)
      == "aaaaaaaa-0000-0000-0000-000000000001/bbbbbbbb-0000-0000-0000-000000000002/cccccccc-0000-0000-0000-000000000003.jpg",
      "album paths are <trip>/<owner>/<photo>.jpg in lower case")

print("Wire format")
check(Wire.parseDate("2026-11-15T12:00:00+00:00") == Date(timeIntervalSince1970: 1_794_744_000), "plain Postgres timestamp")
let micro = Wire.parseDate("2026-11-15T12:00:00.123456+00:00")
check(micro != nil && abs(micro!.timeIntervalSince1970 - 1_794_744_000.123) < 0.002, "timestamp with microseconds")
check(Wire.parseDate("2026-11-15T14:00:00.5+02:00") == Date(timeIntervalSince1970: 1_794_744_000.5), "short fraction and a UTC offset")
check(Wire.parseDate(Wire.format(t0)) == t0, "dates survive format and parse")

let tripJSON = """
[{"id":"11111111-1111-1111-1111-111111111111","name":"Lisbon","start_date":"2026-11-14T12:00:00+00:00",
  "end_date":"2026-11-16T12:00:00+00:00","invite_code":"ABC234",
  "places":[{"id":"22222222-2222-2222-2222-222222222222","name":"Lisbon","latitude":38.7,"longitude":-9.1,"radiusKm":50,"timeZoneID":"Europe/Lisbon"}],
  "trip_members":[
    {"user_id":"44444444-4444-4444-4444-444444444444","copy":1,"joined_at":"2026-11-10T10:00:00.5+00:00","profiles":{"name":"Joiner"}},
    {"user_id":"33333333-3333-3333-3333-333333333333","copy":0,"joined_at":"2026-11-09T10:00:00+00:00","profiles":{"name":"Creator"}}],
  "photos":[{"id":"55555555-5555-5555-5555-555555555555","trip_id":"11111111-1111-1111-1111-111111111111",
    "owner_id":"33333333-3333-3333-3333-333333333333","taken_at":"2026-11-14T13:30:00.250+00:00",
    "latitude":38.71,"longitude":null,"storage_path":"p/q/r.jpg"}]}]
"""
let rows = try Wire.decoder.decode([Wire.TripRow].self, from: Data(tripJSON.utf8))
let decodedTrip = rows[0].makeTrip()
check(decodedTrip.members.map(\.name) == ["Creator", "Joiner"], "members come back in join order with their names")
check(decodedTrip.places.first?.timeZoneID == "Europe/Lisbon" && decodedTrip.inviteCode == "ABC234", "places and invite code decode")
check(decodedTrip.photos.count == 1 && decodedTrip.photos[0].ref == .remote("p/q/r.jpg") && !decodedTrip.photos[0].hasLocation,
      "photos decode as downloadable and tolerate a missing coordinate")

print("Supabase client")
final class Stub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [(request: URLRequest, body: Data)] = []
    nonisolated(unsafe) static var respond: (URLRequest) -> (Int, String) = { _ in (200, "{}") }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        Stub.requests.append((request, body))
        let (status, text) = Stub.respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class MemoryStorage: SessionStorage, @unchecked Sendable {
    nonisolated(unsafe) var session: Session?
    init(_ session: Session? = nil) { self.session = session }
    func load() -> Session? { session }
    func save(_ session: Session?) { self.session = session }
}
let stubConfig = URLSessionConfiguration.ephemeral
stubConfig.protocolClasses = [Stub.self]
let stubSession = URLSession(configuration: stubConfig)
let config = SupabaseConfig(url: URL(string: "https://example.supabase.co")!, anonKey: "anon-key")
func authJSON(token: String, user: UUID) -> String {
    #"{"access_token":"\#(token)","refresh_token":"r-\#(token)","expires_in":3600,"user":{"id":"\#(user.uuidString)"}}"#
}
func lastBody() -> String { String(data: Stub.requests.last!.body, encoding: .utf8) ?? "" }

let userID = UUID()
let storage = MemoryStorage()
let backend = SupabaseBackend(config: config, urlSession: stubSession, storage: storage)
Stub.respond = { request in
    request.url!.path == "/auth/v1/signup" ? (200, authJSON(token: "t1", user: userID)) : (201, "")
}
let signedIn = try await backend.signIn(name: "Ada Lovelace")
check(signedIn.id == userID && signedIn.name == "Ada Lovelace", "sign-in creates an anonymous account and returns you")
check(Stub.requests.map(\.request.url!.path) == ["/auth/v1/signup", "/rest/v1/profiles"], "sign-in = sign up, then save the profile")
check(Stub.requests[0].request.value(forHTTPHeaderField: "apikey") == "anon-key"
      && Stub.requests[0].request.value(forHTTPHeaderField: "Authorization") == nil,
      "sign-up is sent with the anon key as apikey only")
check(Stub.requests[1].request.value(forHTTPHeaderField: "Authorization") == "Bearer t1"
      && Stub.requests[1].request.value(forHTTPHeaderField: "apikey") == "anon-key", "later calls carry your token")
check(storage.session?.userID == userID, "the session is saved for next launch")

Stub.requests = []
Stub.respond = { _ in (200, "\"K7M2QX\"") }
var newTrip = Trip(name: "Weekend", startDate: t0, endDate: t0, places: [Place(name: "Here", latitude: 1, longitude: 2)],
                   members: [signedIn], inviteCode: "LOCAL1")
let code = try await backend.createTrip(newTrip)
check(code == "K7M2QX", "the server's invite code comes back")
check(Stub.requests[0].request.url!.path == "/rest/v1/rpc/create_trip" && lastBody().contains("\"p_name\":\"Weekend\"")
      && lastBody().contains("\"radiusKm\":50"), "create_trip sends the trip and its places as-is")

Stub.requests = []
Stub.respond = { _ in (200, "null") }
let nobody = try await backend.joinTrip(code: "NOPE00")
check(nobody == nil && Stub.requests.count == 1, "an unknown invite code joins nothing")

Stub.requests = []
let joinID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
Stub.respond = { request in
    request.url!.path.hasSuffix("join_trip") ? (200, "\"\(joinID.uuidString.lowercased())\"") : (200, tripJSON)
}
let joined = try await backend.joinTrip(code: "abc234")
check(joined?.name == "Lisbon" && Stub.requests.count == 2, "joining returns the trip with its members and photos")
check(Stub.requests[1].request.url!.query?.contains("id=eq.11111111-1111-1111-1111-111111111111") == true, "the trip is fetched by id")

Stub.requests = []
Stub.respond = { _ in (200, "") }
let photoPath = try await backend.uploadPhoto(pendingPhoto, tripID: joinID, jpeg: Data([0xFF, 0xD8, 0xFF]))
check(photoPath == AlbumPath.path(tripID: joinID, ownerID: pendingPhoto.ownerID, photoID: pendingPhoto.id), "uploads go to <trip>/<owner>/<photo>.jpg")
check(Stub.requests.map(\.request.url!.path) == ["/storage/v1/object/trip-photos/\(photoPath)", "/rest/v1/photos"],
      "the file is stored first, then the album row")
check(Stub.requests[0].request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg"
      && Stub.requests[0].request.value(forHTTPHeaderField: "x-upsert") == "true"
      && Stub.requests[0].body == Data([0xFF, 0xD8, 0xFF]), "the JPEG bytes are sent untouched and a retry overwrites")
check(Stub.requests[1].request.value(forHTTPHeaderField: "Prefer")?.contains("merge-duplicates") == true
      && (try? Wire.decoder.decode(Wire.PhotoRow.self, from: Stub.requests[1].body))?.storagePath == photoPath
      && Stub.requests[1].request.url!.query == "on_conflict=id", "the album row is an upsert, so retries don't duplicate")

Stub.requests = []
Stub.respond = { _ in (200, "bytes") }
let downloaded = try await backend.downloadPhoto(path: "a/b/c.jpg")
check(downloaded == Data("bytes".utf8) && Stub.requests[0].request.url!.path == "/storage/v1/object/authenticated/trip-photos/a/b/c.jpg",
      "friends' photos download through the authenticated route")

print("Token refresh")
let stale = Session(accessToken: "old", refreshToken: "r-old", expiresAt: Date().addingTimeInterval(-10), userID: userID)
let refreshStorage = MemoryStorage(stale)
let refreshing = SupabaseBackend(config: config, urlSession: stubSession, storage: refreshStorage)
Stub.requests = []
Stub.respond = { request in
    request.url!.path == "/auth/v1/token" ? (200, authJSON(token: "new", user: userID)) : (200, "[]")
}
_ = try await refreshing.fetchTrips()
check(Stub.requests.map(\.request.url!.path) == ["/auth/v1/token", "/rest/v1/trips"], "an expired token is refreshed before the request")
check(Stub.requests[1].request.value(forHTTPHeaderField: "Authorization") == "Bearer new" && refreshStorage.session?.accessToken == "new",
      "the new token is used and saved")
check(lastBody() == "" && Stub.requests[0].body.count > 0 && String(data: Stub.requests[0].body, encoding: .utf8)!.contains("r-old"),
      "the refresh sends the refresh token")

Stub.requests = []
var calls = 0
Stub.respond = { request in
    if request.url!.path == "/auth/v1/token" { return (200, authJSON(token: "again", user: userID)) }
    calls += 1
    return calls == 1 ? (401, #"{"message":"JWT expired"}"#) : (200, "[]")
}
_ = try await refreshing.fetchTrips()
check(Stub.requests.map(\.request.url!.path) == ["/rest/v1/trips", "/auth/v1/token", "/rest/v1/trips"],
      "a 401 refreshes the token and retries once")

let dead = MemoryStorage(Session(accessToken: "x", refreshToken: "r-x", expiresAt: Date().addingTimeInterval(-10), userID: userID))
let expired = SupabaseBackend(config: config, urlSession: stubSession, storage: dead)
Stub.respond = { _ in (400, #"{"error_description":"Invalid Refresh Token"}"#) }
var outcome: Error?
do { _ = try await expired.fetchTrips() } catch { outcome = error }
check(outcome as? BackendError == .signedOut && dead.session == nil, "a dead refresh token signs you out and clears the saved session")
let noSession = try await expired.restore()
check(noSession == nil, "with no session there is no one to restore")

Stub.respond = { _ in (409, #"{"message":"duplicate key value"}"#) }
var failure: Error?
do { _ = try await backend.createTrip(newTrip) } catch { failure = error }
check((failure as? BackendError) == .http(status: 409, message: "duplicate key value"), "server errors surface their message")

print("Sign in with Apple")
// Linking: an anonymous account attaches the Apple ID and keeps its id (and so its trips).
let anonID = UUID()
let linkStorage = MemoryStorage(Session(accessToken: "anon", refreshToken: "r-anon", expiresAt: Date().addingTimeInterval(3600), userID: anonID))
let linking = SupabaseBackend(config: config, urlSession: stubSession, storage: linkStorage)
Stub.requests = []
Stub.respond = { request in
    if request.url!.path == "/auth/v1/token" { return (200, authJSON(token: "linked", user: anonID)) }
    return (200, #"[{"id":"\#(anonID.uuidString)","name":"Ada"}]"#)
}
let linkedMe = try await linking.signInWithApple(idToken: "apple-jwt", nonce: "raw-nonce", name: "Someone Else")
let linkBody = String(data: Stub.requests[0].body, encoding: .utf8) ?? ""
check(Stub.requests[0].request.url!.query == "grant_type=id_token" && linkBody.contains("\"link_identity\":true")
      && linkBody.contains("\"provider\":\"apple\"") && linkBody.contains("\"nonce\":\"raw-nonce\""),
      "linking sends the Apple token with link_identity and the raw nonce")
check(Stub.requests[0].request.value(forHTTPHeaderField: "Authorization") == "Bearer anon",
      "linking is sent as the anonymous user")
check(linkedMe.id == anonID && linkedMe.name == "Ada", "a linked account keeps its id and existing name")

// That Apple ID already has an account elsewhere: linking is refused, so sign into that account.
let appleID = UUID()
let switchStorage = MemoryStorage(Session(accessToken: "anon2", refreshToken: "r-anon2", expiresAt: Date().addingTimeInterval(3600), userID: anonID))
let switching = SupabaseBackend(config: config, urlSession: stubSession, storage: switchStorage)
Stub.requests = []
Stub.respond = { request in
    if request.url!.path == "/auth/v1/token" {
        // The stub records each body before it answers, so the latest one is this request's.
        let body = String(data: Stub.requests.last?.body ?? Data(), encoding: .utf8) ?? ""
        return body.contains("link_identity")
            ? (422, #"{"msg":"Identity is already linked to another user"}"#)
            : (200, authJSON(token: "apple", user: appleID))
    }
    return (200, #"[{"id":"\#(appleID.uuidString)","name":"Ada on her other phone"}]"#)
}
let switched = try await switching.signInWithApple(idToken: "apple-jwt", nonce: "n", name: nil)
check(switched.id == appleID && switchStorage.session?.userID == appleID, "an Apple ID with its own account signs into that account")
check(Stub.requests.filter { $0.request.url!.path == "/auth/v1/token" }.count == 2
      && Stub.requests[1].request.value(forHTTPHeaderField: "apikey") == "anon-key"
      && Stub.requests[1].request.value(forHTTPHeaderField: "Authorization") == nil,
      "after the refused link, a plain Apple sign-in goes with the anon key")

// Brand new: no session, no profile yet; the name Apple shared is saved.
let freshStorage = MemoryStorage()
let fresh = SupabaseBackend(config: config, urlSession: stubSession, storage: freshStorage)
let newAppleID = UUID()
Stub.requests = []
Stub.respond = { request in
    if request.url!.path == "/auth/v1/token" { return (200, authJSON(token: "new-apple", user: newAppleID)) }
    return request.httpMethod == "GET" ? (200, "[]") : (201, "")
}
let newcomer = try await fresh.signInWithApple(idToken: "apple-jwt", nonce: "n", name: "Grace Hopper")
check(newcomer.id == newAppleID && newcomer.name == "Grace Hopper", "a first Apple sign-in creates the profile with Apple's name")
check(!(String(data: Stub.requests[0].body, encoding: .utf8) ?? "").contains("link_identity"), "with no account yet, nothing is linked")

print("Owner actions")
Stub.requests = []
Stub.respond = { _ in (204, "") }
var edited = newTrip
edited.coverPhotoID = nil
edited.coverPath = nil
try await backend.updateTrip(edited)
let updateBody = String(data: Stub.requests[0].body, encoding: .utf8) ?? ""
check(Stub.requests[0].request.url!.path == "/rest/v1/rpc/update_trip" && updateBody.contains("\"p_cover_path\":null")
      && updateBody.contains("\"p_cover_photo_id\":null"), "update_trip sends empty covers as null")
try await backend.removeMember(userID, tripID: joinID)
try await backend.transferTrip(joinID, to: userID)
try await backend.leaveTrip(joinID)
try await backend.deleteTrip(joinID)
check(Stub.requests.dropFirst().map(\.request.url!.path) == ["/rest/v1/rpc/remove_member", "/rest/v1/rpc/transfer_trip",
                                                             "/rest/v1/rpc/leave_trip", "/rest/v1/rpc/delete_trip"],
      "member and owner actions call their database functions")

print("Invite links")
let host = "relive.example.com"
check(InviteLink.url(code: "ABC123", host: nil).absoluteString == "relive://join/ABC123", "no domain: relive:// link")
check(InviteLink.url(code: "ABC123", host: host).absoluteString == "https://relive.example.com/join/ABC123", "with a domain: https link")
check(InviteLink.code(in: URL(string: "relive://join/ABC123")!, host: host) == "ABC123", "reads a relive:// invite")
check(InviteLink.code(in: URL(string: "https://relive.example.com/join/ABC123")!, host: host) == "ABC123", "reads a web invite")
check(InviteLink.code(in: URL(string: "https://evil.example.com/join/ABC123")!, host: host) == nil, "ignores other domains")
check(InviteLink.code(in: URL(string: "https://relive.example.com/other/ABC123")!, host: host) == nil, "ignores other paths")
check(InviteLink.code(in: URL(string: "https://relive.example.com/join/ABC123")!, host: nil) == nil, "ignores web links with no domain set up")

print("Sync: owners, covers, removals")
var mine = Trip(name: "T", startDate: t0, endDate: t0, places: [], members: [me], inviteCode: "SYNC01")
let keptPending = TripPhoto(ownerID: me.id, takenAt: t0, ref: .asset("waiting"))
let goneRemote = TripPhoto(ownerID: me.id, takenAt: t0, ref: .remote("t/x/gone.jpg"), remotePath: "t/x/gone.jpg")
mine.photos = [keptPending, goneRemote]
mine.coverPhotoID = goneRemote.id
mine.coverImageFile = "old.jpg"
mine.coverPath = "t/me/cover-old.jpg"
var server = mine
let newOwner = UUID()
server.ownerID = newOwner
server.photos = []
server.coverPath = "t/them/cover-new.jpg"
mine.merge(remote: server)
check(mine.ownerID == newOwner, "a new owner comes down from the server")
check(mine.photos.map(\.id) == [keptPending.id], "photos the server dropped go; ones waiting to upload stay")
check(mine.coverPhotoID == nil, "a cover photo that's gone falls back to automatic")
check(mine.coverPath == "t/them/cover-new.jpg" && mine.coverImageFile == nil, "a cover uploaded elsewhere replaces this phone's copy")
check(mine.onServer == true, "a merged trip is marked as on the server")

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
