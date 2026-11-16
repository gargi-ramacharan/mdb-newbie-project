import Foundation

/// One pin on the trip map: photos taken close together in space and time.
struct Stop: Identifiable, Hashable, Sendable {
    /// Time-ordered; every photo has a location.
    var photos: [TripPhoto]
    var latitude: Double
    var longitude: Double

    /// Stable while the stop's first photo stays the same.
    var id: UUID { photos[0].id }
    var start: Date { photos[0].takenAt }
    var end: Date { photos[photos.count - 1].takenAt }
    var nameKey: String { Geo.key(latitude, longitude) }
}

enum StopClusterer {
    /// A photo joins a stop when it is within this distance of the stop's centre...
    static let radiusKm = 0.3
    /// ...and no more than this long after the stop's latest photo.
    static let maxGap: TimeInterval = 2 * 60 * 60

    /// Groups located photos into stops, returned in time order.
    static func stops(from photos: [TripPhoto]) -> [Stop] {
        let located = photos.filter(\.hasLocation).sorted { $0.takenAt < $1.takenAt }
        var stops: [Stop] = []

        for photo in located {
            let lat = photo.latitude!, lon = photo.longitude!
            // Look back through recent stops so two people shooting at different
            // places at the same time don't keep splitting each other's stop.
            var joined = false
            for i in stops.indices.reversed() {
                if photo.takenAt.timeIntervalSince(stops[i].end) > maxGap { break }
                if Geo.distanceKm(stops[i].latitude, stops[i].longitude, lat, lon) <= radiusKm {
                    stops[i].photos.append(photo)
                    let n = Double(stops[i].photos.count)
                    stops[i].latitude += (lat - stops[i].latitude) / n
                    stops[i].longitude += (lon - stops[i].longitude) / n
                    joined = true
                    break
                }
            }
            if !joined {
                stops.append(Stop(photos: [photo], latitude: lat, longitude: lon))
            }
        }
        return stops.sorted { $0.start < $1.start }
    }
}
