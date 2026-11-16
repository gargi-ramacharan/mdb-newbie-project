import Foundation

/// The numbers printed on the receipt recap.
struct TripStats: Hashable, Sendable {
    struct MemberCount: Hashable, Sendable {
        var member: Member
        var count: Int
    }

    var photoCount = 0
    var stopCount = 0
    var dayCount = 0
    /// Unique city names in the order first visited.
    var cities: [String] = []
    /// Most photos first.
    var perMember: [MemberCount] = []
    var busiestDay: Date?
    var busiestDayCount = 0
    /// The stop furthest from the trip's first stop.
    var furthestName: String?
    var furthestKm = 0.0
    /// Length of the path through the stops in time order.
    var pathKm = 0.0

    static func compute(
        trip: Trip,
        stops: [Stop],
        names: [String: PlaceName]
    ) -> TripStats {
        let calendar = trip.calendar
        var stats = TripStats()
        stats.photoCount = trip.photos.count
        stats.stopCount = stops.count
        stats.dayCount = trip.dayCount()

        for stop in stops {
            if let city = names[stop.nameKey]?.city, !stats.cities.contains(city) {
                stats.cities.append(city)
            }
        }

        let byOwner = Dictionary(grouping: trip.photos, by: \.ownerID)
        stats.perMember = trip.members
            .map { MemberCount(member: $0, count: byOwner[$0.id]?.count ?? 0) }
            .sorted { ($0.count, $1.member.name) > ($1.count, $0.member.name) }

        let byDay = Dictionary(grouping: trip.photos) { calendar.startOfDay(for: $0.takenAt) }
        if let busiest = byDay.max(by: { ($0.value.count, $1.key) < ($1.value.count, $0.key) }) {
            stats.busiestDay = busiest.key
            stats.busiestDayCount = busiest.value.count
        }

        if let first = stops.first {
            for (i, stop) in stops.enumerated() where i > 0 {
                let fromStart = Geo.distanceKm(first.latitude, first.longitude, stop.latitude, stop.longitude)
                if fromStart > stats.furthestKm {
                    stats.furthestKm = fromStart
                    stats.furthestName = names[stop.nameKey]?.spot
                }
                let prev = stops[i - 1]
                stats.pathKm += Geo.distanceKm(prev.latitude, prev.longitude, stop.latitude, stop.longitude)
            }
        }
        return stats
    }
}
