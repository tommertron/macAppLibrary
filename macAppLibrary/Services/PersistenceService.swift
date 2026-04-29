import Foundation

actor PersistenceService {
    private var cache: [String: UserAppData] = [:]
    private var loaded = false

    private static var storeURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("macAppLibrary")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("userData.json")
    }

    func loadUserData() -> [String: UserAppData] {
        guard !loaded else { return cache }
        loaded = true
        guard
            let data = try? Data(contentsOf: Self.storeURL),
            let decoded = try? JSONDecoder().decode([String: UserAppData].self, from: data)
        else { return [:] }
        cache = decoded
        return cache
    }

    func save(_ userData: UserAppData, for bundleID: String) {
        cache[bundleID] = userData
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: Self.storeURL, options: .atomic)
    }
}
