import SwiftUI

struct OnboardingView: View {
    @Environment(TripStore.self) private var store
    @State private var name = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Wordmark(size: 88, color: Theme.thermal)
                Text("Everyone's trip photos in one album, on one map, on one receipt.")
                    .font(.title3)
                    .foregroundStyle(Theme.thermal.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 72)

            Spacer(minLength: 24)

            // The form sits on a white card rising from the bottom edge.
            VStack(alignment: .leading, spacing: 10) {
                Text("Your name")
                    .font(.subheadline.weight(.semibold))
                TextField("", text: $name, prompt: Text("First and last").foregroundStyle(Theme.ink.opacity(0.35)))
                    .font(Theme.title(30))
                    .tracking(-0.6)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.go)
                    .onSubmit { start() }
                Rectangle()
                    .frame(height: 1.5)
                Text("It's printed on every trip receipt you share.")
                    .font(.footnote)
                    .opacity(0.7)
                Button {
                    start()
                } label: {
                    Text("Start")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.ink, in: Capsule())
                }
                .opacity(trimmedName.isEmpty ? 0.35 : 1)
                .disabled(trimmedName.isEmpty)
                .padding(.top, 10)
            }
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 20)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                    .fill(Theme.thermal)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(Theme.ink.ignoresSafeArea())
    }

    private func start() {
        guard !trimmedName.isEmpty else { return }
        store.signIn(name: trimmedName)
    }
}
