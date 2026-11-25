# Re:live

Everyone's trip photos in one album, on one map. SwiftUI, iOS 17+.

## Run it

Open `Relive.xcodeproj` in Xcode, pick an iPhone simulator (or your phone) and press Run.
To run on a real phone, set your team under the Relive target's Signing & Capabilities and
change the bundle identifier from `com.relive.app` to one of your own.

The app uses **Sign in with Apple** and **Associated Domains** (`Relive.entitlements`). Both need a
paid Apple Developer Program team to run on a phone; a free personal team can't sign them. The
simulator doesn't need either.

## What's in the prototype

- **Trips and invites.** Create a trip with dates and one or more places. Each trip gets an
  invite code and a link: `https://<your domain>/join/CODE` once invite links are set up (below),
  otherwise `relive://join/CODE`.
- **Owners and members.** Whoever creates a trip owns it. The owner edits its cover (upload a
  photo or pick one from the album), name, dates and places, removes members, hands the trip to
  someone else, or deletes it for everyone. Everyone else sees the trip's info read-only and can
  leave; leaving or being removed takes that person's photos out of the album.
- **Photos.** Open any photo to see it whole, swipe through the album, save it to your library
  (once: already-saved photos say so), or take out one of your own.
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

## Backend (Supabase)

The app talks to Supabase over plain HTTPS (`Relive/Backend`, no packages to install). Until you
point it at a project it runs exactly as the original prototype: everything stays on the phone.

One person sets up the project, everyone else just pulls the repo:

1. Create a project at supabase.com. In **Authentication > Providers**, turn on **Anonymous sign-ins**
   (for "Continue without an account") and **Apple** (below). In **Authentication > Settings**, turn on
   **Allow manual linking**, so an account that started anonymous keeps its trips when it signs in with Apple.
2. In the **SQL Editor**, run `supabase/migrations/0001_init.sql`, then `0002_owners_covers_members.sql`
   (and `0003_storage_cleanup.sql` once step 4's secret is saved).
   They create the tables, the `create_trip` / `join_trip` functions, the owner and member functions
   (`update_trip`, `remove_member`, `transfer_trip`, `leave_trip`, `delete_trip`), the private
   `trip-photos` bucket, and the row-level security that limits every trip's photos to its members.
3. Copy **Project URL** and the **anon public key** (Settings > API) into `SupabaseURL` and
   `SupabaseAnonKey` in `Info.plist`. The anon key is meant to ship inside the app; the policies
   in step 2 are what protect the data.
4. Set up photo cleanup (below), so photo files are deleted when someone leaves a trip.

### Photo cleanup

Leaving a trip, removing someone or deleting a trip takes the photos out of the album straight
away, but the files themselves can only be deleted through the Storage API with the service key.
`0003_storage_cleanup.sql` makes each of those actions queue the folder to clean, and the
`storage-cleanup` Edge Function deletes the files. The app calls it right after each action, and
pg_cron calls it every 10 minutes in case that call never arrives. It only deletes files that no
photo or cover uses any more, so someone who rejoins keeps their new photos.

1. In the **SQL Editor**, save the project URL for the schedule (once):
   `select vault.create_secret('https://<project ref>.supabase.co', 'project_url');`
2. Run `supabase/migrations/0003_storage_cleanup.sql`. It also queues any files already left
   behind, so the first run clears them.
3. Deploy the function (it needs no caller identity, since it can only delete files that are
   already garbage):
   `npx supabase functions deploy storage-cleanup --no-verify-jwt --project-ref <project ref>`

To check it: **Integrations > Cron** shows each run, and `select * from public.storage_cleanup;`
lists folders still waiting.

With that on:

- **Trips and invites.** Creating a trip asks the server for its invite code. Joining with a code
  or a `relive://join/CODE` link adds you as a member and pulls the album.
- **Upload.** Reviewing photos queues them; each is re-encoded as a JPEG with a long edge of 1600 px
  (never the original) and uploaded. Uploads retry on the next launch, trip open or tap on Retry,
  and sending the same photo twice never duplicates it.
- **Shared album.** Opening a trip, or coming back to the app, fetches everyone's new photos.
  Friends' photos download on demand and are cached on the phone. There's no background
  fetch: it all happens when the app is open.
- A reinstall signs back into the same account (the Keychain survives), so the trips come back, and
  camera-roll photos that are already in the album aren't suggested again.

Trips made before a backend was configured exist only on that phone; they have no server copy and
their invite codes won't work for friends.

### Accounts: Sign in with Apple

With a backend, the first screen offers **Continue with Apple**. Apple gives the app a signed token
(checked by Supabase), a user id private to this app, and the person's name the first time only
(they can edit it before sharing). The app asks for the name only, never the email, and never sees
the Apple ID, password or phone number. **Continue without an account** makes an anonymous account
from a typed name, for testing; Profile > Sign in with Apple upgrades it later and keeps its trips.
If that Apple ID already has an account (from another phone), the phone switches to that account.

To turn it on:

1. In the Apple Developer portal, enable **Sign in with Apple** on the app's identifier (Xcode does
   this when you add the capability with a paid team).
