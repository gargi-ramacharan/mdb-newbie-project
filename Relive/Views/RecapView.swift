import SwiftUI

/// The receipt recap, printing out of a slot onto an ink-violet counter, with a
/// button to share it as an image.
struct RecapView: View {
    let trip: Trip
    let stops: [Stop]
    @Environment(TripStore.self) private var store
    @State private var shareImage: UIImage?

    private let receiptWidth: CGFloat = 330

    var body: some View {
        let stats = TripStats.compute(trip: trip, stops: stops, names: store.placeNames)
        if trip.photos.isEmpty {
            ContentUnavailableView(
                "No receipt yet",
                systemImage: "scroll",
                description: Text("Add photos to the album and the trip's receipt prints here.")
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 24) {
                    ReceiptCard(trip: trip, stats: stats, tornTop: false)
                        .frame(width: receiptWidth)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)

                    if !trip.hasEnded() {
                        Text("The trip isn't over, so this is a running total.")
                            .font(.footnote)
                            .foregroundStyle(Theme.thermal.opacity(0.8))
                    }

                    if let shareImage {
                        ShareLink(
                            item: Image(uiImage: shareImage),
                            preview: SharePreview("\(trip.name) receipt", image: Image(uiImage: shareImage))
                        ) {
                            Label("Share receipt", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Theme.canary, in: Capsule())
                        }
                        .padding(.horizontal, 36)
                    }
                }
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            // The slot the paper feeds out of.
            .safeAreaInset(edge: .top, spacing: 0) {
                Rectangle()
                    .fill(Color(red: 0.07, green: 0.065, blue: 0.22))
                    .frame(height: 7)
            }
            .background(Theme.ink)
            .task(id: stats) {
                // Draw the card off screen at 3x, torn at both ends, for sharing.
                let renderer = ImageRenderer(
                    content: ReceiptCard(trip: trip, stats: stats, tornTop: true)
                        .frame(width: receiptWidth)
                        .padding(28)
                        .background(Theme.ink)
                )
                renderer.scale = 3
                shareImage = renderer.uiImage
            }
        }
    }
}

/// A tall receipt of the trip's numbers, printed in carbon-copy violet. Uses fixed
/// colours so it looks the same in light mode, dark mode and when drawn off screen.
struct ReceiptCard: View {
    let trip: Trip
    let stats: TripStats
    /// False while the paper is still attached to the printer slot.
    let tornTop: Bool

    var body: some View {
        VStack(spacing: 9) {
            Text(AppInfo.name)
                .font(Theme.display(54, relativeTo: .largeTitle))
                .padding(.bottom, -8)
            Text("TRIP RECEIPT")
                .font(Theme.mono(11))
                .tracking(4)

            rule

            Text(trip.name.uppercased())
                .font(Theme.mono(15, .bold))
                .multilineTextAlignment(.center)
            Text(trip.dateRangeText.uppercased())
            Text("PARTY OF \(trip.members.count)")

            rule

            line("DAYS", "\(stats.dayCount)")
            line("CITIES", "\(stats.cities.count)")
            if !stats.cities.isEmpty {
                note(stats.cities.joined(separator: ", "))
            }
            line("SPOTS", "\(stats.stopCount)")
            line("PHOTOS", "\(stats.photoCount)")

            rule

            Text("PHOTOS BY")
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(stats.perMember, id: \.member.id) { entry in
                line(entry.member.firstName, "\(entry.count)")
            }

            rule

            if let busiest = stats.busiestDay {
                line("BUSIEST DAY", "\(stats.busiestDayCount) PHOTOS")
                note("Day \(trip.dayNumber(for: busiest)), \(trip.text(busiest, .dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
            }
            if stats.stopCount > 1 {
                line("FURTHEST POINT", distance(stats.furthestKm))
                note("\(stats.furthestName ?? "A spot"), from the first stop")
                line("SPOT TO SPOT", distance(stats.pathKm))
            }

            rule

            HStack(alignment: .firstTextBaseline) {
                Text("TOTAL MEMORIES")
                    .font(Theme.mono(16, .heavy))
                Spacer()
                // DIN Condensed draws high in its line box; drop it onto the label's baseline.
                Text("\(stats.photoCount)")
                    .font(Theme.display(34, relativeTo: .title))
                    .offset(y: 5)
            }

            rule

            Text("THANK YOU FOR TRAVELING TOGETHER")
                .multilineTextAlignment(.center)
            BarcodeShape(seed: trip.inviteCode)
                .frame(height: 46)
                .padding(.horizontal, 18)
                .padding(.top, 4)
            Text("MADE WITH \(AppInfo.name.uppercased())")
                .font(Theme.mono(10))
                .tracking(3)
        }
        .font(Theme.mono(12))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 22)
        .padding(.top, tornTop ? 34 : 28)
        .padding(.bottom, 34)
        .background(Theme.thermal)
        .clipShape(TornEdge(top: tornTop))
    }

    private var rule: some View {
        HLine()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .frame(height: 1)
            .padding(.vertical, 3)
    }

    /// "LABEL ........ VALUE"
    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label.uppercased())
                .lineLimit(1)
                .fixedSize()
            HLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
                .frame(height: 1)
            Text(value)
        }
    }

    /// An indented detail under a line.
    private func note(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.mono(10))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
    }

    private func distance(_ km: Double) -> String {
        km < 10 ? String(format: "%.1f KM", km) : "\(Int(km.rounded())) KM"
    }
}

private struct HLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Decorative bars. The pattern is fixed per trip but does not encode anything scannable.
private struct BarcodeShape: Shape {
    let seed: String

    func path(in rect: CGRect) -> Path {
        var state = seed.unicodeScalars.reduce(UInt64(7)) { ($0 &* 31) &+ UInt64($1.value) }
        var path = Path()
        var x = rect.minX
        var isBar = true
        while x < rect.maxX {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let width = CGFloat(1 + (state >> 33) % 3) * 1.6
            if isBar {
                path.addRect(CGRect(x: x, y: rect.minY, width: min(width, rect.maxX - x), height: rect.height))
            }
            x += width
            isBar.toggle()
        }
        return path
    }
}
