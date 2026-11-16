import SwiftUI

/// Review your suggested photos before any of them join the shared album.
struct ReviewPhotosView: View {
    let trip: Trip
    let scan: ScanResult
    /// Called with the photos to add and the ones left out.
    var onFinish: (_ added: [TripPhoto], _ skipped: [TripPhoto]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID>

    init(trip: Trip, scan: ScanResult, onFinish: @escaping ([TripPhoto], [TripPhoto]) -> Void) {
        self.trip = trip
        self.scan = scan
        self.onFinish = onFinish
        // Suggested photos start selected, unless you skipped them in an earlier review.
        // Photos with no location start unselected.
        let preselected = scan.suggested.filter { !trip.skipped.contains($0.ref) }
        _selected = State(initialValue: Set(preselected.map(\.id)))
    }

    private var all: [TripPhoto] { scan.all }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section(
                        "Suggested",
                        detail: "Taken during the trip near \(trip.placesText). Tap any you'd rather keep private.",
                        photos: scan.suggested
                    )
                    section(
                        "No location",
                        detail: "Taken during the trip, but the photo has no location. Tap to include.",
                        photos: scan.noLocation
                    )
                    if scan.elsewhereCount > 0 {
                        Text(scan.elsewhereCount == 1
                            ? "1 other photo from these dates was taken somewhere else and was left out."
                            : "\(scan.elsewhereCount) other photos from these dates were taken somewhere else and were left out.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Review your photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if selected.count == all.count {
                        Button("Deselect all") { selected = [] }
                    } else {
                        Button("Select all") { selected = Set(all.map(\.id)) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onFinish(
                        all.filter { selected.contains($0.id) },
                        all.filter { !selected.contains($0.id) }
                    )
                    dismiss()
                } label: {
                    Text(selected.count == 1 ? "Add 1 photo to the album" : "Add \(selected.count) photos to the album")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selected.isEmpty)
                .padding()
                .background(.bar)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, detail: String, photos: [TripPhoto]) -> some View {
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(title) (\(photos.count))")
                    .font(Theme.display(26, relativeTo: .title2))
                    .padding(.horizontal)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                PhotoGrid(photos: photos, trip: trip, onTap: { toggle($0) }) { photo in
                    let isSelected = selected.contains(photo.id)
                    ZStack(alignment: .topTrailing) {
                        Color.black.opacity(isSelected ? 0 : 0.45)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, isSelected ? Color.accentColor : .clear)
                            .padding(5)
                    }
                }
            }
        }
    }

    private func toggle(_ photo: TripPhoto) {
        if selected.contains(photo.id) {
            selected.remove(photo.id)
        } else {
            selected.insert(photo.id)
        }
    }
}
