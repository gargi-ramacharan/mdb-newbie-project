import SwiftUI
import Photos

/// Saves album photos and the receipt into your photo library. Asks for add-only access,
/// so it works even if you didn't let the app read your library.
enum PhotoSaver {
    enum SaveError: LocalizedError {
        case noAccess
        case noImage

        var errorDescription: String? {
            switch self {
            case .noAccess: "Allow Re:live to add photos in Settings > Privacy > Photos."
            case .noImage: "The photo couldn't be loaded."
            }
        }
    }

    /// Saves a pooled photo at full size. A friend's photo comes from the shared album via
    /// `download`; a seeded stand-in is drawn out as an image.
    @MainActor
    static func save(_ photo: TripPhoto, paper: Color, download: (String) async -> Data?) async throws {
        let image: UIImage?
        switch photo.ref {
        case .asset(let id):
            image = await PhotoScanner.image(for: id, side: 4096, contentMode: .aspectFit)
        case .remote(let path):
            image = await download(path).flatMap(UIImage.init(data:))
        case .placeholder(let symbol, _):
            let renderer = ImageRenderer(
                content: PlaceholderPhoto(symbol: symbol, paper: paper).frame(width: 400, height: 400)
            )
            renderer.scale = 3
            image = renderer.uiImage
        }
        guard let image else { throw SaveError.noImage }
        let identifier = try await save(image)
        if let identifier { record(identifier, for: "photo:\(photo.id)") }
    }

    /// True when this album photo was saved from the app and is still in your library.
    static func isSaved(_ photo: TripPhoto) -> Bool {
        isSaved(key: "photo:\(photo.id)")
    }

    /// True when the image saved under `key` is still in your library. If the app can't
    /// read the library to check, a recorded save counts.
    static func isSaved(key: String) -> Bool {
        guard let identifier = savedByKey[key] else { return false }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return true }
        return PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).count > 0
    }

    /// Saves an image and remembers it under `key`, so it isn't saved twice.
    static func save(_ image: UIImage, key: String) async throws {
        if let identifier = try await save(image) { record(identifier, for: key) }
    }

    @discardableResult
    static func save(_ image: UIImage) async throws -> String? {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.noAccess }
        var identifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            identifier = PHAssetChangeRequest.creationRequestForAsset(from: image)
                .placeholderForCreatedAsset?.localIdentifier
        }
        if let identifier { remember(identifier) }
        return identifier
    }

    private static let byKeyKey = "photosSavedByKey"

    /// What was saved: an album photo or receipt key, to its library identifier.
    private static var savedByKey: [String: String] {
        UserDefaults.standard.dictionary(forKey: byKeyKey) as? [String: String] ?? [:]
    }

    private static func record(_ identifier: String, for key: String) {
        var saved = savedByKey
        saved[key] = identifier
        UserDefaults.standard.set(saved, forKey: byKeyKey)
    }

    private static let savedKey = "photosSavedByApp"

    /// Library photos this app saved (receipts, friends' photos). They're dated the moment
    /// they were saved, so without this they'd be suggested for whatever trip is on now.
    static var savedIdentifiers: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: savedKey) ?? [])
    }

    private static func remember(_ identifier: String) {
        var saved = savedIdentifiers
        saved.insert(identifier)
        UserDefaults.standard.set(Array(saved), forKey: savedKey)
    }
}

/// Cover photos an owner uploaded, kept as JPEGs next to the app's data. With a backend
/// these would go to the photo bucket so every member sees the same cover.
enum CoverImages {
    private static let cache = NSCache<NSString, UIImage>()

    private static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Shrinks the image to at most 2000 px on its long edge, saves it, and returns its file name.
    static func save(_ image: UIImage) -> String? {
        let scale = min(1, 2000 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            return nil
        }
        cache.setObject(resized, forKey: name as NSString)
        return name
    }

    /// The saved JPEG's bytes, for uploading.
    static func data(_ name: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    static func load(_ name: String) -> UIImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        guard let image = UIImage(contentsOfFile: directory.appendingPathComponent(name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    static func delete(_ name: String) {
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}
