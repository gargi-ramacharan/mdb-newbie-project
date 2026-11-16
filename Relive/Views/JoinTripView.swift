import SwiftUI

struct JoinTripView: View {
    var onJoined: (Trip) -> Void
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var notFound = false
    @State private var joining = false
    @State private var problem: String?

    init(code: String, onJoined: @escaping (Trip) -> Void) {
        _code = State(initialValue: code)
        self.onJoined = onJoined
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $code)
                        .font(Theme.display(32))
                        .tracking(2)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: code) {
                            notFound = false
                            problem = nil
                        }
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(.red)
                    } else if notFound {
                        Text(store.hasBackend
                            ? "No trip found for that code. Check it with whoever invited you."
                            : "No trip found for that code. This build isn't connected to a server, so only the sample code KYOTO7 can be joined.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Enter the code from a friend's invite.")
                    }
                }
            }
            .navigationTitle("Join a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if joining {
                        ProgressView()
                    } else {
                        Button("Join") { join() }
                            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func join() {
        guard !joining else { return }
        joining = true
        Task {
            defer { joining = false }
            do {
                switch try await store.join(code: code) {
                case .joined(let trip), .alreadyMember(let trip):
                    dismiss()
                    onJoined(trip)
                case .notFound:
                    notFound = true
                }
            } catch {
                problem = error is URLError
                    ? "Couldn't reach the server. Check your connection and try again."
                    : error.localizedDescription
            }
        }
    }
}
