import SwiftUI
import CoreLocation

/// Re:live is clean and photo-led: white screens, soft grey cards, big tight sans-serif
/// titles, and black pills for what's selected. The tickets on the home screen and the
/// receipt recap keep a little print-shop character. The app is always light.
enum Theme {
    /// Warm near-black print ink.
    static let ink = Color(red: 0.122, green: 0.110, blue: 0.094)
    /// Thermal receipt paper, and the face of tickets and cards.
    static let thermal = Color.white
    /// Screen background.
    static let paper = Color.white
    /// Soft grey for cards, pills and form backgrounds.
    static let card = Color(red: 0.949, green: 0.949, blue: 0.945)
    /// Mustard: your colour, and the app's highlight.
    static let canary = Color(red: 0.949, green: 0.757, blue: 0.306)
    /// Tomato red, for actions.
    static let tomato = Color(red: 0.886, green: 0.255, blue: 0.169)
    static let orange = Color(red: 0.933, green: 0.482, blue: 0.188)
    static let teal = Color(red: 0.557, green: 0.741, blue: 0.714)
    static let sage = Color(red: 0.580, green: 0.682, blue: 0.549)
    static let lilac = Color(red: 0.671, green: 0.639, blue: 0.855)
    /// One flat colour per person. Ink text is readable on all of them.
    static let copies: [Color] = [canary, orange, teal, sage, lilac]

    /// Numerals and small titles: DIN Condensed, the face of tickets and transit signs.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("DINCondensed-Bold", size: size, relativeTo: style)
    }

    /// Poster face for the home screen's tickets: Futura Condensed ExtraBold, in capitals.
    static func poster(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Futura-CondensedExtraBold", size: size, relativeTo: style)
    }

    /// Big, tight sans-serif titles. Pair with `.tracking(-size * 0.025)`.
    static func title(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
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
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
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
            Theme.card
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

/// A whole photo at its own aspect ratio, as large as fits. For the photo viewer.
struct FullPhoto: View {
    let photo: TripPhoto
    let paper: Color
    @State private var image: UIImage?

    var body: some View {
        switch photo.ref {
        case .asset(let id):
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: id) {
                image = await PhotoScanner.image(for: id, side: 2400, contentMode: .aspectFit)
            }
        case .remote(let path):
            RemoteImage(path: path, side: 2400, fit: true)
        case .placeholder(let symbol, _):
            // The seeded stand-ins are drawn square.
            PlaceholderPhoto(symbol: symbol, paper: paper)
                .aspectRatio(1, contentMode: .fit)
        }
    }
}

