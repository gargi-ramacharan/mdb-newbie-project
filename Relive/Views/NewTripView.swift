import SwiftUI
import MapKit

struct NewTripView: View {
    var onCreate: (Trip) -> Void
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(2 * 24 * 60 * 60)
    @State private var places: [Place] = []
    @State private var searching = false
    @State private var creating = false
    @State private var problem: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                    if let problem {
                        Text(problem).foregroundStyle(.red)
                    } else {
                        Text("Photos taken on these dates within 50 km of any place here are suggested for the album.")
                    }
                }
            }
            .disabled(creating)
            .navigationTitle("New trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if creating {
                        ProgressView()
                    } else {
                        Button("Create") { create() }
                            .disabled(trimmedName.isEmpty || places.isEmpty)
                    }
                }
            }
            .onChange(of: start) { _, newStart in
                if end < newStart { end = newStart }
            }
            .sheet(isPresented: $searching) {
                PlaceSearchView { places.append($0) }
            }
        }
    }

    private func create() {
        guard !creating else { return }
        creating = true
        problem = nil
        Task {
            defer { creating = false }
            do {
                guard let trip = try await store.createTrip(
                    name: trimmedName, startDate: start, endDate: end, places: places
                ) else { return }
                dismiss()
                onCreate(trip)
            } catch {
                problem = error is URLError
                    ? "Couldn't reach the server. Check your connection and try again."
                    : error.localizedDescription
            }
        }
    }
}

/// Searches Apple Maps for a city, region or landmark to use as a trip place.
struct PlaceSearchView: View {
    var onPick: (Place) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []

    var body: some View {
        NavigationStack {
            List(results, id: \.self) { item in
                Button {
                    let coordinate = item.placemark.coordinate
                    onPick(Place(
                        name: item.name ?? "Pinned place",
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude,
                        timeZoneID: item.timeZone?.identifier
                    ))
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "Unnamed place")
                            .foregroundStyle(Color.primary)
                        if let detail = item.placemark.title {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView(
                        "Find a place",
                        systemImage: "magnifyingglass",
                        description: Text("Search for a city, region or landmark.")
                    )
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Lisbon, Yosemite, Kyoto…")
            .navigationTitle("Add a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: query) {
                let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.count >= 2 else {
                    results = []
                    return
                }
                // Wait for a pause in typing before searching.
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = text
                request.resultTypes = [.address, .pointOfInterest]
                let found = (try? await MKLocalSearch(request: request).start())?.mapItems
                guard !Task.isCancelled else { return }
                results = found ?? []
            }
        }
    }
}
