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

    init(repository: TripRepository = LocalTripRepository()) {
        self.repository = repository
        self.data = repository.load() ?? AppData()
    }

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
    func signIn(name: String) {
        let me = Member(name: name, copy: 0)
        data.me = me
        data.trips.append(SeedData.demoTrip(me: me))
        data.placeNames.merge(SeedData.demoPlaceNames) { _, seeded in seeded }
        save()
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

    @discardableResult
    func createTrip(name: String, startDate: Date, endDate: Date, places: [Place]) -> Trip? {
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
        data.trips.append(trip)
        save()
        return trip
    }

    func join(code rawCode: String) -> JoinResult {
        let code = rawCode.uppercased().filter { $0.isLetter || $0.isNumber }
        if let existing = data.trips.first(where: { $0.inviteCode == code }) {
            return .alreadyMember(existing)
        }
        guard let me = data.me, var trip = repository.findTrip(inviteCode: code) else {
            return .notFound
        }
        trip.members.append(me)
        data.trips.append(trip)
        save()
        return .joined(trip)
    }

    /// Ends a review: `added` joins the album, `skipped` is remembered so it isn't suggested again.
    func finishReview(tripID: UUID, added: [TripPhoto], skipped: [TripPhoto]) {
        guard let index = data.trips.firstIndex(where: { $0.id == tripID }) else { return }
        data.trips[index].photos.append(contentsOf: added)
        data.trips[index].skipped.formUnion(skipped.map(\.ref))
        data.trips[index].skipped.subtract(added.map(\.ref))
        save()
    }

    /// Takes one of your photos out of a trip's album. It isn't suggested again.
    func removePhoto(_ photoID: UUID, from tripID: UUID) {
        guard let me = data.me,
              let index = data.trips.firstIndex(where: { $0.id == tripID }),
              let photo = data.trips[index].photos.first(where: { $0.id == photoID }),
              photo.ownerID == me.id else { return }
        data.trips[index].photos.removeAll { $0.id == photoID }
        data.trips[index].skipped.insert(photo.ref)
        if data.trips[index].coverPhotoID == photoID {
            data.trips[index].coverPhotoID = nil
        }
        save()
    }

    /// True when you run this trip and can manage its members or delete it.
    func isOwner(of trip: Trip) -> Bool {
        guard let me = data.me else { return false }
        return trip.isOwner(me.id)
    }

    /// Owner only: saves changes to a trip's name, dates, places and cover. Dates are
    /// calendar days as picked on this phone, like `createTrip`.
    func updateTrip(
        _ id: UUID, name: String, startDate: Date, endDate: Date, places: [Place],
        coverPhotoID: UUID?, coverImageFile: String?
    ) {
        guard let index = data.trips.firstIndex(where: { $0.id == id }),
              isOwner(of: data.trips[index]) else { return }
        var trip = data.trips[index]
        trip.name = name
        trip.places = places
        trip.coverPhotoID = coverPhotoID
        if let old = trip.coverImageFile, old != coverImageFile {
            CoverImages.delete(old)
        }
        trip.coverImageFile = coverImageFile
        // The places decide the trip's time zone, so pin the days after they are set.
        trip.startDate = Self.sameDay(startDate, in: trip.calendar)
        trip.endDate = Self.sameDay(max(endDate, startDate), in: trip.calendar)
        data.trips[index] = trip
        save()
    }

    /// Owner only: takes a member off the trip, with the photos they added.
    func removeMember(_ memberID: UUID, from tripID: UUID) {
        guard let index = data.trips.firstIndex(where: { $0.id == tripID }),
              isOwner(of: data.trips[index]) else { return }
        data.trips[index].removeMember(memberID)
        save()
    }

    /// Owner only: hands the trip to another member.
    func makeOwner(_ memberID: UUID, of tripID: UUID) {
        guard let index = data.trips.firstIndex(where: { $0.id == tripID }),
              isOwner(of: data.trips[index]) else { return }
        data.trips[index].makeOwner(memberID)
        save()
    }

    /// Takes you off a trip you don't own, or hides a trip someone shared with you. It
    /// disappears from this phone along with any photos you added; an owner has to hand
    /// the trip on first, or delete it.
    func leaveTrip(_ id: UUID) {
        if let trip = data.trips.first(where: { $0.id == id }) {
            guard !isOwner(of: trip) else { return }
            // Nothing syncs yet, so leaving only drops this phone's copy. With a server this
            // would call `trip.removeMember(me.id)` there instead.
            data.trips.removeAll { $0.id == id }
        } else if allSharedTrips.contains(where: { $0.id == id }) {
            data.leftSharedTrips = (data.leftSharedTrips ?? []).union([id])
        } else {
            return
        }
        save()
    }

    /// Owner only: deletes the trip for everyone on it.
    func deleteTrip(_ id: UUID) {
        guard let trip = data.trips.first(where: { $0.id == id }), isOwner(of: trip) else { return }
        if let file = trip.coverImageFile { CoverImages.delete(file) }
        data.trips.removeAll { $0.id == id }
        save()
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
