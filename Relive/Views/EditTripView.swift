import SwiftUI
import PhotosUI

/// A trip's cover, name, dates, places and members. Its owner can change all of it, upload
/// a cover, manage who is on it, and delete it for everyone; anyone else sees it read-only
/// and can leave.
struct EditTripView: View {
    /// What happened to the trip, once the sheet has closed.
    enum Exit {
        case left
        case deleted
    }

    let trip: Trip
    /// Called instead of saving when you leave or delete the trip. The caller does the work,
    /// so the trip doesn't vanish from under the screens still showing it.
    var onExit: (Exit) -> Void
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var start: Date
    @State private var end: Date
    @State private var places: [Place]
    @State private var coverPhotoID: UUID?
    /// An uploaded cover's file name: the trip's own, or a new upload not saved yet.
    @State private var coverImageFile: String?
    /// The newest uploaded photo, kept as a choice even while another cover is selected.
    @State private var uploadedFile: String?
    /// Every file uploaded in this sheet, so the unused ones can be thrown away.
    @State private var uploads: [String] = []
    @State private var pickedCover: PhotosPickerItem?
    @State private var loadingCover = false
    @State private var searching = false
    @State private var removing: Member?
    @State private var confirmingLeave = false
    @State private var confirmingDelete = false
    /// Set when Save was tapped, so a new upload isn't cleaned up as abandoned.
    @State private var saved = false

    init(trip: Trip, onExit: @escaping (Exit) -> Void) {
        self.trip = trip
        self.onExit = onExit
        _name = State(initialValue: trip.name)
        // The pickers show days on this phone's calendar; the trip keeps them at the destination.
        _start = State(initialValue: TripStore.localDay(trip.startDate, from: trip.calendar))
        _end = State(initialValue: TripStore.localDay(trip.endDate, from: trip.calendar))
        _places = State(initialValue: trip.places)
        _coverPhotoID = State(initialValue: trip.chosenCover?.id)
        _coverImageFile = State(initialValue: trip.coverImageFile)
        _uploadedFile = State(initialValue: trip.coverImageFile)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The live trip, so member changes show as soon as they're made.
    private var current: Trip { store.trip(trip.id) ?? trip }

    private var isOwner: Bool { store.isOwner(of: current) }

    /// Only the owner edits. Handing the trip on mid-edit turns the sheet read-only.
    private var canEdit: Bool { isOwner }

    /// The trip as it will look with the cover being picked.
    private var preview: Trip {
        var preview = current
        if canEdit {
            preview.coverPhotoID = coverPhotoID
            preview.coverImageFile = coverImageFile
        }
        return preview
    }

    var body: some View {
        NavigationStack {
            Form {
                coverSection
                if canEdit {
                    editableInfo
                } else {
                    readOnlyInfo
                }
                membersSection
                exitSection
            }
            .paperForm()
            .navigationTitle(canEdit ? "Edit trip" : "Trip info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canEdit {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .fontWeight(.semibold)
                            .disabled(trimmedName.isEmpty || places.isEmpty || loadingCover)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .onChange(of: start) { _, newStart in
                if end < newStart { end = newStart }
            }
            .onChange(of: pickedCover) { _, item in
                guard let item else { return }
                Task { await upload(item) }
            }
            .onDisappear(perform: discardUnusedUploads)
            .sheet(isPresented: $searching) {
                PlaceSearchView { places.append($0) }
            }
            .confirmationDialog(
                "Remove \(removing?.firstName ?? "")?",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible,
                presenting: removing
            ) { member in
                Button("Remove \(member.firstName)", role: .destructive) {
                    store.removeMember(member.id, from: trip.id)
                }
            } message: { member in
                Text("\(member.firstName) and the photos they added will be taken off this trip.")
            }
            .confirmationDialog("Leave \(current.name)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Leave trip", role: .destructive) { exit(.left) }
            } message: {
                Text("It comes off your phone, along with any photos you added.")
            }
            .confirmationDialog("Delete \(current.name) for everyone?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete for everyone", role: .destructive) { exit(.deleted) }
            } message: {
                Text("Every member loses the trip and its shared album. This can't be undone.")
            }
        }
    }

    // MARK: Cover

