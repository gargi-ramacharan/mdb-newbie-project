import SwiftUI
import MapKit

/// The home screen is a globe you can spin. It opens on the whole earth, then turns
/// to the trip in front; swiping the cards turns it from trip to trip. Your own trips
/// come first, then trips other people have shared with you.
struct HomeView: View {
    @Binding var incomingCode: String?
    @Environment(TripStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var path: [UUID] = []
    @State private var showingNewTrip = false
    @State private var joinPrompt: JoinPrompt?
    @State private var position: MapCameraPosition = .camera(wholeEarth)
    /// The trip whose card is in front and whose place the globe is showing.
    @State private var focused: UUID?

    struct JoinPrompt: Identifiable {
        let id = UUID()
        var code: String
    }

    /// Stands in for a trip in the card row when you have none of your own.
    private static let emptyID = UUID()

    /// Your trips, then the ones shared with you.
    private var allTrips: [Trip] { store.trips + store.sharedTrips }

    /// Ids of the cards in the row, in order.
    private var cardIDs: [UUID] {
        (store.trips.isEmpty ? [Self.emptyID] : []) + allTrips.map(\.id)
    }

    private static let wholeEarth = MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 30, longitude: 10),
        distance: globeDistance
    )

    /// Far enough out that the whole globe fits, so pins on other continents stay in view.
    private static let globeDistance: CLLocationDistance = 40_000_000

    /// Poster type for the home screen: Futura Condensed ExtraBold.
    static func poster(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Futura-CondensedExtraBold", size: size, relativeTo: style)
    }

    var body: some View {
        NavigationStack(path: $path) {
            globe
                .safeAreaInset(edge: .bottom, spacing: 0) { cards }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationDestination(for: UUID.self) { TripDetailView(tripID: $0) }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(AppInfo.name)
                            .font(Self.poster(30))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 6)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            if let me = store.me {
                                Section("Signed in as \(me.name)") {
                                    Button("Reset sample trip", systemImage: "arrow.counterclockwise") {
                                        store.resetDemo()
                                    }
                                }
                            }
                        } label: {
                            Label("Profile", systemImage: "person.crop.circle")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("New trip", systemImage: "plus") { showingNewTrip = true }
                            Button("Join with a code", systemImage: "person.badge.plus") {
                                joinPrompt = JoinPrompt(code: "")
                            }
                        } label: {
                            Label("Add trip", systemImage: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showingNewTrip) {
                    NewTripView { trip in show(trip) }
                }
                .sheet(item: $joinPrompt) { prompt in
                    JoinTripView(code: prompt.code) { trip in show(trip) }
                }
                .onChange(of: incomingCode, initial: true) { _, code in
                    guard let code else { return }
                    joinPrompt = JoinPrompt(code: code)
                    incomingCode = nil
                }
                .onChange(of: focused) { _, id in
                    fly(to: allTrips.first { $0.id == id })
                }
                .onChange(of: cardIDs) { _, ids in
                    // A deleted trip hands the globe to the next card; the first trip takes it from empty.
                    if let focused, ids.contains(focused) { return }
                    focused = ids.first
                }
                .task {
                    // The one orchestrated moment: hold on the whole earth, then turn to the trip.
                    guard focused == nil else { return }
                    try? await Task.sleep(for: .seconds(1.4))
                    if focused == nil { focused = cardIDs.first }
                }
        }
    }

    private var globe: some View {
        Map(position: $position) {
            ForEach(allTrips) { trip in
                if let place = trip.places.first {
                    // Your trips are canary with an ink outline; a shared trip takes its sharer's colour.
                    let sharer = store.sharer(of: trip)
                    Annotation(trip.name, coordinate: place.coordinate, anchor: .bottom) {
                        Button {
                            // The first tap brings a trip to the front; tapping the front pin opens it.
                            if focused == trip.id {
                                path = [trip.id]
                            } else {
                                withAnimation { focused = trip.id }
                            }
                        } label: {
                            TripPin(
                                fill: sharer?.color ?? Theme.canary,
                                outline: sharer == nil ? Theme.ink : .white,
                                isFront: focused == trip.id
                            )
                        }
                        .buttonStyle(PressScale())
                        .accessibilityLabel(trip.name)
                    }
                    // Only the trip in front is named, so the globe isn't covered in labels.
                    .annotationTitles(focused == trip.id ? .automatic : .hidden)
                }
            }
        }
        // Satellite imagery with place names, roads and businesses as you zoom in.
        .mapStyle(.hybrid(elevation: .realistic))
    }

    private var cards: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                if store.trips.isEmpty {
                    emptyCard
                        .containerRelativeFrame(.horizontal)
                        .id(Self.emptyID)
                }
                ForEach(allTrips) { trip in
                    let sharer = store.sharer(of: trip)
                    Button {
                        path = [trip.id]
                    } label: {
                        TripCard(trip: trip, sharer: sharer)
                    }
                    .buttonStyle(PressScale())
                    .contextMenu {
                        if sharer == nil {
                            Button("Delete trip", systemImage: "trash", role: .destructive) {
                                store.deleteTrip(trip.id)
                            }
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $focused)
        .contentMargins(.horizontal, 26, for: .scrollContent)
        .scrollIndicators(.hidden)
        .frame(height: 132)
        .padding(.bottom, 10)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No trips of your own yet")
                .font(Self.poster(26, relativeTo: .title2))
            Text("Start one, or join a friend's with their code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 10) {
                Button("New trip") { showingNewTrip = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.canary)
                    .foregroundStyle(Theme.ink)
                Button("Join with a code") { joinPrompt = JoinPrompt(code: "") }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
            .fontWeight(.semibold)
            .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    /// Opens a trip that was just created or joined, and turns the globe to it for the way back.
    private func show(_ trip: Trip) {
        focused = trip.id
        path = [trip.id]
    }

    private func fly(to trip: Trip?) {
        let camera: MapCamera
        if let place = trip?.places.first {
            // Stay out in space: the globe turns to the trip rather than diving into it.
            camera = MapCamera(centerCoordinate: place.coordinate, distance: Self.globeDistance)
        } else {
            camera = Self.wholeEarth
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 2.4)) {
            position = .camera(camera)
        }
    }
}

/// A map marker: a round head tapering to a point that sits on the place.
private struct TripPin: View {
    let fill: Color
    let outline: Color
    let isFront: Bool

    var body: some View {
        let width: CGFloat = isFront ? 34 : 24
        PinShape()
            .fill(fill)
            .overlay(PinShape().stroke(outline, lineWidth: 2.5))
            .overlay(alignment: .top) {
                Circle()
                    .fill(outline)
                    .frame(width: width * 0.34, height: width * 0.34)
                    .padding(.top, width * 0.33)
            }
            .frame(width: width, height: width * 1.36)
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
            // A finger-sized target, with the point still on the place.
            .frame(width: 48, height: 52, alignment: .bottom)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isFront)
    }
}

private struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        // Angle between straight down and the points where the sides leave the head.
        let spread = acos(radius / (tip.y - center.y)) * 180 / .pi
        var path = Path()
        path.move(to: tip)
        path.addArc(center: center, radius: radius, startAngle: .degrees(90 + spread), endAngle: .degrees(450 - spread), clockwise: false)
        path.closeSubpath()
        return path
    }
}

private struct TripCard: View {
    let trip: Trip
    /// Set when this is someone else's trip that they shared with you.
    var sharer: Member?

    var body: some View {
        HStack(spacing: 14) {
            Color.black
                .frame(width: 104, height: 104)
                .overlay { TripCover(trip: trip) }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: -8) {
                        ForEach(trip.members.prefix(4)) { Avatar(member: $0, size: 24) }
                    }
                    .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(trip.name)
                    .font(HomeView.poster(26, relativeTo: .title2))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Group {
                    Text(trip.dateRangeText)
                        .foregroundStyle(.secondary)
                    if let sharer {
                        Text("Shared by \(sharer.firstName)")
                            .fontWeight(.semibold)
                            .foregroundStyle(sharer.color)
                    } else {
                        Text(trip.placesText)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}