2. In Supabase, **Authentication > Providers > Apple**: enable it and add the app's bundle id
   (`com.relive.app`, or yours) under **Client IDs**. A native-only app doesn't need the secret key.

### Invite links that work without the app

`web/` is a tiny static site: `/join/CODE` shows the code with **Get re:live** and **Open the trip**
buttons, and `/.well-known/apple-app-site-association` tells iOS to open `/join/*` links straight in
the app when it's installed. iOS doesn't carry a link through an App Store install, so a new person
installs, then taps the link again (or types the code).

1. Get a domain and deploy `web/` to it (for example on Vercel: import the repo with `web` as the
   root directory; `vercel.json` sets up `/join/:code` and the association file's content type).
2. In `web/.well-known/apple-app-site-association`, replace `TEAMID` with your Apple team id (and the
   bundle id if you changed it). In `web/join/index.html`, set `relive-app-link` to your TestFlight or
   App Store link.
3. In Xcode, set the Relive target's `INVITE_LINK_HOST` build setting to the domain (no `https://`).
   That fills both `InviteLinkHost` in Info.plist (so invites share `https://` links) and the
   `applinks:` entitlement. Left blank, invites use `relive://` links, as before.

## What's simulated

- The **Lisbon long weekend** demo trip is seeded on first launch. Its photos are drawn
  placeholders, and "your camera roll" for that trip is seeded too, so the review flow can be
  demoed without real photos. It is never uploaded. Profile menu > Reset sample trip puts it back.
- Without a backend, joining only works for the sample code `KYOTO7`, and trips are stored on
  this phone (`Application Support/relive.json`). `TripRepository` in `Relive/Services/TripStore.swift`
  is the local store; `TripBackend` in `Relive/Backend/TripBackend.swift` is the server seam.
- The globe's five other trips (below) are made up and are never saved or uploaded.

## Look

The visual system lives in `Theme` in `Relive/Views/Components.swift`: white screens, soft grey
cards, big tight system-font titles, and black pills for what's selected, with one flat colour per
person (mustard, orange, teal, sage, lilac). Trip screens open on the cover photo edge to edge. The
home screen's trips are tickets with a tear-off stub, and the receipt recap keeps its monospaced
print. The logo is "re:live" in Futura Bold with a tomato colon.

The home screen (`Relive/Views/HomeView.swift`) is a satellite globe: it opens on the whole
earth, turns to the trip in front, and turns from trip to trip as you swipe their cards. Its
day and night follow the real time of day. Tap a pin to bring its trip to the front, and tap
the front pin (or its card) to open it. Your own trips are canary pins. The other pins
are five made-up trips "shared" by other people (New York, Rio de Janeiro, Cape Town, Mumbai,
Sydney), each with a view-only album of placeholder photos; they come from
`SeedData.sharedTrips` and are never saved. The Apple Maps logo and Legal link on the globe
are Apple's required attribution and have to stay visible. Trip covers are aerial views from
Apple Maps until a trip has real photos or a chosen cover, so the globe and covers need a network
connection. Press and hold a card to delete a trip you own, or leave one you don't.

## Layout

- `Relive/Core` — models, stop clustering, recap stats, seed data. No UI imports.
- `Relive/Services` — local storage, camera-roll scanning, reverse geocoding, and `TripStore`, which ties them to the backend.
- `Relive/Backend` — the Supabase client, its wire format, and the photo cache. Foundation only.
- `Relive/Views` — the screens.
- `supabase/migrations` — the database schema and security policies.
- `web` — the invite-link site and the file that lets iOS open invite links in the app.
- `Scripts/LogicCheck` — checks for the Core and Backend logic (the Backend runs against a stubbed network) that run without Xcode:

      swiftc Relive/Core/*.swift Relive/Backend/*.swift Scripts/LogicCheck/main.swift -o /tmp/relive-check && /tmp/relive-check
