import Foundation

/// Seeded content: a finished Lisbon trip with three friends' photos already pooled and a
/// stand-in "camera roll" of your own photos waiting for review, plus made-up trips that
/// other people have shared with you.
enum SeedData {
    static let demoInviteCode = "LISBOA"

    static let friends: [Member] = [
        Member(id: fixedID(901), name: "Maya Chen", copy: 1),
        Member(id: fixedID(902), name: "Jonah Park", copy: 2),
        Member(id: fixedID(903), name: "Priya Nair", copy: 3),
    ]

    private struct Shot {
        /// 0 = you, 1...3 = `friends`.
        var who: Int
        var minute: Int
        var symbol: String
        var located = true
    }

    private struct Spot {
        var name: String
        var city: String
        var lat: Double
        var lon: Double
        var day: Int
        var hour: Int
        var minute: Int
        var shots: [Shot]
    }

    private static let spots: [Spot] = [
        Spot(name: "Praça do Comércio", city: "Lisbon", lat: 38.7075, lon: -9.1364, day: 0, hour: 10, minute: 15, shots: [
            Shot(who: 1, minute: 0, symbol: "building.columns.fill"),
            Shot(who: 0, minute: 4, symbol: "figure.2"),
            Shot(who: 2, minute: 9, symbol: "tram.fill"),
            Shot(who: 0, minute: 12, symbol: "doc.text.fill"),
        ]),
        Spot(name: "Miradouro de Santa Luzia", city: "Lisbon", lat: 38.7116, lon: -9.1300, day: 0, hour: 11, minute: 30, shots: [
            Shot(who: 3, minute: 0, symbol: "binoculars.fill"),
            Shot(who: 1, minute: 6, symbol: "camera.fill"),
            Shot(who: 0, minute: 11, symbol: "sun.max.fill"),
            Shot(who: 3, minute: 20, symbol: "leaf.fill"),
        ]),
        Spot(name: "Time Out Market", city: "Lisbon", lat: 38.7069, lon: -9.1459, day: 0, hour: 13, minute: 20, shots: [
            Shot(who: 2, minute: 0, symbol: "fork.knife"),
            Shot(who: 1, minute: 8, symbol: "wineglass.fill"),
            Shot(who: 2, minute: 15, symbol: "takeoutbag.and.cup.and.straw.fill"),
        ]),
        Spot(name: "LX Factory", city: "Lisbon", lat: 38.7035, lon: -9.1789, day: 0, hour: 16, minute: 0, shots: [
            Shot(who: 0, minute: 0, symbol: "paintpalette.fill"),
            Shot(who: 3, minute: 10, symbol: "books.vertical.fill"),
            Shot(who: 0, minute: 25, symbol: "cup.and.saucer.fill", located: false),
        ]),
        Spot(name: "Bairro Alto", city: "Lisbon", lat: 38.7139, lon: -9.1447, day: 0, hour: 20, minute: 15, shots: [
            Shot(who: 1, minute: 0, symbol: "music.note"),
            Shot(who: 2, minute: 30, symbol: "wineglass.fill"),
            Shot(who: 0, minute: 55, symbol: "moon.stars.fill", located: false),
        ]),
        Spot(name: "Belém Tower", city: "Lisbon", lat: 38.6916, lon: -9.2160, day: 1, hour: 9, minute: 40, shots: [
            Shot(who: 3, minute: 0, symbol: "building.2.fill"),
            Shot(who: 1, minute: 7, symbol: "camera.fill"),
            Shot(who: 0, minute: 15, symbol: "water.waves"),
            Shot(who: 2, minute: 22, symbol: "figure.2"),
        ]),
        Spot(name: "Pastéis de Belém", city: "Lisbon", lat: 38.6975, lon: -9.2032, day: 1, hour: 10, minute: 50, shots: [
            Shot(who: 2, minute: 0, symbol: "birthday.cake.fill"),
            Shot(who: 0, minute: 6, symbol: "cup.and.saucer.fill"),
        ]),
        Spot(name: "Pena Palace", city: "Sintra", lat: 38.7876, lon: -9.3906, day: 1, hour: 13, minute: 30, shots: [
            Shot(who: 1, minute: 0, symbol: "crown.fill"),
            Shot(who: 3, minute: 12, symbol: "mountain.2.fill"),
            Shot(who: 1, minute: 30, symbol: "camera.fill"),
            Shot(who: 2, minute: 48, symbol: "figure.walk"),
            Shot(who: 0, minute: 60, symbol: "flag.fill"),
        ]),
        Spot(name: "Quinta da Regaleira", city: "Sintra", lat: 38.7963, lon: -9.3961, day: 1, hour: 15, minute: 45, shots: [
            Shot(who: 3, minute: 0, symbol: "tree.fill"),
            Shot(who: 2, minute: 20, symbol: "arrow.down.circle.fill"),
            Shot(who: 3, minute: 40, symbol: "leaf.fill"),
        ]),
        Spot(name: "Praia da Rainha", city: "Cascais", lat: 38.6970, lon: -9.4196, day: 2, hour: 11, minute: 0, shots: [
            Shot(who: 1, minute: 0, symbol: "beach.umbrella.fill"),
            Shot(who: 0, minute: 14, symbol: "sailboat.fill"),
            Shot(who: 2, minute: 33, symbol: "water.waves"),
            Shot(who: 1, minute: 50, symbol: "sun.max.fill"),
        ]),
        Spot(name: "Boca do Inferno", city: "Cascais", lat: 38.6913, lon: -9.4305, day: 2, hour: 12, minute: 50, shots: [
            Shot(who: 3, minute: 0, symbol: "wind"),
            Shot(who: 2, minute: 12, symbol: "camera.fill"),
        ]),
        Spot(name: "Miradouro da Senhora do Monte", city: "Lisbon", lat: 38.7190, lon: -9.1326, day: 2, hour: 18, minute: 40, shots: [
            Shot(who: 1, minute: 0, symbol: "sunset.fill"),
            Shot(who: 0, minute: 8, symbol: "sunset.fill"),
            Shot(who: 3, minute: 15, symbol: "figure.2"),
            Shot(who: 2, minute: 26, symbol: "moon.stars.fill"),
        ]),
    ]

