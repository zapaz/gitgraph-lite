import Foundation

/// Repositories opened before, most recent first, offered again by the Open repo button.
public final class RecentRepositories {
    public static let limit = 10
    private let defaults: UserDefaults
    private let key = "recentRepositories.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Stored paths, most recent first.
    public var paths: [String] { defaults.stringArray(forKey: key) ?? [] }

    /// Stored paths whose folder still exists.
    public var existing: [String] {
        paths.filter { var folder: ObjCBool = false; return FileManager.default.fileExists(atPath: $0, isDirectory: &folder) && folder.boolValue }
    }

    public func record(_ path: String) {
        let standard = URL(fileURLWithPath: path).standardizedFileURL.path
        let rest = paths.filter { URL(fileURLWithPath: $0).standardizedFileURL.path != standard }
        defaults.set(Array(([standard] + rest).prefix(Self.limit)), forKey: key)
    }

    public func remove(_ path: String) { defaults.set(paths.filter { $0 != path }, forKey: key) }
    public func clear() { defaults.removeObject(forKey: key) }
}
