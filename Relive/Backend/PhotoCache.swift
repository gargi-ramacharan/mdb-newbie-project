import Foundation

/// Keeps album photos you've already downloaded in the Caches folder, so scrolling the album
/// doesn't fetch them again. The system may clear it when space is short; they just download again.
enum PhotoCache {
    private static var folder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("AlbumPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func file(for path: String) -> URL {
        // "<trip>/<owner>/<photo>.jpg" -> one flat file name.
        folder.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
    }

    static func read(_ path: String) -> Data? {
        try? Data(contentsOf: file(for: path))
    }

    static func write(_ data: Data, for path: String) {
        try? data.write(to: file(for: path), options: .atomic)
    }

    /// Clears every downloaded photo, on sign-out.
    static func deleteAll() {
        try? FileManager.default.removeItem(at: folder)
    }
}