    /// The finished Lisbon trip with only the friends' photos pooled.
    static func demoTrip(me: Member, now: Date = Date(), calendar: Calendar = .current) -> Trip {
        let start = calendar.date(byAdding: .day, value: -9, to: calendar.startOfDay(for: now))!
        let end = calendar.date(byAdding: .day, value: 2, to: start)!
        var trip = Trip(
            id: fixedID(1),
            name: "Lisbon long weekend",
            startDate: start,
            endDate: end,
            places: [
                Place(id: fixedID(11), name: "Lisbon", latitude: 38.7223, longitude: -9.1393),
                Place(id: fixedID(12), name: "Sintra", latitude: 38.8029, longitude: -9.3817),
            ],
            members: [me] + friends,
            inviteCode: demoInviteCode,
            isDemo: true
        )
        trip.photos = allShots(start: start, me: me, calendar: calendar).filter { $0.ownerID != me.id }
        return trip
    }

    /// Your stand-in camera roll for the demo trip: the photos not pooled yet.
    static func demoCameraRoll(trip: Trip, me: Member, calendar: Calendar = .current) -> [TripPhoto] {
        let pooled = Set(trip.photos.map(\.id))
        return allShots(start: calendar.startOfDay(for: trip.startDate), me: me, calendar: calendar)
            .filter { $0.ownerID == me.id && !pooled.contains($0.id) }
    }

    /// Names for the demo stops, so the demo map and receipt work offline.
    static var demoPlaceNames: [String: PlaceName] {
        var names: [String: PlaceName] = [:]
        for spot in spots {
            names[Geo.key(spot.lat, spot.lon)] = PlaceName(spot: spot.name, city: spot.city)
        }
        return names
    }

    /// Trips that exist "on the server" and can be joined with an invite code.
    static func joinableTrips(now: Date = Date(), calendar: Calendar = .current) -> [Trip] {
        let start = calendar.date(byAdding: .day, value: 20, to: calendar.startOfDay(for: now))!
        let end = calendar.date(byAdding: .day, value: 3, to: start)!
        return [
            Trip(
                id: fixedID(2),
                name: "Kyoto in the fall",
                startDate: start,
                endDate: end,
                places: [Place(id: fixedID(21), name: "Kyoto", latitude: 35.0116, longitude: 135.7681)],
                members: [friends[0], friends[1]],
                inviteCode: "KYOTO7"
            ),
        ]
    }

