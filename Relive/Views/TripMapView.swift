import SwiftUI
import MapKit

/// The trip as pins in time order, joined by a path, one day at a time or all at once.
struct TripMapView: View {
    let trip: Trip
    let stops: [Stop]
    @Environment(TripStore.self) private var store
    /// `nil` shows the whole trip.
    @State private var day: Int?
    @State private var position: MapCameraPosition = .automatic
    @State private var openStop: Stop?

    private var days: [Int] {
        Array(Set(stops.map { trip.dayNumber(for: $0.start) })).sorted()
    }

    private var visible: [Stop] {
        guard let day else { return stops }
        return stops.filter { trip.dayNumber(for: $0.start) == day }
    }

    var body: some View {
        if stops.isEmpty {
            ContentUnavailableView(
                "Nothing on the map yet",
                systemImage: "map",
                description: Text("Photos that have a location show up here as stops.")
            )
            .frame(maxHeight: .infinity)
        } else {
            Map(position: $position) {
                if visible.count > 1 {
                    // Joins the photographed stops in time order. It is not a recorded GPS track.
                    MapPolyline(coordinates: visible.map(\.coordinate))
                        .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [1, 6]))
                }
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, stop in
                    Annotation(store.placeNames[stop.nameKey]?.spot ?? "", coordinate: stop.coordinate) {
                        Button {
                            openStop = stop
                        } label: {
                            StopPin(number: index + 1, photoCount: stop.photos.count)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        dayChip("Whole trip", value: nil)
                        ForEach(days, id: \.self) { dayChip("Day \($0)", value: $0) }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
            }
            .sheet(item: $openStop) { stop in
                StopSheet(trip: trip, stop: stop, name: store.placeNames[stop.nameKey])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func dayChip(_ title: String, value: Int?) -> some View {
        // Tapping a chip also re-frames its stops, so it doubles as "show everything again".
        Pill(title: title, isOn: day == value, raised: true) {
            day = value
            withAnimation { position = .automatic }
        }
    }
}

/// A numbered stop. The canary tag is how many photos were taken there.
private struct StopPin: View {
    let number: Int
    let photoCount: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Theme.thermal)
            .frame(width: 30, height: 30)
            .background(Theme.ink, in: Circle())
            .overlay(Circle().stroke(Theme.thermal, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                Text("\(photoCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Theme.canary, in: Capsule())
                    .offset(x: 11, y: -7)
            }
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

/// One stop's photos, with a switcher to see it through each person's camera.
struct StopSheet: View {
    let trip: Trip
    let stop: Stop
    let name: PlaceName?
    /// `nil` shows everyone's photos.
    @State private var ownerID: UUID?
    @State private var viewing: TripPhoto?

    private var owners: [Member] {
        trip.members.filter { member in stop.photos.contains { $0.ownerID == member.id } }
    }

    private var shown: [TripPhoto] {
        guard let ownerID else { return stop.photos }
        return stop.photos.filter { $0.ownerID == ownerID }
    }

    private var subtitle: String {
        let when = "Day \(trip.dayNumber(for: stop.start)), \(trip.timeRangeText(for: stop))"
        guard let city = name?.city else { return when }
        return "\(city). \(when)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(name?.spot ?? "Unnamed stop")
                        .font(Theme.title(30))
                        .tracking(-0.7)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ownerChip("Everyone", count: stop.photos.count, member: nil)
                        ForEach(owners) { member in
                            ownerChip(
                                member.firstName,
                                count: stop.photos.filter { $0.ownerID == member.id }.count,
                                member: member
                            )
                        }
                    }
                    .padding(.horizontal)
                }

                PhotoGrid(photos: shown, trip: trip, onTap: { viewing = $0 }) { _ in EmptyView() }
            }
            .padding(.top, 24)
        }
        .sheet(item: $viewing) { PhotoViewer(photos: shown, startingAt: $0, trip: trip) }
    }

    private func ownerChip(_ title: String, count: Int, member: Member?) -> some View {
        let isOn = ownerID == member?.id
        return Button {
            ownerID = member?.id
        } label: {
            HStack(spacing: 6) {
                if let member { Avatar(member: member, size: 20) }
                Text(title).fontWeight(.semibold)
                Text("\(count)").opacity(0.6)
            }
            .font(.subheadline)
            .foregroundStyle(isOn ? Theme.thermal : Color.primary)
            .padding(.leading, member == nil ? 14 : 8)
            .padding(.trailing, 14)
            .padding(.vertical, 7)
            .background(isOn ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Color(.secondarySystemFill)), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
