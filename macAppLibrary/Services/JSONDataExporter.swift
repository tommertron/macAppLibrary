import Foundation

actor JSONDataExporter {
    static let shared = JSONDataExporter()

    static let enabledKey = "jsonExportEnabled"
    static let customPathKey = "jsonExportCustomPath"
    static let schemaVersion = 1

    private var pendingTask: Task<Void, Never>?
    private let debounceNanos: UInt64 = 1_000_000_000

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("macAppLibrary/export")
    }

    static var resolvedDirectory: URL {
        if let custom = UserDefaults.standard.string(forKey: customPathKey), !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return defaultDirectory
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Schedule a debounced export. Multiple rapid calls coalesce to a single write.
    func scheduleExport(snapshot: ExportSnapshot) {
        pendingTask?.cancel()
        pendingTask = Task { [debounceNanos] in
            try? await Task.sleep(nanoseconds: debounceNanos)
            if Task.isCancelled { return }
            await self.writeNow(snapshot: snapshot)
        }
    }

    /// Immediate write (used for first-write on enable, or "Export Now" button).
    func writeNow(snapshot: ExportSnapshot) {
        let dir = Self.resolvedDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            NSLog("[JSONDataExporter] Failed to create export dir: \(error)")
            return
        }

        let target = dir.appendingPathComponent("apps.json")
        let tmp = dir.appendingPathComponent("apps.json.tmp")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: target)
            }
        } catch {
            NSLog("[JSONDataExporter] Write failed: \(error)")
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}

struct ExportSnapshot: Encodable {
    let schemaVersion: Int
    let generatedAt: Date
    let appCount: Int
    let apps: [ExportedApp]

    init(apps: [AppEntry]) {
        self.schemaVersion = JSONDataExporter.schemaVersion
        self.generatedAt = Date()
        self.appCount = apps.count
        self.apps = apps
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(ExportedApp.init)
    }
}

struct ExportedApp: Encodable {
    let bundleID: String
    let name: String
    let path: String
    let version: String?
    let developer: String?
    let effectiveDeveloper: String?
    let effectiveDescription: String?
    let effectiveCategories: [String]
    let effectiveWebsiteURL: String?
    let systemCategory: String?
    let sizeBytes: Int64?
    let lastLaunched: Date?
    let lastModified: Date?
    let dateAdded: Date?
    let isFavorite: Bool
    let userDescription: String?
    let userDeveloper: String?
    let userCategories: [String]
    let userNotes: String?
    let userWebsiteURL: String?
    let communityDescription: String?
    let communityDeveloper: String?
    let communityCategories: [String]
    let communityURL: String?

    init(_ app: AppEntry) {
        self.bundleID = app.bundleID
        self.name = app.name
        self.path = app.bundlePath
        self.version = app.version
        self.developer = app.developer
        self.effectiveDeveloper = app.effectiveDeveloper
        self.effectiveDescription = app.effectiveDescription
        self.effectiveCategories = app.effectiveCategories
        self.effectiveWebsiteURL = app.effectiveWebsiteURL
        self.systemCategory = app.systemCategory
        self.sizeBytes = app.sizeBytes
        self.lastLaunched = app.lastLaunched
        self.lastModified = app.lastModified
        self.dateAdded = app.dateAdded
        self.isFavorite = app.isFavorite
        self.userDescription = app.userDescription
        self.userDeveloper = app.userDeveloper
        self.userCategories = app.userCategories
        self.userNotes = app.userNotes
        self.userWebsiteURL = app.userWebsiteURL
        self.communityDescription = app.communityDescription
        self.communityDeveloper = app.communityDeveloper
        self.communityCategories = app.communityCategories
        self.communityURL = app.communityURL
    }
}
