import SwiftUI

struct JoinTripView: View {
    var onJoined: (Trip) -> Void
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var notFound = false

    init(code: String, onJoined: @escaping (Trip) -> Void) {
        _code = State(initialValue: code)
        self.onJoined = onJoined
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $code)
                        .font(Theme.title(32))
                        .tracking(1.5)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: code) { notFound = false }
                } footer: {
                    if notFound {
                        Text("No trip found for that code. Trips aren't synced between phones in this prototype yet, so only the sample code KYOTO7 can be joined.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Enter the code from a friend's invite.")
                    }
                }
            }
            .paperForm()
            .navigationTitle("Join a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") { join() }
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func join() {
        switch store.join(code: code) {
        case .joined(let trip), .alreadyMember(let trip):
            dismiss()
            onJoined(trip)
        case .notFound:
            notFound = true
        }
    }
}
