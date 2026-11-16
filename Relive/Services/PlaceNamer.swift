import CoreLocation

enum PlaceNamer {
    /// Reverse-geocodes a coordinate into a spot name and its city. Needs a network connection.
    static func lookup(latitude: Double, longitude: Double) async -> PlaceName? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return nil
        }
        let city = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
        guard let spot = placemark.areasOfInterest?.first ?? placemark.name ?? placemark.subLocality ?? city else {
            return nil
        }
        return PlaceName(spot: spot, city: city)
    }
}
