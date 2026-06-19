import Foundation

actor PersistenceService {
    private var cache: [String: UserAppData] = [:]
    private var loaded = false

    /// UserDefaults key holding the folder the metadata file is synced to.
    /// Empty/unset = stored locally in Application Support (not synced).
    static let syncFolderKey = "metadataSyncFolder"
    /// Filename used inside a chosen sync folder (distinct, user-facing name).
    static let syncFileName = "macAppLibraryMetadata.json"

    /// Default local (un-synced) store, in Application Support.
    static var defaultStoreURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("macAppLibrary")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("userData.json")
    }

    /// The folder the user chose to sync metadata to (e.g. an iCloud Drive folder),
    /// or nil when storing locally.
    static var syncFolder: URL? {
        guard let path = UserDefaults.standard.string(forKey: syncFolderKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// The file metadata is actually read from / written to right now.
    static var resolvedStoreURL: URL {
        if let folder = syncFolder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder.appendingPathComponent(syncFileName)
        }
        return defaultStoreURL
    }

    /// Whether the metadata file currently lives in a synced folder.
    static var isSyncing: Bool { syncFolder != nil }

    func currentStoreURL() -> URL { Self.resolvedStoreURL }

    func loadUserData() -> [String: UserAppData] {
        guard !loaded else { return cache }
        loaded = true
        cache = Self.read(from: Self.resolvedStoreURL)
        return cache
    }

    func save(_ userData: UserAppData, for bundleID: String) {
        cache[bundleID] = userData
        persist()
    }

    /// Relocate the metadata store to `folderPath` (nil/empty = back to local).
    ///
    /// Only the user metadata moves — which apps are installed is rescanned on each
    /// machine and never synced. When adopting a sync folder that already contains a
    /// file (e.g. written by another Mac), the two sets are merged by bundleID with
    /// the synced file winning on conflicts, so no local-only metadata is lost.
    /// Returns the resulting metadata for the store to re-apply to the library.
    func setSyncFolder(_ folderPath: String?) -> [String: UserAppData] {
        _ = loadUserData()            // make sure the current data is in `cache`
        let local = cache

        let trimmed = folderPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = trimmed, !p.isEmpty {
            UserDefaults.standard.set(p, forKey: Self.syncFolderKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.syncFolderKey)
        }

        let dest = Self.resolvedStoreURL
        if let p = trimmed, !p.isEmpty, FileManager.default.fileExists(atPath: dest.path) {
            // Adopting an existing synced file: merge (synced file wins on conflict).
            var merged = local
            for (k, v) in Self.read(from: dest) { merged[k] = v }
            cache = merged
        } else {
            // New/empty destination, or reverting to local: carry current data over.
            cache = local
        }
        persist()                     // writes to the new resolved location
        return cache
    }

    private static func read(from url: URL) -> [String: UserAppData] {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: UserAppData].self, from: data)
        else { return [:] }
        return decoded
    }

    private func persist() {
        let encoder = JSONEncoder()
        // Pretty + stable key order: human-readable in iCloud and minimises spurious
        // sync conflicts from re-ordered keys.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cache) else { return }
        try? data.write(to: Self.resolvedStoreURL, options: .atomic)
    }
}
