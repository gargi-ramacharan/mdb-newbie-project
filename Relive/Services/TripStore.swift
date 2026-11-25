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

    /// Made-up trips other people have shared with you. With no server to fetch them from,
    /// they are rebuilt from seed data on every launch; only which ones you left is saved.
    private let allSharedTrips = SeedData.sharedTrips()

    /// Trips other people have shared with you that you haven't left. View-only.
    var sharedTrips: [Trip] {
        let left = data.leftSharedTrips ?? []
        return allSharedTrips.filter { !left.contains($0.id) }
    }

    /// Newest trip first.
    var trips: [Trip] { data.trips.sorted { $0.startDate > $1.startDate } }

    func trip(_ id: UUID) -> Trip? {
        data.trips.first { $0.id == id } ?? sharedTrips.first { $0.id == id }
    }

    /// The person who shared this trip with you, or `nil` when it is one of your own.
    func sharer(of trip: Trip) -> Member? {
        allSharedTrips.contains { $0.id == trip.id } ? trip.members.first : nil
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
            let remotes = try await backend.fetchTrips()
            for remote in remotes { merge(remote) }
            // A synced trip the server no longer lists was deleted, or you were taken off it.
            let listed = Set(remotes.map(\.id))
            data.trips.removeAll { $0.onServer == true && !listed.contains($0.id) }
            save()
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
            if let remote = try await backend.fetchTrip(id: tripID) {
                merge(remote)
            } else if local.onServer == true {
                // Deleted, or you were taken off it.
                data.trips.removeAll { $0.id == tripID }
                save()
            }
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

    /// Puts the demo trip back to "your photos are waiting for review", and brings back
    /// any shared trips you left.
    func resetDemo() {
        guard let me = data.me else { return }
        data.trips.removeAll(where: \.isDemo)
        data.trips.append(SeedData.demoTrip(me: me))
        data.leftSharedTrips = nil
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
            inviteCode: newInviteCode(),
            ownerID: me.id
        )
        // The dates were picked as calendar days on this phone. Pin them to the same
        // calendar days at the destination.
        trip.startDate = Self.sameDay(startDate, in: trip.calendar)
        trip.endDate = Self.sameDay(endDate, in: trip.calendar)
        if let backend {
            trip.inviteCode = try await backend.createTrip(trip)
            trip.onServer = true
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

    // MARK: Owner and member actions
    //
    // A trip that's on the server changes there first; this phone's copy only changes once the
    // server agrees. Local-only trips (the demo, or with no backend) change straight away.
    // Each returns false and sets `actionProblem` if the server said no.

    /// Why the last owner or member action didn't go through, for an alert.
    var actionProblem: String?

    private func syncs(_ trip: Trip) -> Bool { backend != nil && trip.onServer == true }

    private func failed(_ error: Error) -> Bool {
        actionProblem = error is URLError
            ? "Couldn't reach the server. Check your connection and try again."
            : error.localizedDescription
        return false
    }

    /// Takes one of your photos out of a trip's album. It isn't suggested again.
    @discardableResult
    func removePhoto(_ photoID: UUID, from tripID: UUID) async -> Bool {
        guard let me = data.me,
              let trip = data.trips.first(where: { $0.id == tripID }),
              let photo = trip.photos.first(where: { $0.id == photoID }),
              photo.ownerID == me.id else { return false }
        if let backend, syncs(trip), photo.remotePath != nil {
            do { try await backend.deletePhoto(photo, tripID: tripID) } catch { return failed(error) }
        }
        guard let index = data.trips.firstIndex(where: { $0.id == tripID }) else { return true }
        data.trips[index].photos.removeAll { $0.id == photoID }
        data.trips[index].skipped.insert(photo.ref)
        if data.trips[index].coverPhotoID == photoID {
            data.trips[index].coverPhotoID = nil
        }
        save()
        return true
    }

    /// True when you run this trip and can manage its members or delete it.
    func isOwner(of trip: Trip) -> Bool {
        guard let me = data.me else { return false }
        return trip.isOwner(me.id)
    }

    /// Owner only: saves changes to a trip's name, dates, places and cover. Dates are
    /// calendar days as picked on this phone, like `createTrip`. A newly uploaded cover is
    /// sent to the shared album so every member sees it.
    @discardableResult
    func updateTrip(
        _ id: UUID, name: String, startDate: Date, endDate: Date, places: [Place],
        coverPhotoID: UUID?, coverImageFile: String?, keepUploadedCover: Bool = false
    ) async -> Bool {
        guard let old = data.trips.first(where: { $0.id == id }), isOwner(of: old) else { return false }
        var trip = old
        trip.name = name
        trip.places = places
        trip.coverPhotoID = coverPhotoID
        trip.coverImageFile = coverImageFile
        // A new upload replaces the old cover's path; choosing Auto or an album photo clears it.
        if coverImageFile != old.coverImageFile || (coverImageFile == nil && !keepUploadedCover) {
            trip.coverPath = nil
        }
        // The places decide the trip's time zone, so pin the days after they are set.
        trip.startDate = Self.sameDay(startDate, in: trip.calendar)
        trip.endDate = Self.sameDay(max(endDate, startDate), in: trip.calendar)

        if let backend, syncs(old) {
            do {
                if let file = coverImageFile, file != old.coverImageFile, let jpeg = CoverImages.data(file) {
                    trip.coverPath = try await backend.uploadCover(tripID: id, jpeg: jpeg)
                }
                try await backend.updateTrip(trip)
            } catch {
                return failed(error)
            }
            if let oldPath = old.coverPath, oldPath != trip.coverPath {
                // Only works for covers you uploaded; anyone else's stays, unreferenced.
                try? await backend.deleteFile(path: oldPath)
            }
        }
        if let oldFile = old.coverImageFile, oldFile != coverImageFile {
            CoverImages.delete(oldFile)
        }
        guard let index = data.trips.firstIndex(where: { $0.id == id }) else { return true }
        // Keep anything that synced in meanwhile (photos, members); take the edited details.
        data.trips[index].name = trip.name
        data.trips[index].places = trip.places
        data.trips[index].startDate = trip.startDate
        data.trips[index].endDate = trip.endDate
        data.trips[index].coverPhotoID = trip.coverPhotoID
        data.trips[index].coverImageFile = trip.coverImageFile
        data.trips[index].coverPath = trip.coverPath
        save()
        return true
    }

    /// Owner only: takes a member off the trip, with the photos they added.
    @discardableResult
    func removeMember(_ memberID: UUID, from tripID: UUID) async -> Bool {
        guard let trip = data.trips.first(where: { $0.id == tripID }), isOwner(of: trip) else { return false }
        if let backend, syncs(trip) {
            do { try await backend.removeMember(memberID, tripID: tripID) } catch { return failed(error) }
        }
        guard let index = data.trips.firstIndex(where: { $0.id == tripID }) else { return true }
        data.trips[index].removeMember(memberID)
        save()
        return true
    }

    /// Owner only: hands the trip to another member.
    @discardableResult
    func makeOwner(_ memberID: UUID, of tripID: UUID) async -> Bool {
        guard let trip = data.trips.first(where: { $0.id == tripID }), isOwner(of: trip) else { return false }
        if let backend, syncs(trip) {
            do { try await backend.transferTrip(tripID, to: memberID) } catch { return failed(error) }
        }
        guard let index = data.trips.firstIndex(where: { $0.id == tripID }) else { return true }
        data.trips[index].makeOwner(memberID)
        save()
        return true
    }

    /// Takes you off a trip you don't own, with the photos you added, or hides a trip someone
    /// shared with you. An owner has to hand the trip on first, or delete it.
    @discardableResult
    func leaveTrip(_ id: UUID) async -> Bool {
        if let trip = data.trips.first(where: { $0.id == id }) {
            guard !isOwner(of: trip) else { return false }
            if let backend, syncs(trip) {
                do { try await backend.leaveTrip(id) } catch { return failed(error) }
            }
            data.trips.removeAll { $0.id == id }
        } else if allSharedTrips.contains(where: { $0.id == id }) {
            data.leftSharedTrips = (data.leftSharedTrips ?? []).union([id])
        } else {
            return false
        }
        save()
        return true
    }

    /// Owner only: deletes the trip for everyone on it.
    @discardableResult
    func deleteTrip(_ id: UUID) async -> Bool {
        guard let trip = data.trips.first(where: { $0.id == id }), isOwner(of: trip) else { return false }
        if let backend, syncs(trip) {
            do { try await backend.deleteTrip(id) } catch { return failed(error) }
        }
        if let file = trip.coverImageFile { CoverImages.delete(file) }
        data.trips.removeAll { $0.id == id }
        save()
        return true
    }

    // MARK: Sign in with Apple

    /// True once this phone's account is signed in with Apple, so it works on other devices.
    var isSignedInWithApple: Bool { data.signedInWithApple == true }

    /// Signs in with Apple. On first launch this creates your profile (using the name Apple
    /// shares, or `name`); later it attaches Apple to the account you already have. If that
    /// Apple ID already has an account, this phone switches to it and its trips come down.
    func signInWithApple(idToken: String, nonce: String, name: String?) async throws {
        guard let backend else { return }
        let account = try await backend.signInWithApple(idToken: idToken, nonce: nonce, name: name)
        if let me = data.me {
            if account.id != me.id {
                for index in data.trips.indices {
                    data.trips[index].replacePerson(me.id, with: account.id)
                }
            }
            data.me = Member(id: account.id, name: account.name, copy: me.copy)
        } else {
            data.me = account
            data.trips.append(SeedData.demoTrip(me: account))
            data.placeNames.merge(SeedData.demoPlaceNames) { _, seeded in seeded }
        }
        data.signedInWithApple = true
        save()
        await refresh()
    }

    /// Noon on `date`'s calendar day at the trip's destination, as a date on this phone's
    /// calendar with the same year, month and day. The reverse of `sameDay`, for date pickers.
    static func localDay(_ date: Date, from calendar: Calendar) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: date)
        parts.hour = 12
        return Calendar.current.date(from: parts) ?? date
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

    /// A six-character code no trip on this phone, or in the seeded "server", already uses.
    /// 32^6 is about a billion codes, so a clash is rare, but it is checked anyway. Codes are
    /// only unique per phone until trips sync; a server would enforce it with a unique column.
    private func newInviteCode() -> String {
        let taken = Set(data.trips.map(\.inviteCode))
            .union(SeedData.joinableTrips().map(\.inviteCode))
            .union([SeedData.demoInviteCode])
        var code: String
        repeat {
            code = InviteCode.random()
        } while taken.contains(code)
        return code
    }
}
