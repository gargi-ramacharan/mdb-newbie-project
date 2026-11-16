import Photos
import UIKit

/// Photos from your camera roll that look like they belong to a trip and aren't pooled yet.
struct ScanResult: Sendable {
    /// Taken during the trip dates and near one of its places.
    var suggested: [TripPhoto] = []
    /// Taken during the trip dates but with no GPS.
    var noLocation: [TripPhoto] = []
    /// Taken during the trip dates but outside every place's radius. Left out.
    var elsewhereCount = 0

    var all: [TripPhoto] { suggested + noLocation }
}

enum PhotoScanner {
    static var status: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Finds your not-yet-pooled photos for a trip. Nothing is added to the trip here.
    static func scan(trip: Trip, me: Member) async -> ScanResult {
        if trip.isDemo {
            return sort(SeedData.demoCameraRoll(trip: trip, me: me), for: trip)
        }
        guard status == .authorized || status == .limited else { return ScanResult() }
        return await Task.detached(priority: .userInitiated) {
            sort(cameraRollPhotos(trip: trip, ownerID: me.id), for: trip)
        }.value
    }

    private static func sort(_ photos: [TripPhoto], for trip: Trip) -> ScanResult {
        var result = ScanResult()
        for photo in photos {
            if let lat = photo.latitude, let lon = photo.longitude {
                if trip.isNearPlaces(latitude: lat, longitude: lon) {
                    result.suggested.append(photo)
                } else {
                    result.elsewhereCount += 1
                }
            } else {
                result.noLocation.append(photo)
            }
        }
        return result
    }

    /// Camera-roll photos inside the trip dates that aren't in the album yet. Screenshots are skipped.
    private static func cameraRollPhotos(trip: Trip, ownerID: UUID) -> [TripPhoto] {
        let interval = trip.interval()
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            interval.start as NSDate, interval.end as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        var pooled = Set<String>()
        for photo in trip.photos {
            if case .asset(let id) = photo.ref { pooled.insert(id) }
        }

        var photos: [TripPhoto] = []
        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
            guard !pooled.contains(asset.localIdentifier),
                  !asset.mediaSubtypes.contains(.photoScreenshot),
                  let takenAt = asset.creationDate else { return }
            photos.append(TripPhoto(
                ownerID: ownerID,
                takenAt: takenAt,
                latitude: asset.location?.coordinate.latitude,
                longitude: asset.location?.coordinate.longitude,
                ref: .asset(asset.localIdentifier)
            ))
        }
        return photos
    }

    /// Loads a camera-roll photo scaled to roughly `side` pixels.
    static func image(for localIdentifier: String, side: CGFloat) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        // With this delivery mode Photos calls the handler exactly once.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
