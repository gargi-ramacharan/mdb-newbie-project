import SwiftUI
import CoreLocation

/// Re:live borrows its look from receipt books: carbon-copy violet ink on thermal
/// paper, and one coloured copy sheet per person.
enum Theme {
    /// Carbon-copy violet. Fixed in light and dark mode; use `.tint` where it must adapt.
    static let ink = Color(red: 0.161, green: 0.149, blue: 0.478)
    /// Thermal paper white.
    static let thermal = Color(red: 0.968, green: 0.972, blue: 0.965)
    static let canary = Color(red: 1.0, green: 0.894, blue: 0.369)
    /// Copy-paper colours, one per person. Ink text is readable on all of them.
    static let copies: [Color] = [
        canary,
        Color(red: 0.973, green: 0.706, blue: 0.769),   // pink
        Color(red: 0.710, green: 0.835, blue: 0.961),   // sky
        Color(red: 0.749, green: 0.898, blue: 0.784),   // mint
        Color(red: 0.953, green: 0.745, blue: 0.353),   // goldenrod
    ]

    /// Titles and numerals: DIN Condensed, the face of tickets and transit signs.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("DINCondensed-Bold", size: size, relativeTo: style)
    }

    /// Receipt print only.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Member {
    var color: Color { Theme.copies[abs(copy) % Theme.copies.count] }
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

extension Trip {
    /// Formats a date in the trip's time zone, so a 3 pm photo reads 3 pm wherever you are now.
    func text(_ date: Date, _ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    var dateRangeText: String {
        let day = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(text(startDate, day)) – \(text(endDate, day.year()))"
    }

    var placesText: String { places.map(\.name).joined(separator: ", ") }

    /// "3 days in Lisbon, Sintra"
    var summaryText: String {
        let days = dayCount()
        return "\(days) \(days == 1 ? "day" : "days") in \(placesText)"
    }

    func timeRangeText(for stop: Stop) -> String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        let startText = text(stop.start, time)
        let endText = text(stop.end, time)
        return startText == endText ? startText : "\(startText) – \(endText)"
    }

    func paper(for photo: TripPhoto) -> Color {
        member(photo.ownerID)?.color ?? Theme.thermal
    }
}

extension Stop {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct Avatar: View {
    let member: Member
    var size: CGFloat = 28

    var body: some View {
        Text(member.initials)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(member.color, in: Circle())
            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
    }
}

struct AvatarStack: View {
    let members: [Member]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(members.prefix(5)) { Avatar(member: $0) }
        }
    }
}

/// A square photo: a real camera-roll image, or a stand-in printed on its owner's copy colour.
struct PhotoTile: View {
    let photo: TripPhoto
    /// Copy colour of the person who took it. Only seeded stand-ins use it.
    let paper: Color
    /// Pixel size to load camera-roll photos at.
    var loadSide: CGFloat = 360

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                switch photo.ref {
                case .asset(let id):
                    AssetImage(localIdentifier: id, side: loadSide)
                case .remote(let path):
                    RemoteImage(path: path, side: loadSide)
                case .placeholder(let symbol, _):
                    PlaceholderPhoto(symbol: symbol, paper: paper)
                }
            }
            .clipped()
    }
}

struct AssetImage: View {
    let localIdentifier: String
    let side: CGFloat
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: localIdentifier) {
            image = await PhotoScanner.image(for: localIdentifier, side: side)
        }
    }
}

/// A photo from the shared album, downloaded on demand and cached on this phone.
struct RemoteImage: View {
    let path: String
    let side: CGFloat
    @Environment(TripStore.self) private var store
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .task(id: path) {
            guard let data = await store.albumPhoto(path: path), let full = UIImage(data: data) else { return }
            // Decode at the size it is shown, so a grid of 1600 px photos stays light.
            let scale = min(1, side / max(full.size.width, full.size.height))
            let target = CGSize(width: full.size.width * scale, height: full.size.height * scale)
            image = await full.byPreparingThumbnail(ofSize: target) ?? full
        }
    }
}

struct PlaceholderPhoto: View {
    let symbol: String
    let paper: Color

    var body: some View {
        GeometryReader { geo in
            ZStack {
                paper
                Image(systemName: symbol)
                    .font(.system(size: geo.size.width * 0.3, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }
}

/// A photo shown large, with who took it and when.
struct PhotoViewer: View {
    let photo: TripPhoto
    let trip: Trip
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                PhotoTile(photo: photo, paper: trip.paper(for: photo), loadSide: 1400)
                HStack(spacing: 10) {
                    if let owner = trip.member(photo.ownerID) {
                        Avatar(member: owner)
                        Text(owner.name).font(.headline)
                    }
                    Spacer()
                    Text(trip.text(photo.takenAt, Date.FormatStyle(date: .abbreviated, time: .shortened)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A three-column grid of photos. `badge` draws on top of each tile.
struct PhotoGrid<Badge: View>: View {
    let photos: [TripPhoto]
    let trip: Trip
    var onTap: (TripPhoto) -> Void
    @ViewBuilder var badge: (TripPhoto) -> Badge

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(photos) { photo in
                Button {
                    onTap(photo)
                } label: {
                    PhotoTile(photo: photo, paper: trip.paper(for: photo))
                        .overlay { badge(photo) }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A sheet of paper with a torn zigzag edge on the chosen sides.
struct TornEdge: Shape {
    var top = true
    var bottom = true

    func path(in rect: CGRect) -> Path {
        let count = max(1, Int(rect.width / 9))
        let tooth = rect.width / CGFloat(count)
        let depth = tooth / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + (top ? depth : 0)))
        if top {
            for i in 0..<count {
                let x = rect.minX + CGFloat(i) * tooth
                path.addLine(to: CGPoint(x: x + tooth / 2, y: rect.minY))
                path.addLine(to: CGPoint(x: x + tooth, y: rect.minY + depth))
            }
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - (bottom ? depth : 0)))
        if bottom {
            for i in (0..<count).reversed() {
                let x = rect.minX + CGFloat(i) * tooth
                path.addLine(to: CGPoint(x: x + tooth / 2, y: rect.maxY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY - depth))
            }
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
