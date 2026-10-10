import Foundation

/// Photos, receipts, plan pictures and covers live in one private folder; the database keeps paths relative
/// to it ("photos/receipts/….jpg"), so they stay valid when the app is reinstalled or restored.
public struct FileStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// The app's own folder: Application Support/files.
    public static func appDefault() -> FileStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileStore(root: base.appendingPathComponent("files", isDirectory: true))
    }

    public func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }

    public func exists(_ relative: String?) -> Bool {
        guard let relative, !relative.isEmpty else { return false }
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url(relative).path, isDirectory: &dir) && !dir.boolValue
    }

    /// Writes [data] as a new file in [folder] ("covers", "photos/receipts", …) and returns its relative path.
    @discardableResult
    public func write(_ data: Data, folder: String, ext: String = "jpg") throws -> String {
        let dir = root.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let relative = "\(folder)/\(UUID().uuidString).\(ext)"
        try data.write(to: url(relative), options: .atomic)
        return relative
    }

    public func delete(_ relative: String?) {
        guard let relative, !relative.isEmpty, !relative.contains("..") else { return }
        try? FileManager.default.removeItem(at: url(relative))
    }

    public func delete(_ paths: [String]) { paths.forEach { delete($0) } }
}
