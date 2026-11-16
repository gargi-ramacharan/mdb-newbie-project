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
    func signIn(name: String) {
        let me = Member(name: name, copy: 0)
        data.me = me
        data.trips.append(SeedData.demoTrip(me: me))
        data.placeNames.merge(SeedData.demoPlaceNames) { _, seeded in seeded }
        save()
    }

    /// Puts the demo trip back to "your photos are waiting for review".
    func resetDemo() {
        guard let me = data.me else { return }
        data.trips.removeAll(where: \.isDemo)
        data.trips.append(SeedData.demoTrip(me: me))
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
            inviteCode: Self.newInviteCode()
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