/// A photo from the shared album, downloaded on demand and cached on this phone.
struct RemoteImage: View {
    let path: String
    let side: CGFloat
    /// Fits the whole photo instead of filling the frame, for the photo viewer.
    var fit = false
    @Environment(TripStore.self) private var store
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if !fit { Theme.card }
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fit ? .fit : .fill)
            } else {
                ProgressView().tint(fit ? .white : nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Photos shown whole on black, at their own shape. Swipe left and right through them.
/// Shows who took each one and when, with a button to save it to your photo library.
struct PhotoViewer: View {
    let photos: [TripPhoto]
    let trip: Trip
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var currentID: UUID
    @State private var saveState = SaveState.idle
    @State private var confirmingRemove = false

    enum SaveState: Equatable {
        case idle, saving, saved, failed(String)
    }

    init(photos: [TripPhoto], startingAt photo: TripPhoto, trip: Trip) {
        self.photos = photos.contains(photo) ? photos : [photo]
        self.trip = trip
        _currentID = State(initialValue: photo.id)
    }

    private var current: TripPhoto? { photos.first { $0.id == currentID } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $currentID) {
                    ForEach(photos) { photo in
                        FullPhoto(photo: photo, paper: trip.paper(for: photo))
                            .tag(photo.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                if let current {
                    infoBar(for: current)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if photos.count > 1, let index = photos.firstIndex(where: { $0.id == currentID }) {
                    ToolbarItem(placement: .principal) {
                        Text("\(index + 1) of \(photos.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                if let current, current.ownerID == store.me?.id, store.trip(trip.id) != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Remove from album", systemImage: "trash") { confirmingRemove = true }
                            .tint(.white)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(.white)
                }
            }
            .onChange(of: currentID, initial: true) { _, _ in refreshSaveState() }
            .confirmationDialog("Remove this photo from the album?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    guard let current else { return }
                    Task {
                        if await store.removePhoto(current.id, from: trip.id) { dismiss() }
                    }
                }
            } message: {
                Text("It stays in your own photo library and won't be suggested for this trip again.")
            }
        }
        .preferredColorScheme(.dark)
        .actionProblemAlert()
    }

    private func infoBar(for photo: TripPhoto) -> some View {
        HStack(spacing: 10) {
            if let owner = trip.member(photo.ownerID) {
                Avatar(member: owner)
                VStack(alignment: .leading, spacing: 1) {
                    Text(owner.name).font(.subheadline.weight(.semibold))
                    Text(trip.text(photo.takenAt, Date.FormatStyle(date: .abbreviated, time: .shortened)))
                        .font(.caption)
                        .opacity(0.6)
                }
            }
            Spacer()
            saveButton(for: photo)
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 14)
    }

    /// Your own camera-roll photos are already in your library.
    private func isYours(_ photo: TripPhoto) -> Bool {
        if case .asset = photo.ref { return photo.ownerID == store.me?.id }
        return false
    }

    private func refreshSaveState() {
        guard let current else { return }
        saveState = isYours(current) || PhotoSaver.isSaved(current) ? .saved : .idle
    }

    @ViewBuilder
    private func saveButton(for photo: TripPhoto) -> some View {
        if saveState == .saved {
            Label("In your library", systemImage: "checkmark")
                .font(.footnote.weight(.medium))
                .opacity(0.7)
        } else {
            Button {
                Task {
                    saveState = .saving
                    do {
                        try await PhotoSaver.save(photo, paper: trip.paper(for: photo), download: store.albumPhoto)
                        if currentID == photo.id { saveState = .saved }
                    } catch {
                        saveState = .failed(error.localizedDescription)
                    }
                }
            } label: {
                Group {
                    if saveState == .saving {
                        ProgressView().tint(Theme.ink)
                    } else {
                        Label("Save", systemImage: "arrow.down.to.line")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.white, in: Capsule())
            }
            .disabled(saveState == .saving)
            .alert(
                "Couldn't save the photo",
                isPresented: Binding(get: { if case .failed = saveState { true } else { false } },
                                     set: { if !$0 { saveState = .idle } })
            ) {
                Button("OK") { saveState = .idle }
            } message: {
                if case .failed(let reason) = saveState { Text(reason) }
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(photos) { photo in
                Button {
                    onTap(photo)
                } label: {
                    PhotoTile(photo: photo, paper: trip.paper(for: photo))
                        .overlay { badge(photo) }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Shows the store's `actionProblem` (an owner or member action the server refused).
private struct ActionProblemAlert: ViewModifier {
    @Environment(TripStore.self) private var store

    func body(content: Content) -> some View {
        content.alert(
            "That didn't go through",
            isPresented: Binding(get: { store.actionProblem != nil }, set: { if !$0 { store.actionProblem = nil } })
        ) {
            Button("OK") { store.actionProblem = nil }
        } message: {
            Text(store.actionProblem ?? "")
        }
    }
}

extension View {
    func actionProblemAlert() -> some View { modifier(ActionProblemAlert()) }

    /// A printed, offset shadow in solid ink, drawn behind `shape`.
    func hardShadow<S: Shape>(_ shape: S, offset: CGFloat = 4) -> some View {
        background(shape.fill(Theme.ink).offset(x: offset, y: offset))
    }

    /// Soft grey behind a form's white rows, so sheets match the rest of the app.
    func paperForm() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.card)
    }
}

/// The "re:live" logo: lower-case Futura Bold, set tight, with a tomato colon.
struct Wordmark: View {
    var size: CGFloat
    var color: Color = Theme.ink

    var body: some View {
        (Text("re").foregroundStyle(color)
            + Text(":").foregroundStyle(Theme.tomato)
            + Text("live").foregroundStyle(color))
            .font(.custom("Futura-Bold", size: size, relativeTo: .largeTitle))
            .tracking(-size * 0.04)
            .accessibilityLabel(AppInfo.name)
    }
}

/// A rounded pill, black when selected and soft grey when not: the app's tabs and filters.
struct Pill: View {
    let title: String
    let isOn: Bool
    /// Off pills sit on white instead of grey, for use over maps and photos.
    var raised = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isOn ? .white : Theme.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(isOn ? Theme.ink : (raised ? .white : Theme.card), in: Capsule())
                .shadow(color: .black.opacity(raised ? 0.12 : 0), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A ticket: rounded corners, and a half-round notch top and bottom at `notchX`, where
/// the stub tears off.
struct TicketShape: Shape {
    var notchX: CGFloat
    var notchRadius: CGFloat = 9
    var corner: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let x = rect.minX + notchX
        let r = notchRadius
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + corner, y: rect.minY))
        path.addLine(to: CGPoint(x: x - r, y: rect.minY))
        path.addArc(center: CGPoint(x: x, y: rect.minY), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: corner)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: corner)
        path.addLine(to: CGPoint(x: x + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: x, y: rect.maxY), radius: r,
                    startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: corner)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: corner)
        path.closeSubpath()
        return path
    }
}

/// A postage stamp: a rectangle with round perforation bites along every edge.
struct StampShape: Shape {
    var bite: CGFloat = 5
    /// Distance between bite centres.
    var pitch: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Each edge in drawing order: its end point, and the angles that bite inward.
        let edges: [(from: CGPoint, to: CGPoint, start: Double, end: Double)] = [
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), 180, 0),
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), 270, 90),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY), 0, -180),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY), 90, -90),
        ]
        for edge in edges {
            let dx = edge.to.x - edge.from.x
            let dy = edge.to.y - edge.from.y
            let length = hypot(dx, dy)
            let count = max(1, Int((length - pitch) / pitch))
            // Centre the row of bites on the edge, clear of the corners.
            let gap = (length - CGFloat(count - 1) * pitch) / 2
            for i in 0..<count {
                let t = (gap + CGFloat(i) * pitch) / length
                let center = CGPoint(x: edge.from.x + dx * t, y: edge.from.y + dy * t)
                path.addArc(center: center, radius: bite,
                            startAngle: .degrees(edge.start), endAngle: .degrees(edge.end), clockwise: true)
            }
            path.addLine(to: edge.to)
        }
        path.closeSubpath()
        return path
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
