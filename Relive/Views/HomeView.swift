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
    /// The trip whose context menu asked to delete or leave it, waiting for confirmation.
    @State private var removing: Trip?

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

    var body: some View {
        NavigationStack(path: $path) {
            globe
                .safeAreaInset(edge: .bottom, spacing: 0) { cards }
                // A custom top bar instead of the navigation bar, so its buttons are solid
                // white and easy to spot over the dark globe.
                .safeAreaInset(edge: .top, spacing: 0) { topBar }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: UUID.self) { TripDetailView(tripID: $0) }
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

    private var topBar: some View {
        HStack {
            Menu {
                if let me = store.me {
                    Section(store.isSignedInWithApple ? "Signed in with Apple as \(me.name)" : "Signed in as \(me.name)") {
                        if store.hasBackend && !store.isSignedInWithApple {
                            // Keeps this account's trips and makes it work on your other devices.
                            Button("Sign in with Apple", systemImage: "apple.logo") {
                                Task { await linkApple() }
                            }
                        }
                        Button("Reset sample trip", systemImage: "arrow.counterclockwise") {
                            store.resetDemo()
                        }
                    }
                }
            } label: {
                CircleIcon(systemName: "person.fill")
            }
            .accessibilityLabel("Profile")
            Spacer()
            Wordmark(size: 30, color: .white)
                .shadow(color: .black.opacity(0.5), radius: 6)
            Spacer()
            Menu {
                Button("New trip", systemImage: "plus") { showingNewTrip = true }
                Button("Join with a code", systemImage: "person.badge.plus") {
                    joinPrompt = JoinPrompt(code: "")
                }
            } label: {
                CircleIcon(systemName: "plus")
            }
            .accessibilityLabel("Add trip")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
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
                        if store.isOwner(of: trip) {
                            Button("Delete for everyone", systemImage: "trash", role: .destructive) {
                                removing = trip
                            }
                        } else {
                            Button("Leave trip", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                removing = trip
                            }
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .confirmationDialog(
            removing.map { store.isOwner(of: $0) ? "Delete \($0.name) for everyone?" : "Leave \($0.name)?" } ?? "",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { trip in
            if store.isOwner(of: trip) {
                Button("Delete for everyone", role: .destructive) { Task { await store.deleteTrip(trip.id) } }
            } else {
                Button("Leave trip", role: .destructive) { Task { await store.leaveTrip(trip.id) } }
            }
        } message: { trip in
            Text(store.isOwner(of: trip)
                 ? "Every member loses the trip and its shared album. This can't be undone."
                 : "It comes off your phone, along with any photos you added.")
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $focused)
        .contentMargins(.horizontal, 26, for: .scrollContent)
        .scrollIndicators(.hidden)
        .frame(height: 168)
        .padding(.bottom, 10)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No trips of your own yet")
                .font(Theme.title(24))
                .tracking(-0.5)
            Text("Start one, or join a friend's with their code.")
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 10) {
                Pill(title: "New trip", isOn: true) { showingNewTrip = true }
                Pill(title: "Join with a code", isOn: false) { joinPrompt = JoinPrompt(code: "") }
            }
            .padding(.top, 6)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.thermal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
        .hardShadow(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.trailing, 4)
        .padding(.bottom, 4)
    }

    /// Signs this account in with Apple from the profile menu.
    private func linkApple() async {
        do {
            let credential = try await AppleSignIn.request()
            try await store.signInWithApple(idToken: credential.idToken, nonce: credential.nonce, name: credential.name)
        } catch {
            guard !AppleSignIn.wasCancelled(error) else { return }
            store.actionProblem = error is URLError
                ? "Couldn't reach the server. Check your connection and try again."
                : error.localizedDescription
        }
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

/// A round button outlined in white with a white icon, readable on the dark globe.
private struct CircleIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(.black.opacity(0.25), in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .contentShape(Circle())
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

/// A trip as a ticket: its cover on the stub, torn off along a dotted perforation.
private struct TripCard: View {
    let trip: Trip
    /// Set when this is someone else's trip that they shared with you.
    var sharer: Member?

    private static let stub: CGFloat = 112

    var body: some View {
        let ticket = TicketShape(notchX: Self.stub)
        HStack(spacing: 0) {
            Color.black
                .frame(width: Self.stub)
                .frame(maxHeight: .infinity)
                .overlay { TripCover(trip: trip) }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: -8) {
                        ForEach(trip.members.prefix(4)) { Avatar(member: $0, size: 24) }
                    }
                    .padding(8)
                }
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                // The ticket's "class" line: whose trip it is.
                Text(sharer.map { "Shared by \($0.firstName)" } ?? "Your trip")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(sharer?.color ?? Theme.canary, in: Capsule())
                Spacer(minLength: 0)
                // Same type as the trip screen's banner. Long names shrink rather than being cut off.
                Text(trip.name)
                    .font(Theme.title(30))
                    .tracking(-0.8)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                Text(trip.placesText)
                    .font(Theme.title(17))
                    .tracking(-0.3)
                    .lineLimit(1)
                    .opacity(0.5)
                Text(trip.dateRangeText)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .opacity(0.75)
                    .padding(.top, 2)
            }
            .foregroundStyle(Theme.ink)
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                // The perforation between stub and ticket.
                Line()
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 6]))
                    .frame(width: 2)
                    .padding(.vertical, 12)
            }
        }
        .background(Theme.thermal)
        .clipShape(ticket)
        .overlay(ticket.stroke(Theme.ink, lineWidth: 2))
        .hardShadow(ticket)
        .padding(.trailing, 4)
        .padding(.bottom, 4)
    }
}

/// A vertical line down the middle of its frame.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