    private var coverSection: some View {
        Section {
            Color.black
                .frame(height: 220)
                .overlay { TripCover(trip: preview) }
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(canEdit ? name : current.name)
                            .font(Theme.title(32))
                            .tracking(-0.8)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                        Text(current.dateRangeText)
                            .font(.subheadline.weight(.medium))
                            .opacity(0.75)
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                }
                .overlay {
                    if loadingCover {
                        ProgressView().tint(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if canEdit {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        PhotosPicker(selection: $pickedCover, matching: .images, photoLibrary: .shared()) {
                            choiceTile(selected: false) {
                                VStack(spacing: 4) {
                                    Image(systemName: "photo.badge.plus")
                                    Text("Upload").font(.caption2.weight(.semibold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Theme.ink)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Upload a cover photo")

                        if let file = uploadedFile, let uploaded = CoverImages.load(file) {
                            Button {
                                coverImageFile = file
                            } label: {
                                choiceTile(selected: coverImageFile == file) {
                                    Image(uiImage: uploaded).resizable().scaledToFill()
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Uploaded cover")
                        }

                        Button {
                            coverImageFile = nil
                            coverPhotoID = nil
                        } label: {
                            choiceTile(selected: coverImageFile == nil && coverPhotoID == nil) {
                                VStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                    Text("Auto").font(.caption2.weight(.semibold))
                                }
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.white)
                            }
                        }
                        .buttonStyle(.plain)

                        ForEach(current.photos.sorted { $0.takenAt < $1.takenAt }) { photo in
                            Button {
                                coverImageFile = nil
                                coverPhotoID = photo.id
                            } label: {
                                choiceTile(selected: coverImageFile == nil && coverPhotoID == photo.id) {
                                    PhotoTile(photo: photo, paper: current.paper(for: photo))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .frame(height: 72)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
            }
        } footer: {
            if canEdit {
                Text("Upload any photo, or pick one from the album. Auto uses an album photo, or an aerial view of where you went.")
            }
        }
    }

    private func choiceTile<Content: View>(selected: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Theme.ink : .clear, lineWidth: 2.5)
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Loads the picked photo and saves it as an uploaded cover. It only becomes the trip's
    /// cover on Save; if the sheet is cancelled the file is thrown away.
    private func upload(_ item: PhotosPickerItem) async {
        loadingCover = true
        defer {
            loadingCover = false
            pickedCover = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let file = CoverImages.save(image) else { return }
        uploads.append(file)
        uploadedFile = file
        coverImageFile = file
    }

    /// Deletes this sheet's uploads that didn't end up as the saved cover.
    private func discardUnusedUploads() {
        let kept = saved ? coverImageFile : nil
        for file in uploads where file != kept {
            CoverImages.delete(file)
        }
        uploads = []
    }

    // MARK: Details

    @ViewBuilder
    private var editableInfo: some View {
        Section("Name") {
            TextField("Trip name", text: $name)
        }
        Section("Dates") {
            DatePicker("Starts", selection: $start, displayedComponents: .date)
            DatePicker("Ends", selection: $end, in: start..., displayedComponents: .date)
        }
        Section {
            ForEach(places) { place in
                Label(place.name, systemImage: "mappin.and.ellipse")
            }
            .onDelete { places.remove(atOffsets: $0) }
            Button("Add a place", systemImage: "plus") { searching = true }
        } header: {
            Text("Where")
        } footer: {
            Text("Photos taken on these dates within 50 km of any place here are suggested for the album.")
        }
    }

    @ViewBuilder
    private var readOnlyInfo: some View {
        Section {
            HStack(spacing: 8) {
                stat("Duration", "\(current.dayCount()) \(current.dayCount() == 1 ? "day" : "days")")
                stat("Photos", "\(current.photos.count)")
                stat("People", "\(current.members.count)")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
        Section("Where") {
            ForEach(current.places) { place in
                Label(place.name, systemImage: "mappin.and.ellipse")
            }
        }
    }

    /// A small labelled number, like the stat cards on a travel itinerary.
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .opacity(0.5)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Members

    private var membersSection: some View {
        Section {
            ForEach(current.members) { member in
                HStack(spacing: 12) {
                    Avatar(member: member, size: 34)
                    Text(member.id == store.me?.id ? "\(member.name) (you)" : member.name)
                    Spacer()
                    if current.isOwner(member.id) {
                        Text("Owner")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.card, in: Capsule())
                    } else if isOwner {
                        Menu {
                            Button("Make owner", systemImage: "crown") {
                                store.makeOwner(member.id, of: trip.id)
                            }
                            Button("Remove from trip", systemImage: "person.badge.minus", role: .destructive) {
                                removing = member
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 32, height: 32)
                                .background(Theme.card, in: Circle())
                        }
                        .accessibilityLabel("Manage \(member.firstName)")
                    }
                }
            }
        } header: {
            Text("Members")
        } footer: {
            if isOwner {
                Text("You own this trip. To leave it, make someone else the owner first.")
            } else if let owner = current.ownerMemberID.flatMap(current.member) {
                Text("Only \(owner.firstName), who owns this trip, can change its details or members.")
            }
        }
    }

    // MARK: Leave or delete

    private var exitSection: some View {
        Section {
            Button {
                if isOwner { confirmingDelete = true } else { confirmingLeave = true }
            } label: {
                Text(isOwner ? "Delete trip for everyone" : "Leave trip")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.tomato)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(PressScale())
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private func save() {
        saved = true
        store.updateTrip(
            trip.id,
            name: trimmedName,
            startDate: start,
            endDate: end,
            places: places,
            coverPhotoID: coverImageFile == nil ? coverPhotoID : nil,
            coverImageFile: coverImageFile
        )
        dismiss()
    }

    private func exit(_ exit: Exit) {
        dismiss()
        onExit(exit)
    }
}
