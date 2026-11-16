import SwiftUI
import Photos

struct TripDetailView: View {
    let tripID: UUID
    @Environment(TripStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = Tab.album
    @State private var scan = ScanResult()
    @State private var access = PhotoScanner.status
    @State private var reviewing = false

    enum Tab: String, CaseIterable {
        case album = "Album"
        case map = "Map"
        case recap = "Recap"
    }

    var body: some View {
        if let trip = store.trip(tripID), let me = store.me {
            let stops = StopClusterer.stops(from: trip.photos)
            // Someone else's shared trip is view-only: nothing of yours is scanned or added.
            let sharer = store.sharer(of: trip)
            // Photos you already reviewed and skipped don't count as new.
            let newCount = scan.all.filter { !trip.skipped.contains($0.ref) }.count
            VStack(spacing: 0) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if sharer == nil {
                    notice(for: trip, newCount: newCount)
                }

                switch tab {
                case .album: AlbumView(trip: trip, sharer: sharer)
                case .map: TripMapView(trip: trip, stops: stops)
                case .recap: RecapView(trip: trip, stops: stops)
                }
            }
            .navigationTitle(trip.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !scan.all.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Review my photos", systemImage: "photo.badge.plus") { reviewing = true }
                    }
                }
                if sharer == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: "Join \"\(trip.name)\" on \(AppInfo.name): \(trip.inviteURL.absoluteString)\nOr enter the code \(trip.inviteCode) in the app.") {
                            Label("Invite", systemImage: "person.badge.plus")
                        }
                    }
                }
            }
            // Catch-up scan: when the trip opens, when the app comes back to the
            // foreground, and after photos are added.
            .task(id: "\(scenePhase)-\(trip.photos.count)") {
                guard scenePhase == .active, sharer == nil else { return }
                access = PhotoScanner.status
                scan = await PhotoScanner.scan(trip: trip, me: me)
            }
            .task(id: stops.map(\.nameKey)) {
                await store.resolveNames(for: stops)
            }
            .sheet(isPresented: $reviewing) {
                ReviewPhotosView(trip: trip, scan: scan) { added, skipped in
                    store.finishReview(tripID: trip.id, added: added, skipped: skipped)
                    scan = ScanResult()
                }
            }
        } else {
            ContentUnavailableView("Trip not found", systemImage: "questionmark.folder")
        }
    }

    @ViewBuilder
    private func notice(for trip: Trip, newCount: Int) -> some View {
        if newCount > 0 {
            NoticeSlip(
                text: newCount == 1
                    ? "1 new photo of yours matches this trip."
                    : "\(newCount) new photos of yours match this trip.",
                action: "Review"
            ) { reviewing = true }
        } else if !trip.isDemo {
            switch access {
            case .notDetermined:
                NoticeSlip(
                    text: "Let \(AppInfo.name) look through your photos for this trip. Nothing is added until you review it.",
                    action: "Allow"
                ) {
                    Task {
                        access = await PhotoScanner.requestAccess()
                        if let trip = store.trip(tripID), let me = store.me {
                            scan = await PhotoScanner.scan(trip: trip, me: me)
                        }
                    }
                }
            case .denied, .restricted:
                NoticeSlip(
                    text: "Photo access is off, so your trip photos can't be found.",
                    action: "Open Settings"
                ) { openSettings() }
            case .limited:
                NoticeSlip(
                    text: "\(AppInfo.name) can only see the photos you picked. Allow all photos to catch new ones.",
                    action: "Open Settings"
                ) { openSettings() }
            default:
                EmptyView()
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// A full-width canary slip for the one thing that needs your attention on a trip.
private struct NoticeSlip: View {
    let text: String
    let action: String
    var perform: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                perform()
            } label: {
                Text(action)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.thermal)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Theme.ink, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Theme.canary)
    }
}

/// The shared album: every pooled photo, grouped by day of the trip.
struct AlbumView: View {
    let trip: Trip
    /// Set when this is someone else's trip that they shared with you.
    var sharer: Member?
    @State private var viewing: TripPhoto?

    private var days: [(day: Int, photos: [TripPhoto])] {
        Dictionary(grouping: trip.photos) { trip.dayNumber(for: $0.takenAt) }
            .map { (day: $0.key, photos: $0.value.sorted { $0.takenAt < $1.takenAt }) }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    AvatarStack(members: trip.members)
                    Spacer(minLength: 8)
                    if let sharer {
                        Text("Shared by \(sharer.firstName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Invite code")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(trip.inviteCode)
                            .font(Theme.display(20, relativeTo: .subheadline))
                            .tracking(1.5)
                            .baselineOffset(-2)
                    }
                }
                .padding(.horizontal)

                if trip.photos.isEmpty {
                    ContentUnavailableView(
                        "No photos yet",
                        systemImage: "photo.on.rectangle",
                        description: Text("Photos you and your friends add to this trip show up here.")
                    )
                    .padding(.top, 40)
                }

                ForEach(days, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Day \(group.day)")
                                .font(Theme.display(30, relativeTo: .title2))
                            Spacer()
                            Text(trip.text(group.photos[0].takenAt, .dateTime.weekday(.wide).month().day()))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        PhotoGrid(photos: group.photos, trip: trip, onTap: { viewing = $0 }) { photo in
                            if let owner = trip.member(photo.ownerID) {
                                Avatar(member: owner, size: 22)
                                    .padding(5)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .sheet(item: $viewing) { PhotoViewer(photo: $0, trip: trip) }
    }
}
