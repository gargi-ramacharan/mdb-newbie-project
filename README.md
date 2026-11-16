# Re:live

Everyone's trip photos in one album, on one map, on one receipt. SwiftUI, iOS 17+.

## Run it

Open `Relive.xcodeproj` in Xcode, pick an iPhone simulator (or your phone) and press Run.
To run on a real phone, set your team under the Relive target's Signing & Capabilities and
change the bundle identifier from `com.relive.app` to one of your own.

## What's in the prototype

- **Trips and invites.** Create a trip with dates and one or more places. Each trip gets an
  invite code and a `relive://join/CODE` link.
- **Photo pooling.** Opening a trip scans your camera roll for photos taken on the trip's
  dates within 50 km of any of its places. You review them (suggested ones start selected,
  photos with no location start unselected) and nothing joins the album until you confirm.
  Photos you leave out aren't suggested again; "Review my photos" in the toolbar brings them back.
  Trip days are counted in the time zone of the trip's first place, so a trip abroad still
  matches its first-day photos when you scan after flying home.
- **Map.** Photos within 300 m and 2 hours of each other become one stop. Stops are numbered
  in time order and joined by a path, for the whole trip or one day at a time. Tap a stop to
  see its photos and switch between the people who took them.
- **Receipt recap.** Days, cities, spots, photos per person, busiest day, furthest point (the
  spot furthest from the first stop) and spot-to-spot distance, on a receipt card you can share
  as an image.

## What's simulated

Everything is stored on this phone (`Application Support/relive.json`); nothing is uploaded.

- The **Lisbon long weekend** demo trip is seeded on first launch. Its photos are drawn
  placeholders, and "your camera roll" for that trip is seeded too, so the review flow can be
  demoed without real photos. Profile menu > Reset sample trip puts it back.
- Joining only works for the sample code `KYOTO7`, because trips aren't synced between phones.
  `TripRepository` in `Relive/Services/TripStore.swift` is the one place a real backend plugs in.
- Trips you create use your real camera roll, but only your own photos can be in them.

## Look

The visual system lives in `Theme` in `Relive/Views/Components.swift`. It borrows from receipt
books: carbon-copy violet ink on thermal-paper white, a copy-paper colour per person (canary,
pink, sky, mint, goldenrod), DIN Condensed for titles and numerals, and monospace only on the
receipt itself.

The home screen (`Relive/Views/HomeView.swift`) is a satellite globe: it opens on the whole
earth, turns to the trip in front, and turns from trip to trip as you swipe their cards. Its
day and night follow the real time of day. Tap a pin to bring its trip to the front, and tap
the front pin (or its card) to open it. Your own trips are canary pins. The other pins
are five made-up trips "shared" by other people (New York, Rio de Janeiro, Cape Town, Mumbai,
Sydney), each with a view-only album of placeholder photos; they come from
`SeedData.sharedTrips` and are never saved. The Apple Maps logo and Legal link on the globe
are Apple's required attribution and have to stay visible. It sets
its titles in Futura Condensed ExtraBold. Trip covers are aerial views from Apple Maps until a
trip has real photos, so the globe and covers need a network connection. Press and hold a
card to delete a trip.

## Layout

- `Relive/Core` — models, stop clustering, recap stats, seed data. No UI imports.
- `Relive/Services` — storage, camera-roll scanning, reverse geocoding.
- `Relive/Views` — the screens.
- `Scripts/LogicCheck` — checks for the Core logic that run without Xcode:

      swiftc Relive/Core/*.swift Scripts/LogicCheck/main.swift -o /tmp/relive-check && /tmp/relive-check