    // MARK: Trips other people shared

    /// A made-up trip someone else shared with you. Its first member is the person who shared it.
    private struct Sample {
        /// Stable number for the trip's ids.
        var n: Int
        var name: String
        var daysAgo: Int
        var place: Place
        var members: [Member]
        var spots: [Spot]
    }

    static let leo = Member(id: fixedID(904), name: "Leo Okafor", copy: 4)

    private static let samples: [Sample] = [
        Sample(
            n: 3, name: "New York weekend", daysAgo: 30,
            place: Place(id: fixedID(31), name: "New York", latitude: 40.7128, longitude: -74.0060, timeZoneID: "America/New_York"),
            members: [friends[0], friends[1]],
            spots: [
                Spot(name: "Brooklyn Bridge", city: "New York", lat: 40.7061, lon: -73.9969, day: 0, hour: 9, minute: 30, shots: [
                    Shot(who: 0, minute: 0, symbol: "figure.walk"),
                    Shot(who: 1, minute: 8, symbol: "camera.fill"),
                    Shot(who: 0, minute: 15, symbol: "building.2.fill"),
                    Shot(who: 0, minute: 24, symbol: "camera.fill"),
                    Shot(who: 1, minute: 32, symbol: "figure.2"),
                    Shot(who: 0, minute: 41, symbol: "sun.max.fill"),
                ]),
                Spot(name: "Chelsea Market", city: "New York", lat: 40.7424, lon: -74.0061, day: 0, hour: 13, minute: 0, shots: [
                    Shot(who: 1, minute: 0, symbol: "fork.knife"),
                    Shot(who: 0, minute: 12, symbol: "cup.and.saucer.fill"),
                    Shot(who: 1, minute: 21, symbol: "leaf.fill"),
                    Shot(who: 0, minute: 29, symbol: "sparkles"),
                    Shot(who: 1, minute: 38, symbol: "cup.and.saucer.fill"),
                ]),
                Spot(name: "Central Park", city: "New York", lat: 40.7812, lon: -73.9665, day: 1, hour: 10, minute: 15, shots: [
                    Shot(who: 0, minute: 0, symbol: "leaf.fill"),
                    Shot(who: 0, minute: 20, symbol: "bicycle"),
                    Shot(who: 1, minute: 35, symbol: "tree.fill"),
                    Shot(who: 0, minute: 44, symbol: "fork.knife"),
                    Shot(who: 1, minute: 52, symbol: "binoculars.fill"),
                    Shot(who: 0, minute: 61, symbol: "figure.walk"),
                ]),
                Spot(name: "Top of the Rock", city: "New York", lat: 40.7593, lon: -73.9794, day: 1, hour: 17, minute: 40, shots: [
                    Shot(who: 1, minute: 0, symbol: "sunset.fill"),
                    Shot(who: 0, minute: 10, symbol: "binoculars.fill"),
                    Shot(who: 1, minute: 25, symbol: "moon.stars.fill"),
                    Shot(who: 1, minute: 34, symbol: "music.note"),
                    Shot(who: 0, minute: 42, symbol: "star.fill"),
                    Shot(who: 1, minute: 51, symbol: "heart.fill"),
                ]),
            ]
        ),
        Sample(
            n: 4, name: "Rio with the cousins", daysAgo: 62,
            place: Place(id: fixedID(41), name: "Rio de Janeiro", latitude: -22.9068, longitude: -43.1729, timeZoneID: "America/Sao_Paulo"),
            members: [friends[1], friends[2]],
            spots: [
                Spot(name: "Sugarloaf Mountain", city: "Rio de Janeiro", lat: -22.9492, lon: -43.1545, day: 0, hour: 10, minute: 0, shots: [
                    Shot(who: 0, minute: 0, symbol: "mountain.2.fill"),
                    Shot(who: 1, minute: 14, symbol: "camera.fill"),
                    Shot(who: 0, minute: 30, symbol: "binoculars.fill"),
                    Shot(who: 0, minute: 39, symbol: "bag.fill"),
                    Shot(who: 1, minute: 47, symbol: "sunset.fill"),
                    Shot(who: 0, minute: 56, symbol: "mappin.and.ellipse"),
                ]),
                Spot(name: "Ipanema Beach", city: "Rio de Janeiro", lat: -22.9868, lon: -43.2050, day: 0, hour: 15, minute: 30, shots: [
                    Shot(who: 1, minute: 0, symbol: "beach.umbrella.fill"),
                    Shot(who: 0, minute: 22, symbol: "water.waves"),
                    Shot(who: 1, minute: 50, symbol: "sunset.fill"),
                    Shot(who: 1, minute: 59, symbol: "photo.fill"),
                    Shot(who: 0, minute: 67, symbol: "camera.fill"),
                    Shot(who: 1, minute: 76, symbol: "figure.2"),
                ]),
                Spot(name: "Christ the Redeemer", city: "Rio de Janeiro", lat: -22.9519, lon: -43.2105, day: 1, hour: 9, minute: 15, shots: [
                    Shot(who: 0, minute: 0, symbol: "figure.2"),
                    Shot(who: 1, minute: 9, symbol: "sun.max.fill"),
                    Shot(who: 0, minute: 18, symbol: "sun.max.fill"),
                    Shot(who: 1, minute: 26, symbol: "leaf.fill"),
                    Shot(who: 0, minute: 35, symbol: "sparkles"),
                ]),
                Spot(name: "Santa Teresa", city: "Rio de Janeiro", lat: -22.9210, lon: -43.1880, day: 2, hour: 12, minute: 45, shots: [
                    Shot(who: 0, minute: 0, symbol: "tram.fill"),
                    Shot(who: 1, minute: 18, symbol: "paintpalette.fill"),
                    Shot(who: 0, minute: 40, symbol: "music.note"),
                    Shot(who: 1, minute: 49, symbol: "cup.and.saucer.fill"),
                    Shot(who: 0, minute: 57, symbol: "fork.knife"),
                    Shot(who: 1, minute: 66, symbol: "binoculars.fill"),
                ]),
            ]
        ),
        Sample(
            n: 5, name: "Cape Town road trip", daysAgo: 104,
            place: Place(id: fixedID(51), name: "Cape Town", latitude: -33.9249, longitude: 18.4241, radiusKm: 80, timeZoneID: "Africa/Johannesburg"),
            members: [leo, friends[0]],
            spots: [
                Spot(name: "Table Mountain", city: "Cape Town", lat: -33.9628, lon: 18.4098, day: 0, hour: 8, minute: 45, shots: [
                    Shot(who: 0, minute: 0, symbol: "mountain.2.fill"),
                    Shot(who: 1, minute: 16, symbol: "camera.fill"),
                    Shot(who: 0, minute: 34, symbol: "wind"),
                    Shot(who: 0, minute: 43, symbol: "figure.walk"),
                    Shot(who: 1, minute: 51, symbol: "music.note"),
                    Shot(who: 0, minute: 60, symbol: "star.fill"),
                ]),
                Spot(name: "Bo-Kaap", city: "Cape Town", lat: -33.9200, lon: 18.4150, day: 0, hour: 14, minute: 10, shots: [
                    Shot(who: 1, minute: 0, symbol: "paintpalette.fill"),
                    Shot(who: 0, minute: 11, symbol: "fork.knife"),
                    Shot(who: 1, minute: 20, symbol: "heart.fill"),
                    Shot(who: 0, minute: 28, symbol: "bag.fill"),
                    Shot(who: 1, minute: 37, symbol: "sunset.fill"),
                ]),
                Spot(name: "Boulders Beach", city: "Simon's Town", lat: -34.1975, lon: 18.4510, day: 1, hour: 11, minute: 0, shots: [
                    Shot(who: 0, minute: 0, symbol: "bird.fill"),
                    Shot(who: 1, minute: 7, symbol: "bird.fill"),
                    Shot(who: 0, minute: 21, symbol: "water.waves"),
                    Shot(who: 0, minute: 30, symbol: "mappin.and.ellipse"),
                    Shot(who: 1, minute: 38, symbol: "photo.fill"),
                    Shot(who: 0, minute: 47, symbol: "camera.fill"),
                ]),
                Spot(name: "Cape Point", city: "Cape Peninsula", lat: -34.3568, lon: 18.4970, day: 1, hour: 15, minute: 30, shots: [
                    Shot(who: 1, minute: 0, symbol: "flag.fill"),
                    Shot(who: 0, minute: 13, symbol: "sunset.fill"),
                    Shot(who: 1, minute: 22, symbol: "figure.2"),
                    Shot(who: 0, minute: 30, symbol: "sun.max.fill"),
                    Shot(who: 1, minute: 39, symbol: "leaf.fill"),
                ]),
            ]
        ),
        Sample(
            n: 6, name: "Mumbai for the wedding", daysAgo: 45,
            place: Place(id: fixedID(61), name: "Mumbai", latitude: 19.0760, longitude: 72.8777, timeZoneID: "Asia/Kolkata"),
            members: [friends[2], leo, friends[1]],
            spots: [
                Spot(name: "Gateway of India", city: "Mumbai", lat: 18.9220, lon: 72.8347, day: 0, hour: 9, minute: 20, shots: [
                    Shot(who: 0, minute: 0, symbol: "building.columns.fill"),
                    Shot(who: 2, minute: 6, symbol: "ferry.fill"),
                    Shot(who: 1, minute: 15, symbol: "figure.2"),
                    Shot(who: 0, minute: 24, symbol: "sparkles"),
                    Shot(who: 1, minute: 32, symbol: "cup.and.saucer.fill"),
                    Shot(who: 0, minute: 41, symbol: "fork.knife"),
                ]),
                Spot(name: "Crawford Market", city: "Mumbai", lat: 18.9477, lon: 72.8347, day: 0, hour: 12, minute: 30, shots: [
                    Shot(who: 1, minute: 0, symbol: "cart.fill"),
                    Shot(who: 0, minute: 14, symbol: "takeoutbag.and.cup.and.straw.fill"),
                    Shot(who: 1, minute: 23, symbol: "binoculars.fill"),
                    Shot(who: 0, minute: 31, symbol: "figure.walk"),
                    Shot(who: 1, minute: 40, symbol: "music.note"),
                ]),
                Spot(name: "Bandra Fort", city: "Mumbai", lat: 19.0418, lon: 72.8186, day: 1, hour: 17, minute: 15, shots: [
                    Shot(who: 2, minute: 0, symbol: "sunset.fill"),
                    Shot(who: 0, minute: 9, symbol: "camera.fill"),
                    Shot(who: 0, minute: 18, symbol: "star.fill"),
                    Shot(who: 1, minute: 26, symbol: "heart.fill"),
                    Shot(who: 0, minute: 35, symbol: "bag.fill"),
                ]),
                Spot(name: "Marine Drive", city: "Mumbai", lat: 18.9440, lon: 72.8235, day: 2, hour: 20, minute: 0, shots: [
                    Shot(who: 0, minute: 0, symbol: "party.popper.fill"),
                    Shot(who: 1, minute: 20, symbol: "music.note"),
                    Shot(who: 2, minute: 45, symbol: "moon.stars.fill"),
                    Shot(who: 0, minute: 70, symbol: "sparkles"),
                    Shot(who: 1, minute: 79, symbol: "sunset.fill"),
                    Shot(who: 0, minute: 87, symbol: "mappin.and.ellipse"),
                    Shot(who: 1, minute: 96, symbol: "photo.fill"),
                ]),
            ]
        ),
        Sample(
            n: 7, name: "Sydney in spring", daysAgo: 20,
            place: Place(id: fixedID(71), name: "Sydney", latitude: -33.8688, longitude: 151.2093, timeZoneID: "Australia/Sydney"),
            members: [friends[0], friends[2]],
            spots: [
                Spot(name: "Sydney Opera House", city: "Sydney", lat: -33.8568, lon: 151.2153, day: 0, hour: 10, minute: 30, shots: [
                    Shot(who: 0, minute: 0, symbol: "building.2.fill"),
                    Shot(who: 1, minute: 9, symbol: "camera.fill"),
                    Shot(who: 0, minute: 18, symbol: "sailboat.fill"),
                    Shot(who: 0, minute: 27, symbol: "camera.fill"),
                    Shot(who: 1, minute: 35, symbol: "figure.2"),
                    Shot(who: 0, minute: 44, symbol: "sun.max.fill"),
                ]),
                Spot(name: "The Rocks", city: "Sydney", lat: -33.8599, lon: 151.2090, day: 0, hour: 13, minute: 15, shots: [
                    Shot(who: 1, minute: 0, symbol: "fork.knife"),
                    Shot(who: 0, minute: 16, symbol: "cup.and.saucer.fill"),
                    Shot(who: 1, minute: 25, symbol: "leaf.fill"),
                    Shot(who: 0, minute: 33, symbol: "sparkles"),
                    Shot(who: 1, minute: 42, symbol: "cup.and.saucer.fill"),
                ]),
                Spot(name: "Taronga Zoo", city: "Sydney", lat: -33.8430, lon: 151.2410, day: 1, hour: 11, minute: 0, shots: [
                    Shot(who: 0, minute: 0, symbol: "pawprint.fill"),
                    Shot(who: 1, minute: 12, symbol: "tortoise.fill"),
                    Shot(who: 0, minute: 30, symbol: "ferry.fill"),
                    Shot(who: 0, minute: 39, symbol: "fork.knife"),
                    Shot(who: 1, minute: 47, symbol: "binoculars.fill"),
                    Shot(who: 0, minute: 56, symbol: "figure.walk"),
                ]),
                Spot(name: "Bondi Beach", city: "Sydney", lat: -33.8908, lon: 151.2743, day: 2, hour: 14, minute: 20, shots: [
                    Shot(who: 1, minute: 0, symbol: "beach.umbrella.fill"),
                    Shot(who: 0, minute: 15, symbol: "water.waves"),
                    Shot(who: 1, minute: 40, symbol: "sun.max.fill"),
                    Shot(who: 1, minute: 49, symbol: "music.note"),
                    Shot(who: 0, minute: 57, symbol: "star.fill"),
                    Shot(who: 1, minute: 66, symbol: "heart.fill"),
                ]),
            ]
        ),
    ]

