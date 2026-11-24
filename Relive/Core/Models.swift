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
    /// A friend's photo, stored in the shared album. The value is its path in the photo bucket.
    case remote(String)
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
    /// Where this photo lives in the shared album once it has uploaded. `nil` means it is
    /// only on this phone so far. Optional so trips saved before sync existed still load.
    var remotePath: String?

    var hasLocation: Bool { latitude != nil && longitude != nil }

    /// Yours, reviewed, and still waiting to upload to the shared album.
    func needsUpload(by me: UUID) -> Bool {
        guard ownerID == me, remotePath == nil, case .asset = ref else { return false }
        return true
    }
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
    /// Who runs the trip: only they can remove members or delete it for everyone.
    /// `nil` in trips saved before owners existed; the first member is the owner then.
    var ownerID: UUID?
    /// An album photo picked as the cover. `nil` picks one automatically.
    var coverPhotoID: UUID?
    /// File name of a cover photo the owner uploaded. Wins over `coverPhotoID`.
    var coverImageFile: String?
    /// Where an uploaded cover lives in the shared album, so every member sees it.
    var coverPath: String?
    /// True once the trip exists on the server. Such a trip disappears from this phone when
    /// the server no longer lists it (it was deleted, or you were removed). Optional so
    /// trips saved before sync still load.
    var onServer: Bool?

    /// The owner's member id.
    var ownerMemberID: UUID? { ownerID ?? members.first?.id }

    func isOwner(_ memberID: UUID) -> Bool { ownerMemberID == memberID }

    /// Takes someone off the trip, along with the photos they added. The owner can't be removed.
    mutating func removeMember(_ memberID: UUID) {
        guard !isOwner(memberID) else { return }
        members.removeAll { $0.id == memberID }
        photos.removeAll { $0.ownerID == memberID }
        if let cover = coverPhotoID, !photos.contains(where: { $0.id == cover }) {
            coverPhotoID = nil
        }
    }

    /// Hands the trip to another member.
    mutating func makeOwner(_ memberID: UUID) {
        guard members.contains(where: { $0.id == memberID }) else { return }
        ownerID = memberID
    }

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

    /// The link to share. A web link when the app has an invite-link domain set up, so it
    /// works for people who don't have the app yet; otherwise a `relive://` link.
    var inviteURL: URL { InviteLink.url(code: inviteCode, host: InviteLink.configuredHost) }
}

/// Invite links: `https://<host>/join/CODE` once a domain is set up, else `relive://join/CODE`.
enum InviteLink {
    /// `InviteLinkHost` in Info.plist (set from the `INVITE_LINK_HOST` build setting).
    /// Blank until a domain is set up.
    static var configuredHost: String? {
        let host = (Bundle.main.object(forInfoDictionaryKey: "InviteLinkHost") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return host.isEmpty ? nil : host
    }

    static func url(code: String, host: String?) -> URL {
        if let host { return URL(string: "https://\(host)/join/\(code)")! }
        return URL(string: "relive://join/\(code)")!
    }

    /// The invite code in a link this app opened, or `nil` if it isn't an invite.
    static func code(in url: URL, host: String?) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.scheme?.lowercased() {
        case "relive":
            guard url.host?.lowercased() == "join", let code = parts.first else { return nil }
            return code
        case "https":
            guard let host, url.host?.lowercased() == host.lowercased(),
                  parts.count == 2, parts[0] == "join" else { return nil }
            return parts[1]
        default:
            return nil
        }
    }
}

enum InviteCode {
    /// No 0/O or 1/I, so codes read aloud or copied by hand don't get mixed up.
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func random() -> String {
        String((0..<6).map { _ in alphabet.randomElement()! })
    }
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
    /// Ids of trips other people shared with you that you left. Optional so files saved
    /// before leaving existed still load.
    var leftSharedTrips: Set<UUID>?
    /// True once this account is signed in with Apple (optional for older saved files).
    var signedInWithApple: Bool?
}
