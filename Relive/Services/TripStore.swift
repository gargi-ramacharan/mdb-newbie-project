import Foundation
import Observation

/// Where trips live. Today that is a JSON file on this phone; a Supabase-backed
/// type can take its place later without the views changing.
protocol TripRepository {
    func load() -> AppData?
    func save(_ data: AppData)
    /// A trip that exists for this invite code but that you haven't joined on this phone.
    func findTrip(inviteCode: String) -> Trip?
}

struct LocalTripRepository: TripRepository {
    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("relive.json")
    }

    func load() -> AppData? {
        guard let bytes = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AppData.self, from: bytes)
    }

    func save(_ data: AppData) {
        guard let bytes = try? JSONEncoder().encode(data) else { return }
        try? bytes.write(to: fileURL, options: .atomic)
    }

    func findTrip(inviteCode: String) -> Trip? {
        // Nothing is synced between phones yet, so only the seeded trip can be joined.
        SeedData.joinableTrips().first { $0.inviteCode == inviteCode }
    }
}

enum JoinResult {
    case joined(Trip)
    case alreadyMember(Trip)
    case notFound
}

@MainActor
@Observable
final class TripStore {
    private var data: AppData
    private let repository: TripRepository
    /// The server, when `SupabaseURL` and `SupabaseAnonKey` are set in Info.plist.
    /// Without one the app keeps everything on this phone.
    let backend: TripBackend?

    /// How many photos are uploading right now.
    private(set) var uploading = 0
    /// Why the last upload or refresh didn't work, for the notice on the trip screen.
    private(set) var syncProblem: String?
    private var isRefreshing = false

    init(
        repository: TripRepository = LocalTripRepository(),
        backend: TripBackend? = SupabaseConfig.fromBundle().map { SupabaseBackend(config: $0) }
    ) {
        self.repository = repository
        self.backend = backend
        self.data = repository.load() ?? AppData()
    }

    var hasBackend: Bool { backend != nil }

    var me: Member? { data.me }
    var placeNames: [String: PlaceName] {
        data.placeNames.merging(SeedData.sharedPlaceNames) { saved, _ in saved }
    }

    /// Made-up trips other people have shared with you. View-only, and never saved.
    let sharedTrips = SeedData.sharedTrips()

    /// Newest trip first.
    var trips: [Trip] { data.trips.sorted { $0.startDate > $1.startDate } }

    func trip(_ id: UUID) -> Trip? {
        data.trips.first { $0.id == id } ?? sharedTrips.first { $0.id == id }
    }

    /// The person who shared this trip with you, or `nil` when it is one of your own.
    func sharer(of trip: Trip) -> Member? {
        sharedTrips.contains { $0.id == trip.id } ? trip.members.first : nil
    }

    /// First launch: create your profile and seed the demo trip.
    /// With a backend this signs the phone in first, so it needs a connection.
    func signIn(name: String) async throws {
        let me = try await backend?.signIn(name: name) ?? Member(name: name, copy: 0)
        data.me = me
        data.trips.append(SeedData.demoTrip(me: me))
        data.placeNames.merge(SeedData.demoPlaceNames) { _, seeded in seeded }
        save()
        // A reinstall signs back into the same account, so its trips come back.
        await refresh()
    }

    /// On launch: make sure this phone is signed in as the person saved here, then catch up.
    /// Covers someone who used the app before sync existed and has no account yet.
    func bootstrap() async {
        guard let backend, let me = data.me else { return }
        do {
            var account = try await backend.restore()
            if account == nil { account = try await backend.signIn(name: me.name) }
            if let account, account.id != me.id {
                for index in data.trips.indices {
                    data.trips[index].replacePerson(me.id, with: account.id)
                }
                data.me?.id = account.id
                save()
            }
        } catch {
            syncProblem = Self.describe(error)
            return
        }
        await refresh()
    }

