import SwiftUI

/// The welcome screen's postcards: photos of places around the world drifting slowly past,
/// each tipped a little like a card dropped on a table. Holds still when Reduce Motion is on.
struct PlaceCarousel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Points per second: slow enough to read as drifting, not scrolling.
    private static let speed: Double = 16
    private static let spacing: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let size = CGSize(width: (height * 0.74).rounded(), height: height)
            let loop = CGFloat(PlacePhoto.all.count) * (size.width + Self.spacing)
            TimelineView(.animation(paused: reduceMotion)) { context in
                let travelled = CGFloat(context.date.timeIntervalSinceReferenceDate * Self.speed)
                HStack(spacing: Self.spacing) {
                    // Drawn twice end to end so the row loops without a seam.
                    ForEach(0..<2, id: \.self) { _ in
                        ForEach(PlacePhoto.all) { place in
                            Postcard(place: place, size: size)
                        }
                    }
                }
                .offset(x: -travelled.truncatingRemainder(dividingBy: loop))
            }
            .frame(width: geo.size.width, height: height, alignment: .leading)
        }
        // Room for the tilted cards' corners.
        .padding(.vertical, 12)
        .accessibilityHidden(true)
    }
}

private struct Postcard: View {
    let place: PlacePhoto
    let size: CGSize

    var body: some View {
        Image(place.asset)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .overlay {
                LinearGradient(
                    stops: [.init(color: .black.opacity(0.6), location: 0), .init(color: .clear, location: 0.4)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            // Named at the top: the bottom of each card tucks under the sign-in form.
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.country.uppercased())
                        .font(.custom("Futura-Medium", size: 11))
                        .tracking(1.6)
                        .opacity(0.85)
                    Text(place.name)
                        .font(.custom("Futura-Bold", size: 22))
                        .tracking(-0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(.white)
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 2.5))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
            .rotationEffect(.degrees(place.tilt))
            .offset(y: place.tilt * 3)
    }
}

/// A bundled photo of a place, and who took it. The photos come from Wikimedia Commons;
/// most are licensed CC BY or CC BY-SA, which is why the credits are shown in the app.
struct PlacePhoto: Identifiable {
    var asset: String
    var name: String
    var country: String
    /// Degrees the card is tipped; alternating signs keep the row lively.
    var tilt: Double
    var author: String
    var license: String
    var source: URL

    var id: String { asset }

    static let all: [PlacePhoto] = [
        PlacePhoto(asset: "Places/santorini", name: "Santorini", country: "Greece", tilt: -2.5,
                   author: "Giles Laurent", license: "CC BY-SA 4.0",
                   source: URL(string: "https://commons.wikimedia.org/wiki/File:1000_Three_domes_of_Oia_in_Santorini_Photo_by_Giles_Laurent.jpg")!),
        PlacePhoto(asset: "Places/kyoto", name: "Kyoto", country: "Japan", tilt: 2,
                   author: "Martin Falbisoner", license: "CC BY-SA 4.0",
                   source: URL(string: "https://commons.wikimedia.org/wiki/File:Kiyomizu-dera,_Kyoto,_November_2016_-07.jpg")!),
        PlacePhoto(asset: "Places/banff", name: "Moraine Lake", country: "Canada", tilt: -1.5,
                   author: "Gorgo", license: "Public domain",
                   source: URL(string: "https://commons.wikimedia.org/wiki/File:Moraine_Lake_17092005.jpg")!),
        PlacePhoto(asset: "Places/paris", name: "Paris", country: "France", tilt: 2.5,
                   author: "Tristan Nitot", license: "CC BY-SA 3.0",
                   source: URL(string: "https://commons.wikimedia.org/wiki/File:Tour_eiffel_at_sunrise_from_the_trocadero.jpg")!),
        PlacePhoto(asset: "Places/machu-picchu", name: "Machu Picchu", country: "Peru", tilt: -2,
                   author: "Diego Delso", license: "CC BY-SA 4.0",
                   source: URL(string: "https://commons.wikimedia.org/wiki/File:Machu_Picchu,_Per%C3%BA,_2015-07-30,_DD_47.JPG")!),
        PlacePhoto(asset: "Places/sydney", name: "Sydney", country: "Australia", tilt: 1.5,
                   author: "Thomas Adams", license: "CC BY-SA 4.0",
                   source: URL(string: "https://commons.wikimedia.org/wiki/File:Sydneyoperahouse_at_night.jpg")!),
        PlacePhoto(asset: "Places/cappadocia", name: "Cappadocia", country: "Türkiye", tilt: -2.5,
                   author: "Benh LIEU SONG (Flickr)", license: "CC BY-SA 4.0",
                   source: URL(string: "https://commons.wikimedia.org/wiki/File:Cappadocia_Aerial_View_Landscape.jpg")!),
        PlacePhoto(asset: "Places/venice", name: "Venice", country: "Italy", tilt: 2,
                   author: "Benh LIEU SONG (Flickr)", license: "CC BY-SA 4.0",
                   source: URL(string: "https://commons.wikimedia.org/wiki/File:Venice_awakes_(20618763815).jpg")!),
        PlacePhoto(asset: "Places/iceland", name: "Skaftafell", country: "Iceland", tilt: -1.5,
                   author: "Martin Falbisoner", license: "CC BY-SA 4.0",
                   source: URL(string: "https://commons.wikimedia.org/wiki/File:View_from_Skaftafell_National_Park_July_2014_-2.JPG")!),
        PlacePhoto(asset: "Places/new-york", name: "New York", country: "USA", tilt: 2.5,
                   author: "King of Hearts", license: "CC BY-SA 4.0",
                   source: URL(string: "https://commons.wikimedia.org/wiki/File:Midtown_Manhattan_from_Jersey_City_September_2020_HDR.jpg")!),
        PlacePhoto(asset: "Places/nepal", name: "Himalayas", country: "Nepal", tilt: 1,
                   author: "Vyacheslav Argenberg", license: "CC BY 4.0",
                   source: URL(string: "https://commons.wikimedia.org/wiki/File:Chola_Mountain_Lake,_Nepal.jpg")!),
    ]
}

/// Who took the welcome screen's photos, as their licenses ask.
struct PhotoCreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PlacePhoto.all) { place in
                        Link(destination: place.source) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(place.name), \(place.country)")
                                    .font(.headline)
                                    .foregroundStyle(Theme.ink)
                                Text("\(place.author) · \(place.license)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    // After the last credit, so it never sits on top of the list.
                    Text("Photos from Wikimedia Commons. Tap one to see it there with its full license.")
                }
            }
            .navigationTitle("Photo credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

#Preview {
    PlaceCarousel()
        .frame(height: 260)
        .background(Theme.ink)
}