    /// Made-up trips other people shared with you, each with its own album. Newest first.
    static func sharedTrips(now: Date = Date()) -> [Trip] {
        samples.map { sample in
            var calendar = Calendar(identifier: .gregorian)
            if let id = sample.place.timeZoneID, let zone = TimeZone(identifier: id) {
                calendar.timeZone = zone
            }
            let start = calendar.date(byAdding: .day, value: -sample.daysAgo, to: calendar.startOfDay(for: now))!
            let lastDay = sample.spots.map(\.day).max() ?? 0
            var trip = Trip(
                id: fixedID(sample.n),
                name: sample.name,
                startDate: start,
                endDate: calendar.date(byAdding: .day, value: lastDay, to: start)!,
                places: [sample.place],
                members: sample.members,
                inviteCode: ""
            )
            trip.photos = shots(at: sample.spots, owners: sample.members, start: start, calendar: calendar, idBase: sample.n * 1000)
            return trip
        }
        .sorted { $0.startDate > $1.startDate }
    }

    /// Names for the shared trips' stops.
    static var sharedPlaceNames: [String: PlaceName] {
        var names: [String: PlaceName] = [:]
        for spot in samples.flatMap(\.spots) {
            names[Geo.key(spot.lat, spot.lon)] = PlaceName(spot: spot.name, city: spot.city)
        }
        return names
    }

