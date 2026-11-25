import Foundation

extension Trip {
    /// Takes the shared album's latest state of this trip, keeping what only this phone knows:
    /// photos still waiting to upload, the camera-roll reference of your own uploaded photos,
    /// and the photos you skipped.
    mutating func merge(remote: Trip) {
        name = remote.name
        startDate = remote.startDate
        endDate = remote.endDate
        places = remote.places
        members = remote.members
        inviteCode = remote.inviteCode
        ownerID = remote.ownerID
        coverPhotoID = remote.coverPhotoID
        if remote.coverPath != coverPath {
            // Someone else's upload replaced the cover; this phone's copy of the old one is stale.
            coverImageFile = nil
        }
        coverPath = remote.coverPath
        onServer = true

        // Album photos the server no longer has were removed (by their owner, or with a member
        // who left or was removed). Photos still waiting to upload stay.
        let remoteIDs = Set(remote.photos.map(\.id))
        photos.removeAll { $0.remotePath != nil && !remoteIDs.contains($0.id) }
        if let cover = coverPhotoID, !photos.contains(where: { $0.id == cover }) {
            coverPhotoID = nil
        }

        var indexByID: [UUID: Int] = [:]
        for (index, photo) in photos.enumerated() { indexByID[photo.id] = index }
        for theirs in remote.photos {
            if let index = indexByID[theirs.id] {
                // Same photo. Keep this phone's reference (it loads faster), note that it uploaded.
                photos[index].remotePath = theirs.remotePath
            } else {
                indexByID[theirs.id] = photos.count
                photos.append(theirs)
            }
        }
    }

    /// Re-attributes everything that belonged to one person id to another. Used when the same
    /// person gets a new account identity (for example, the first run after sync was added).
    mutating func replacePerson(_ old: UUID, with new: UUID) {
        guard old != new else { return }
        for index in members.indices where members[index].id == old { members[index].id = new }
        for index in photos.indices where photos[index].ownerID == old { photos[index].ownerID = new }
    }
}

/// Recognises camera-roll photos that are already in the album as a downloaded copy, which
/// happens after a reinstall: the album remembers them but this phone no longer knows which
/// camera-roll photo each one was. They match by the moment they were taken.
struct AlreadyUploaded {
    private let moments: Set<Int64>

    init(trip: Trip, owner: UUID) {
        moments = Set(trip.photos.compactMap { photo in
            guard photo.ownerID == owner, case .remote = photo.ref else { return nil }
            return Self.millis(photo.takenAt)
        })
    }

    func contains(_ takenAt: Date) -> Bool {
        let ms = Self.millis(takenAt)
        // The server keeps milliseconds, so allow one off for rounding.
        return moments.contains(ms) || moments.contains(ms - 1) || moments.contains(ms + 1)
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

enum AlbumPath {
    /// `<trip id>/<owner id>/<photo id>.jpg`, lower-case to match how the database prints uuids.
    /// The storage policies read the first two folders, so keep this layout in step with them.
    static func path(tripID: UUID, ownerID: UUID, photoID: UUID) -> String {
        "\(tripID.uuidString.lowercased())/\(ownerID.uuidString.lowercased())/\(photoID.uuidString.lowercased()).jpg"
    }
}
