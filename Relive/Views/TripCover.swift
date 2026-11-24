import SwiftUI
import MapKit

/// Real imagery of a place from Apple Maps: a tilted aerial view. Needs a network connection.
/// (Street-level Look Around photos were tried first, but at an arbitrary coordinate
/// they are as likely to show a building site as a landmark.)
enum PlaceImagery {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(at coordinate: CLLocationCoordinate2D, size: CGSize) async -> UIImage? {
        let key = "\(Geo.key(coordinate.latitude, coordinate.longitude))-\(Int(size.width))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let options = MKMapSnapshotter.Options()
        options.camera = MKMapCamera(lookingAtCenter: coordinate, fromDistance: 1500, pitch: 62, heading: 30)
        options.size = size
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        guard let image = try? await MKMapSnapshotter(options: options).start().image else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

extension Place {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension Trip {
    /// Where to look for cover imagery: the busiest stops first, then the trip's places.
    var coverSpots: [CLLocationCoordinate2D] {
        let busiest = StopClusterer.stops(from: photos).sorted { $0.photos.count > $1.photos.count }
        return busiest.prefix(3).map(\.coordinate) + places.map(\.coordinate)
    }

    /// The album photo picked as the cover, if it is still in the album.
    var chosenCover: TripPhoto? {
        guard let coverPhotoID else { return nil }
        return photos.first { $0.id == coverPhotoID }
    }

    /// The first real camera-roll photo in the album, if there is one.
    var coverAssetID: String? {
        for photo in photos {
            if case .asset(let id) = photo.ref { return id }
        }
        return nil
    }
}

/// A trip's cover: a photo the owner uploaded, or the album photo they picked, or one of
/// its own photos when it has real ones, otherwise an aerial view of where it went. Fills
/// whatever frame it is given; the caller clips.
struct TripCover: View {
    let trip: Trip
    @State private var image: UIImage?

    var body: some View {
        Theme.ink
            .overlay {
                if let file = trip.coverImageFile, let uploaded = CoverImages.load(file) {
                    Image(uiImage: uploaded)
                        .resizable()
                        .scaledToFill()
                } else if let chosen = trip.chosenCover {
                    switch chosen.ref {
                    case .asset(let id):
                        AssetImage(localIdentifier: id, side: 1000)
                    case .placeholder(let symbol, _):
                        PlaceholderPhoto(symbol: symbol, paper: trip.paper(for: chosen))
                    }
                } else if let id = trip.coverAssetID {
                    AssetImage(localIdentifier: id, side: 1000)
                } else if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            // Re-run when the picked cover changes, so clearing it brings the aerial view back.
            .task(id: "\(trip.id)-\(trip.coverPhotoID?.uuidString ?? "auto")-\(trip.coverImageFile ?? "")") {
                guard trip.coverImageFile == nil, trip.chosenCover == nil, trip.coverAssetID == nil else { return }
                guard let spot = trip.coverSpots.first else { return }
                let found = await PlaceImagery.image(at: spot, size: CGSize(width: 900, height: 1100))
                withAnimation(.easeOut(duration: 0.5)) { image = found }
            }
    }
}

/// Shrinks a little while pressed, then springs back.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
