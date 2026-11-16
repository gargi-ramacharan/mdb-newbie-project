// Checks the non-UI logic without Xcode. From the repo root:
//   swiftc Relive/Core/*.swift Scripts/LogicCheck/main.swift -o /tmp/relive-check && /tmp/relive-check
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

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