    private static func allShots(start: Date, me: Member, calendar: Calendar) -> [TripPhoto] {
        shots(at: spots, owners: [me] + friends, start: start, calendar: calendar, idBase: 1000)
    }

    /// Stand-in photos for every shot at `spots`. `Shot.who` indexes into `owners`.
    private static func shots(
        at spots: [Spot],
        owners: [Member],
        start: Date,
        calendar: Calendar,
        idBase: Int
    ) -> [TripPhoto] {
        var photos: [TripPhoto] = []
        var n = 0
        for (spotIndex, spot) in spots.enumerated() {
            let day = calendar.date(byAdding: .day, value: spot.day, to: start)!
            let arrival = calendar.date(bySettingHour: spot.hour, minute: spot.minute, second: 0, of: day)!
            for shot in spot.shots {
                n += 1
                photos.append(TripPhoto(
                    id: fixedID(idBase + n),
                    ownerID: owners[shot.who].id,
                    takenAt: arrival.addingTimeInterval(TimeInterval(shot.minute * 60)),
                    latitude: shot.located ? spot.lat : nil,
                    longitude: shot.located ? spot.lon : nil,
                    ref: .placeholder(
                        symbol: shot.symbol,
                        hue: (Double(spotIndex) * 0.083 + Double(n) * 0.011).truncatingRemainder(dividingBy: 1)
                    )
                ))
            }
        }
        return photos
    }

    private static func fixedID(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!
    }
}
