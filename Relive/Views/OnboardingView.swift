import SwiftUI

struct OnboardingView: View {
    @Environment(TripStore.self) private var store
    @State private var name = ""
    @State private var signingIn = false
    @State private var problem: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppInfo.name)
                    .font(Theme.display(104, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.thermal)
                Text("Everyone's trip photos in one album, on one map, on one receipt.")
                    .font(.title3)
                    .foregroundStyle(Theme.thermal.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 72)

            Spacer(minLength: 24)

            // The form sits on a slip of receipt paper feeding up from the bottom edge.
            VStack(alignment: .leading, spacing: 10) {
                Text("Your name")
                    .font(.subheadline.weight(.semibold))
                TextField("", text: $name, prompt: Text("First and last").foregroundStyle(Theme.ink.opacity(0.35)))
                    .font(Theme.display(34))
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.go)
                    .onSubmit { start() }
                Rectangle()
                    .frame(height: 1.5)
                if let problem {
                    Text(problem)
                        .font(.footnote.weight(.semibold))
                } else {
                    Text("It's printed on every trip receipt you share.")
                        .font(.footnote)
                        .opacity(0.7)
                }
                Button {
                    start()
                } label: {
                    Group {
                        if signingIn {
                            ProgressView().tint(Theme.thermal)
                        } else {
                            Text("Start")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(Theme.thermal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.ink, in: Capsule())
                }
                .opacity(trimmedName.isEmpty ? 0.35 : 1)
                .disabled(trimmedName.isEmpty || signingIn)
                .padding(.top, 10)
            }
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 20)
            .background {
                TornEdge(bottom: false)
                    .fill(Theme.thermal)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(Theme.ink.ignoresSafeArea())
    }

    private func start() {
        guard !trimmedName.isEmpty, !signingIn else { return }
        signingIn = true
        problem = nil
        Task {
            do {
                try await store.signIn(name: trimmedName)
            } catch {
                problem = error is URLError
                    ? "Couldn't reach the server. Check your connection and try again."
                    : error.localizedDescription
            }
            signingIn = false
        }
    }
}
