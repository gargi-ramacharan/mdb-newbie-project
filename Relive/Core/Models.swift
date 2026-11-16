import Foundation

struct Member: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// Which copy-paper colour this person gets, for their avatar and seeded photos.
    var copy: Int

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }
}

/// A destination on the trip. Photos within `radiusKm` of any place count as "on the trip".
struct Place: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusKm: Double = 50
    /// Time zone identifier of the place, e.g. "Europe/Lisbon". `nil` means this phone's time zone.
    var timeZoneID: String?
}

/// Where a pooled photo's pixels come from.
enum PhotoRef: Codable, Hashable, Sendable {
    /// `PHAsset.localIdentifier` in this phone's camera roll.
    case asset(String)
    /// A drawn stand-in used by the seeded demo trip.
    case placeholder(symbol: String, hue: Double)
}

struct TripPhoto: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var ownerID: UUID
    var takenAt: Date
    var latitude: Double?
    var longitude: Double?
    var ref: PhotoRef

    var hasLocation: Bool { latitude != nil && longitude != nil }
}

struct Trip: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// Any moment on the first day.
    var startDate: Date
    /// Any moment on the last day (inclusive).
    var endDate: Date
    var places: [Place]
    var members: [Member]
    var inviteCode: String
    var photos: [TripPhoto] = []
    /// Camera-roll photos you reviewed and chose not to add. They aren't suggested again.
    var skipped: Set<PhotoRef> = []
    var isDemo = false

    /// A calendar in the time zone of the trip's first place, so "day 1" means day 1
    /// at the destination even when the photos are scanned back home.
    var calendar: Calendar {
        var calendar = Calendar.current
        if let id = places.first?.timeZoneID, let zone = TimeZone(identifier: id) {
            calendar.timeZone = zone
        }
        return calendar
    }

    /// Midnight of the first day up to midnight after the last day, at the destination.
    func interval() -> DateInterval {
        let start = calendar.startOfDay(for: startDate)
        let lastDay = calendar.startOfDay(for: max(endDate, startDate))
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        return DateInterval(start: start, end: end)
    }

    func dayCount() -> Int {
        let i = interval()
        return max(1, calendar.dateComponents([.day], from: i.start, to: i.end).day ?? 1)
    }

    /// 1-based day of the trip a date falls on.
    func dayNumber(for date: Date) -> Int {
        let start = calendar.startOfDay(for: startDate)
        let day = calendar.startOfDay(for: date)
        return (calendar.dateComponents([.day], from: start, to: day).day ?? 0) + 1
    }

    func hasEnded(now: Date = Date()) -> Bool {
        now >= interval().end
    }

    func member(_ id: UUID) -> Member? { members.first { $0.id == id } }

    /// True when the coordinate is within the radius of any of the trip's places.
    func isNearPlaces(latitude: Double, longitude: Double) -> Bool {
        places.contains {
            Geo.distanceKm($0.latitude, $0.longitude, latitude, longitude) <= $0.radiusKm
        }
    }

    var inviteURL: URL { URL(string: "relive://join/\(inviteCode)")! }
}

/// A reverse-geocoded name for a spot on the map.
struct PlaceName: Codable, Hashable, Sendable {
    var spot: String
    var city: String?
}

/// Everything the app persists.
struct AppData: Codable, Sendable {
    var me: Member?
    var trips: [Trip] = []
    /// Cache of reverse-geocoded names, keyed by `Geo.key`.
    var placeNames: [String: PlaceName] = [:]
}