    /// Pulls every trip you're in from the server, then sends up any photos still waiting.
    func refresh() async {
        guard let backend, data.me != nil, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            for remote in try await backend.fetchTrips() { merge(remote) }
            syncProblem = nil
        } catch {
            syncProblem = Self.describe(error)
        }
        await uploadPending()
    }

    /// Pulls one trip's latest members and photos. Cheap enough to run whenever a trip opens.
    func refresh(tripID: UUID) async {
        guard let backend, data.me != nil, let local = data.trips.first(where: { $0.id == tripID }),
              !local.isDemo else { return }
        do {
            if let remote = try await backend.fetchTrip(id: tripID) { merge(remote) }
            syncProblem = nil
        } catch {
            syncProblem = Self.describe(error)
        }
        await uploadPending()
    }

    private func merge(_ remote: Trip) {
        if let index = data.trips.firstIndex(where: { $0.id == remote.id }) {
            data.trips[index].merge(remote: remote)
        } else {
            data.trips.append(remote)
        }
        save()
    }

    private static func describe(_ error: Error) -> String {
        if error is URLError { return "No connection. Your photos will sync when you're back online." }
        return error.localizedDescription
    }

    /// Puts the demo trip back to "your photos are waiting for review".
    func resetDemo() {
        guard let me = data.me else { return }
        data.trips.removeAll(where: \.isDemo)
        data.trips.append(SeedData.demoTrip(me: me))
        save()
    }

    /// With a backend the server mints the invite code, so this needs a connection.
    @discardableResult
    func createTrip(name: String, startDate: Date, endDate: Date, places: [Place]) async throws -> Trip? {
        guard let me = data.me else { return nil }
        var trip = Trip(
            name: name,
            startDate: startDate,
            endDate: endDate,
            places: places,
            members: [me],
            inviteCode: Self.newInviteCode()
        )
        // The dates were picked as calendar days on this phone. Pin them to the same
        // calendar days at the destination.
        trip.startDate = Self.sameDay(startDate, in: trip.calendar)
        trip.endDate = Self.sameDay(endDate, in: trip.calendar)
        if let backend {
            trip.inviteCode = try await backend.createTrip(trip)
        }
        data.trips.append(trip)
        save()
        return trip
    }

    func join(code rawCode: String) async throws -> JoinResult {
        let code = rawCode.uppercased().filter { $0.isLetter || $0.isNumber }
        if let existing = data.trips.first(where: { $0.inviteCode == code }) {
            return .alreadyMember(existing)
        }
        guard let me = data.me else { return .notFound }
        if let backend {
            guard let trip = try await backend.joinTrip(code: code) else { return .notFound }
            merge(trip)
            await uploadPending()
            return .joined(data.trips.first { $0.id == trip.id } ?? trip)
        }
        guard var trip = repository.findTrip(inviteCode: code) else { return .notFound }
        trip.members.append(me)
        data.trips.append(trip)
        save()
        return .joined(trip)
    }

    /// Ends a review: `added` joins the album, `skipped` is remembered so it isn't suggested again.
    /// Added photos start uploading right away.
    func finishReview(tripID: UUID, added: [TripPhoto], skipped: [TripPhoto]) {
        guard let index = data.trips.firstIndex(where: { $0.id == tripID }) else { return }
        data.trips[index].photos.append(contentsOf: added)
        data.trips[index].skipped.formUnion(skipped.map(\.ref))
        data.trips[index].skipped.subtract(added.map(\.ref))
        save()
        Task { await uploadPending() }
    }

    // MARK: Uploading

    /// Your reviewed photos in this trip that haven't reached the shared album yet.
    func pendingUploads(in tripID: UUID) -> Int {
        guard backend != nil, let me = data.me,
              let trip = data.trips.first(where: { $0.id == tripID }), !trip.isDemo else { return 0 }
        return trip.photos.filter { $0.needsUpload(by: me.id) }.count
    }

    /// Uploads every reviewed photo of yours that isn't in the shared album yet, compressed
    /// to about 1600 px. Stops at the first connection problem and tries again next time.
    func uploadPending() async {
        guard let backend, let me = data.me, uploading == 0 else { return }
        let work: [(tripID: UUID, photo: TripPhoto)] = data.trips.filter { !$0.isDemo }.flatMap { trip in
            trip.photos.filter { $0.needsUpload(by: me.id) }.map { (trip.id, $0) }
        }
        guard !work.isEmpty else { return }
        uploading = work.count
        var problem: String?

        for (tripID, photo) in work {
            guard case .asset(let identifier) = photo.ref else { continue }
            guard let jpeg = await PhotoScanner.jpegData(for: identifier, maxSide: Self.uploadSide) else {
                // Deleted, outside the photos you've allowed, or still in iCloud. It stays queued,
                // because the cause may be temporary.
                problem = "Some photos couldn't be loaded from your library."
                continue
            }
            do {
                let path = try await backend.uploadPhoto(photo, tripID: tripID, jpeg: jpeg)
                setRemotePath(path, for: photo.id, in: tripID)
            } catch {
                problem = Self.describe(error)
                if error is URLError || error as? BackendError == .signedOut { break }
            }
        }
        syncProblem = problem
        uploading = 0
        // Photos added while this batch was uploading are picked up straight away.
        if problem == nil { await uploadPending() }
    }

    /// Long edge, in pixels, of what gets uploaded. Originals are far too big to sync over mobile data.
    static let uploadSide: CGFloat = 1600

    private func setRemotePath(_ path: String, for photoID: UUID, in tripID: UUID) {
        guard let t = data.trips.firstIndex(where: { $0.id == tripID }),
              let p = data.trips[t].photos.firstIndex(where: { $0.id == photoID }) else { return }
        data.trips[t].photos[p].remotePath = path
        save()
    }

    /// The JPEG of a friend's photo: from this phone's cache if it has been seen, else downloaded.
    func albumPhoto(path: String) async -> Data? {
        if let cached = PhotoCache.read(path) { return cached }
        guard let backend, let bytes = try? await backend.downloadPhoto(path: path) else { return nil }
        PhotoCache.write(bytes, for: path)
        return bytes
    }

    func deleteTrip(_ id: UUID) {
        data.trips.removeAll { $0.id == id }
        save()
    }

    /// Reverse-geocodes any stop that has no cached name yet, one at a time.
    func resolveNames(for stops: [Stop]) async {
        var changed = false
        for stop in stops where placeNames[stop.nameKey] == nil {
            guard let name = await PlaceNamer.lookup(latitude: stop.latitude, longitude: stop.longitude) else {
                continue
            }
            data.placeNames[stop.nameKey] = name
            changed = true
        }
        if changed { save() }
    }

    private func save() { repository.save(data) }

    /// Noon on the same year, month and day as `date` reads on this phone, in another calendar.
    private static func sameDay(_ date: Date, in calendar: Calendar) -> Date {
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        parts.hour = 12
        return calendar.date(from: parts) ?? date
    }

    private static func newInviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}
