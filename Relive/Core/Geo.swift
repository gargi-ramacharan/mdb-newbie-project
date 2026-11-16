import Foundation

enum Geo {
    /// Great-circle distance in kilometres (haversine).
    static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }

    /// Cache key for a coordinate, rounded to about 100 m.
    static func key(_ latitude: Double, _ longitude: Double) -> String {
        String(format: "%.3f,%.3f", latitude, longitude)
    }
}
