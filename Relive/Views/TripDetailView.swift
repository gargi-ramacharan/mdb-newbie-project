import SwiftUI
import Photos

struct TripDetailView: View {
    let tripID: UUID
    @Environment(TripStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var tab = Tab.album
    @State private var scan = ScanResult()
    @State private var access = PhotoScanner.status
    @State private var reviewing = false
    @State private var editing = false
    /// Set when you left or deleted the trip in the edit sheet; done once the sheet closes.
    @State private var pendingExit: EditTripView.Exit?
    /// The trip as last seen, so the screen still has something to show while it closes
    /// after the trip is left or deleted.
    @State private var lastSeen: Trip?

    enum Tab: String, CaseIterable {
        case album = "Album"
        case map = "Map"
        case recap = "Recap"
    }

    var body: some View {
        if let trip = store.trip(tripID) ?? lastSeen, let me = store.me {
            let stops = StopClusterer.stops(from: trip.photos)
            // Someone else's shared trip is view-only: nothing of yours is scanned or added.
            let sharer = store.sharer(of: trip)
            // Photos you already reviewed and skipped don't count as new.
            let newCount = scan.all.filter { !trip.skipped.contains($0.ref) }.count
            VStack(spacing: 0) {
                TripHero(trip: trip)

                HStack(spacing: 8) {
                    ForEach(Tab.allCases, id: \.self) { option in
                        Pill(title: option.rawValue, isOn: tab == option) { tab = option }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                if sharer == nil {
                    notice(for: trip, newCount: newCount)
                }

                switch tab {
                case .album: AlbumView(trip: trip, sharer: sharer)
                case .map: TripMapView(trip: trip, stops: stops)
                case .recap: RecapView(trip: trip, stops: stops)
                }
            }
            // The hero runs up under the status and navigation bars, so the tabs sit right below it.
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .bottomTrailing) {
                // Only the owner edits; everyone else sees the info read-only, and can leave.
                EditTripButton(canEdit: store.isOwner(of: trip)) { editing = true }
                    .padding(20)
            }
            .onChange(of: store.trip(tripID), initial: true) { _, live in
                if let live { lastSeen = live }
            }
            .background(Theme.paper)
            // The hero's title stands in for the navigation title; the bar floats over the photo.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            // White bar buttons over the dark photo.
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if !scan.all.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Review my photos", systemImage: "photo.badge.plus") { reviewing = true }
                            .tint(.white)
                    }
                }
                if sharer == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: "Join \"\(trip.name)\" on \(AppInfo.name): \(trip.inviteURL.absoluteString)\nOr enter the code \(trip.inviteCode) in the app.") {
                            Label("Invite", systemImage: "person.badge.plus")
                        }
                        .tint(.white)
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
            .sheet(isPresented: $editing, onDismiss: finishExit) {
                EditTripView(trip: trip) { pendingExit = $0 }
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
                        if let trip = store.trip(tripID) ?? lastSeen, let me = store.me {
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

    /// Leaves or deletes the trip after the edit sheet has closed, then goes back home.
    private func finishExit() {
        guard let exit = pendingExit else { return }
        pendingExit = nil
        switch exit {
        case .left: store.leaveTrip(tripID)
        case .deleted: store.deleteTrip(tripID)
        }
        dismiss()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// The top of a trip: its cover edge to edge, under the navigation bar, with its name big
/// across the bottom. Long names wrap, then shrink, rather than being cut off.
private struct TripHero: View {
    let trip: Trip

    var body: some View {
        Color.black
            .frame(height: 270)
            .overlay { TripCover(trip: trip) }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.35), location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: .clear, location: 0.45),
                        .init(color: .black.opacity(0.6), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    Text(trip.name)
                        .font(Theme.title(44))
                        .tracking(-1.2)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                    Text(trip.placesText)
                        .font(Theme.title(24))
                        .tracking(-0.5)
                        .lineLimit(1)
                        .opacity(0.65)
                    Text(trip.dateRangeText)
                        .font(.footnote.weight(.medium))
                        .opacity(0.8)
                        .padding(.top, 4)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.top, 100)
                .padding(.bottom, 22)
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32, style: .continuous))
    }
}

/// The round button in the bottom-right corner that opens the trip's info, editable or not.
private struct EditTripButton: View {
    var canEdit: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: canEdit ? "pencil" : "info")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Theme.ink, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(canEdit ? "Edit trip info" : "Trip info")
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.ink, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.ink)
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
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
                        HStack(spacing: 8) {
                            Text("Invite code")
                                .font(.caption)
                                .opacity(0.55)
                            Text(trip.inviteCode)
                                .font(.subheadline.weight(.semibold))
                                .tracking(1)
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.card, in: Capsule())
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
                                .font(Theme.title(26))
                                .tracking(-0.6)
                            Spacer()
                            Text(trip.text(group.photos[0].takenAt, .dateTime.weekday(.wide).month().day()))
                                .font(.subheadline)
                                .opacity(0.55)
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
        // Room for the edit button in the bottom-right corner.
        .contentMargins(.bottom, 80, for: .scrollContent)
        .sheet(item: $viewing) { PhotoViewer(photos: days.flatMap(\.photos), startingAt: $0, trip: trip) }
    }
}
