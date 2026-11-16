import Foundation

/// The JSON the server speaks, and how it maps onto the app's own models.
/// Keys are spelled out (no snake_case conversion) because `Place` is stored as-is in a jsonb column.
enum Wire {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(format(date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Unreadable date: \(text)"))
            }
            return date
        }
        return decoder
    }()

    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Reads Postgres timestamps such as `2026-11-15T12:00:00+00:00` and
    /// `2026-11-15T12:00:00.123456+00:00` (microseconds, which ISO8601DateFormatter won't take).
    static func parseDate(_ text: String) -> Date? {
        var text = text
        if let dot = text.firstIndex(of: ".") {
            let start = text.index(after: dot)
            let end = text[start...].firstIndex { !$0.isNumber } ?? text.endIndex
            let millis = String(text[start..<end].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            text.replaceSubrange(start..<end, with: millis)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    // MARK: Rows

    /// The `select` that returns a trip with its members (and their names) and photos in one request.
    static let tripSelect = "id,name,start_date,end_date,places,invite_code,"
        + "trip_members(user_id,copy,joined_at,profiles(name)),"
        + "photos(id,trip_id,owner_id,taken_at,latitude,longitude,storage_path)"

    struct TripRow: Decodable {
        var id: UUID
        var name: String
        var startDate: Date
        var endDate: Date
        var places: [Place]
        var inviteCode: String
        var members: [MemberRow]
        var photos: [PhotoRow]

        enum CodingKeys: String, CodingKey {
            case id, name, places, photos
            case startDate = "start_date"
            case endDate = "end_date"
            case inviteCode = "invite_code"
            case members = "trip_members"
        }

        func makeTrip() -> Trip {
            let ordered = members.sorted { ($0.joinedAt ?? .distantPast) < ($1.joinedAt ?? .distantPast) }
            return Trip(
                id: id,
                name: name,
                startDate: startDate,
                endDate: endDate,
                places: places,
                members: ordered.map {
                    Member(id: $0.userID, name: $0.profile?.name ?? "Traveler", copy: $0.copy)
                },
                inviteCode: inviteCode,
                photos: photos.map(\.photo)
            )
        }
    }

    struct MemberRow: Decodable {
        var userID: UUID
        var copy: Int
        var joinedAt: Date?
        var profile: ProfileName?

        enum CodingKeys: String, CodingKey {
            case copy
            case userID = "user_id"
            case joinedAt = "joined_at"
            case profile = "profiles"
        }
    }

    struct ProfileName: Codable {
        var name: String
    }

    struct ProfileRow: Codable {
        var id: UUID
        var name: String
    }

    struct PhotoRow: Codable {
        var id: UUID
        var tripID: UUID
        var ownerID: UUID
        var takenAt: Date
        var latitude: Double?
        var longitude: Double?
        var storagePath: String

        enum CodingKeys: String, CodingKey {
            case id, latitude, longitude
            case tripID = "trip_id"
            case ownerID = "owner_id"
            case takenAt = "taken_at"
            case storagePath = "storage_path"
        }

        init(photo: TripPhoto, tripID: UUID, path: String) {
            id = photo.id
            self.tripID = tripID
            ownerID = photo.ownerID
            takenAt = photo.takenAt
            latitude = photo.latitude
            longitude = photo.longitude
            storagePath = path
        }

        var photo: TripPhoto {
            TripPhoto(id: id, ownerID: ownerID, takenAt: takenAt, latitude: latitude,
                      longitude: longitude, ref: .remote(storagePath), remotePath: storagePath)
        }
    }

    struct CreateTripArgs: Encodable {
        var p_id: UUID
        var p_name: String
        var p_start: Date
        var p_end: Date
        var p_places: [Place]
    }

    struct JoinTripArgs: Encodable {
        var p_code: String
    }
}
