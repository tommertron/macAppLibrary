import SwiftUI
import AppKit

enum TimeUnit: String, CaseIterable, Identifiable, Codable {
    case days = "days"
    case weeks = "weeks"
    case months = "months"
    case years = "years"

    var id: String { rawValue }

    var calendarComponent: Calendar.Component {
        switch self {
        case .days:   return .day
        case .weeks:  return .weekOfYear
        case .months: return .month
        case .years:  return .year
        }
    }
}

struct ThresholdDuration: Equatable {
    var value: Int
    var unit: TimeUnit

    func cutoffDate(from now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: unit.calendarComponent, value: -max(1, value), to: now)!
    }
}

enum SmartFilter: String, CaseIterable, Identifiable, Hashable {
    case running = "Running"
    case favorites = "Favorites"
    case unused = "Unused Apps"
    case newApps = "New Apps"
    case recentlyUpdated = "Recently Updated"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .running: return "circle.fill"
        case .favorites: return "star.fill"
        case .unused: return "clock.badge.xmark"
        case .newApps: return "sparkles"
        case .recentlyUpdated: return "arrow.clockwise.circle"
        }
    }
}

enum ViewMode: String, CaseIterable {
    case list
    case gallery
}

enum SidebarSelection: Hashable {
    case all
    case smartFilter(SmartFilter)
    case category(String)
    case developer(String)
}

/// Codable representation of a pinned sidebar item for persistence
struct SidebarPin: Codable, Hashable {
    enum Kind: String, Codable {
        case smartFilter, category, developer
    }
    var kind: Kind
    var value: String // SmartFilter rawValue, category name, or developer name

    var sidebarSelection: SidebarSelection {
        switch kind {
        case .smartFilter:
            return SmartFilter(rawValue: value).map { .smartFilter($0) } ?? .all
        case .category:
            return .category(value)
        case .developer:
            return .developer(value)
        }
    }

    static func from(_ selection: SidebarSelection) -> SidebarPin? {
        switch selection {
        case .all: return nil
        case .smartFilter(let f): return SidebarPin(kind: .smartFilter, value: f.rawValue)
        case .category(let c): return SidebarPin(kind: .category, value: c)
        case .developer(let d): return SidebarPin(kind: .developer, value: d)
        }
    }
}

@MainActor
@Observable
final class AppLibraryStore {
    var apps: [AppEntry] = []
    var isLoading = false
    var isLoadingMetadata = false
    var searchText = ""
    var sidebarSelection: SidebarSelection = .all
    var selectedAppID: String?
    var generatingDescriptionFor: String?
    var errorMessage: String?

    var viewMode: ViewMode = .list {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }
    }
    var expandedAppID: String?
    var runningBundleIDs: Set<String> = []
    var isRefreshingAllCommunity = false
    var isSubmittingAllToCommunity = false

    // Sidebar pinned items — persisted as JSON array of encoded SidebarPin values
    var pinnedItems: [SidebarPin] = [] {
        didSet { Self.savePinnedItems(pinnedItems) }
    }

    // Sidebar collapsed sections — persisted to UserDefaults
    var collapsedSections: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(collapsedSections), forKey: "collapsedSidebarSections")
        }
    }

    var unusedThreshold: ThresholdDuration {
        didSet { Self.saveThreshold(unusedThreshold, key: "unusedThreshold") }
    }
    var newAppsThreshold: ThresholdDuration {
        didSet { Self.saveThreshold(newAppsThreshold, key: "newAppsThreshold") }
    }
    var recentlyUpdatedThreshold: ThresholdDuration {
        didSet { Self.saveThreshold(recentlyUpdatedThreshold, key: "recentlyUpdatedThreshold") }
    }

    private let scanner = AppScanner()
    private let metadataService = MetadataService()
    private let persistence = PersistenceService()
    private let communityService = CommunityService()
    private let aiService = AIService()

    init() {
        unusedThreshold = Self.loadThreshold(key: "unusedThreshold", defaultValue: 2, defaultUnit: .months)
        newAppsThreshold = Self.loadThreshold(key: "newAppsThreshold", defaultValue: 2, defaultUnit: .months)
        recentlyUpdatedThreshold = Self.loadThreshold(key: "recentlyUpdatedThreshold", defaultValue: 1, defaultUnit: .weeks)
        pinnedItems = Self.loadPinnedItems()
        collapsedSections = Set(UserDefaults.standard.stringArray(forKey: "collapsedSidebarSections") ?? [])
        viewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: "viewMode") ?? "list") ?? .list
    }

    private static func saveThreshold(_ threshold: ThresholdDuration, key: String) {
        UserDefaults.standard.set(threshold.value, forKey: "\(key)Value")
        UserDefaults.standard.set(threshold.unit.rawValue, forKey: "\(key)Unit")
    }

    private static func loadThreshold(key: String, defaultValue: Int, defaultUnit: TimeUnit) -> ThresholdDuration {
        let ud = UserDefaults.standard
        let value = ud.object(forKey: "\(key)Value") as? Int ?? defaultValue
        let unitRaw = ud.string(forKey: "\(key)Unit") ?? defaultUnit.rawValue
        let unit = TimeUnit(rawValue: unitRaw) ?? defaultUnit
        return ThresholdDuration(value: max(1, value), unit: unit)
    }

    private static func savePinnedItems(_ items: [SidebarPin]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "pinnedSidebarItems")
        }
    }

    private static func loadPinnedItems() -> [SidebarPin] {
        guard let data = UserDefaults.standard.data(forKey: "pinnedSidebarItems"),
              let items = try? JSONDecoder().decode([SidebarPin].self, from: data)
        else { return [] }
        return items
    }

    func togglePin(for selection: SidebarSelection) {
        guard let pin = SidebarPin.from(selection) else { return }
        if pinnedItems.contains(pin) {
            pinnedItems.removeAll { $0 == pin }
        } else {
            pinnedItems.append(pin)
        }
    }

    func isPinned(_ selection: SidebarSelection) -> Bool {
        guard let pin = SidebarPin.from(selection) else { return false }
        return pinnedItems.contains(pin)
    }

    var selectedApp: AppEntry? {
        apps.first { $0.id == selectedAppID }
    }

    var categories: [String] {
        var seen = Set<String>()
        return apps.flatMap(\.effectiveCategories).filter { seen.insert($0).inserted }.sorted()
    }

    var developers: [String] {
        var seen = Set<String>()
        return apps.compactMap(\.effectiveDeveloper).filter { seen.insert($0).inserted }.sorted()
    }

    var filteredApps: [AppEntry] {
        let base: [AppEntry]
        switch sidebarSelection {
        case .all:
            base = apps
        case .smartFilter(let f):
            base = apps(for: f)
        case .category(let cat):
            base = apps.filter { $0.effectiveCategories.contains(cat) }
        case .developer(let dev):
            base = apps.filter { $0.effectiveDeveloper == dev }
        }
        guard !searchText.isEmpty else { return base }
        let q = searchText.lowercased()
        return base.filter { app in
            app.name.lowercased().contains(q)
                || (app.effectiveDescription?.lowercased().contains(q) ?? false)
                || app.effectiveCategories.contains { $0.lowercased().contains(q) }
                || (app.effectiveDeveloper?.lowercased().contains(q) ?? false)
                || (app.communityURL?.lowercased().contains(q) ?? false)
        }
    }

    func apps(for filter: SmartFilter) -> [AppEntry] {
        let now = Date()
        switch filter {
        case .running:
            return apps.filter { runningBundleIDs.contains($0.bundleID) }
        case .favorites:
            return apps.filter(\.isFavorite)
        case .unused:
            let cutoff = unusedThreshold.cutoffDate(from: now)
            return apps.filter { ($0.lastLaunched.map { $0 < cutoff }) ?? false }
        case .newApps:
            let cutoff = newAppsThreshold.cutoffDate(from: now)
            return apps.filter { ($0.dateAdded.map { $0 > cutoff }) ?? false }
        case .recentlyUpdated:
            let cutoff = recentlyUpdatedThreshold.cutoffDate(from: now)
            return apps.filter { ($0.lastModified.map { $0 > cutoff }) ?? false }
        }
    }

    func count(for filter: SmartFilter) -> Int {
        apps(for: filter).count
    }

    var navigationTitle: String {
        switch sidebarSelection {
        case .all: return "All Apps"
        case .smartFilter(let f): return f.rawValue
        case .category(let cat): return cat
        case .developer(let dev): return dev
        }
    }

    func refreshCommunityData(for bundleID: String) async {
        guard let communityData = try? await communityService.fetchCommunityData() else { return }
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        if let c = communityData[bundleID] {
            apps[idx].communityDescription = c.description
            apps[idx].communityCategories = c.categories
            apps[idx].communityDeveloper = c.developer
            apps[idx].communityURL = c.url
        } else {
            apps[idx].communityDescription = nil
            apps[idx].communityCategories = []
            apps[idx].communityDeveloper = nil
            apps[idx].communityURL = nil
        }
    }

    func refreshAllCommunityData() async {
        isRefreshingAllCommunity = true
        defer { isRefreshingAllCommunity = false }
        guard let communityData = try? await communityService.fetchCommunityData() else { return }
        for i in apps.indices {
            let bundleID = apps[i].bundleID
            if let c = communityData[bundleID] {
                apps[i].communityDescription = c.description
                apps[i].communityCategories = c.categories
                apps[i].communityDeveloper = c.developer
                apps[i].communityURL = c.url
            } else {
                apps[i].communityDescription = nil
                apps[i].communityCategories = []
                apps[i].communityDeveloper = nil
                apps[i].communityURL = nil
            }
        }
    }

    var appsWithUserChanges: [AppEntry] {
        apps.filter { app in
            guard app.effectiveDescription != nil else { return false }
            let changedDesc = app.userDescription.map { !$0.isEmpty && $0 != app.communityDescription } ?? false
            let changedDev = app.userDeveloper.map { !$0.isEmpty && $0 != app.communityDeveloper } ?? false
            let changedCats = !app.userCategories.isEmpty && app.userCategories != app.communityCategories
            let changedURL = app.userWebsiteURL.map { !$0.isEmpty && $0 != app.communityURL } ?? false
            return changedDesc || changedDev || changedCats || changedURL
        }
    }

    func submitAllChangedToCommunity() async -> (submitted: Int, failed: Int) {
        isSubmittingAllToCommunity = true
        defer { isSubmittingAllToCommunity = false }
        var submitted = 0
        var failed = 0
        for app in appsWithUserChanges {
            do {
                let submission = CommunitySubmission(
                    bundleID: app.bundleID,
                    name: app.name,
                    description: app.effectiveDescription ?? "",
                    categories: app.effectiveCategories,
                    developer: app.effectiveDeveloper,
                    url: app.effectiveWebsiteURL
                )
                _ = try await CommunityService().submitEntry(submission)
                submitted += 1
            } catch {
                failed += 1
            }
        }
        return (submitted, failed)
    }

    func pullCommunityFieldsToUser(for bundleID: String) {
        guard let idx = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        var app = apps[idx]
        if let desc = app.communityDescription { app.userDescription = desc }
        if let dev = app.communityDeveloper { app.userDeveloper = dev }
        if !app.communityCategories.isEmpty { app.userCategories = app.communityCategories }
        if let url = app.communityURL { app.userWebsiteURL = url }
        updateApp(app)
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let scanned = await scanner.scan()
        let userData = await persistence.loadUserData()
        let communityData = (try? await communityService.fetchCommunityData()) ?? [:]

        apps = scanned.map { entry in
            var merged = entry
            if let c = communityData[entry.bundleID] {
                merged.communityDescription = c.description
                merged.communityCategories = c.categories
                merged.communityDeveloper = c.developer
                merged.communityURL = c.url
            }
            if let u = userData[entry.bundleID] {
                merged.userDescription = u.description
                merged.userDeveloper = u.developer
                merged.userCategories = u.categories ?? []
                merged.userNotes = u.notes
                merged.userWebsiteURL = u.websiteURL
                merged.isFavorite = u.isFavorite
            }
            return merged
        }

        await loadMetadata()
        scheduleJSONExport()
    }

    func refreshRunningApps() {
        runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
    }

    func startRunningAppsTimer() {
        refreshRunningApps()
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRunningApps()
            }
        }
    }

    private func loadMetadata() async {
        isLoadingMetadata = true
        defer { isLoadingMetadata = false }
        for i in apps.indices {
            let path = apps[i].bundlePath
            let meta = await metadataService.load(bundlePath: path)
            apps[i].sizeBytes = meta.sizeBytes
            apps[i].lastLaunched = meta.lastLaunched
            apps[i].lastModified = meta.lastModified
            apps[i].dateAdded = meta.dateAdded
        }
    }

    func updateApp(_ app: AppEntry) {
        guard let idx = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[idx] = app
        let data = UserAppData(
            description: app.userDescription,
            developer: app.userDeveloper,
            categories: app.userCategories.isEmpty ? nil : app.userCategories,
            notes: app.userNotes,
            websiteURL: app.userWebsiteURL,
            isFavorite: app.isFavorite
        )
        Task { await persistence.save(data, for: app.bundleID) }
        scheduleJSONExport()
    }

    func scheduleJSONExport() {
        guard JSONDataExporter.isEnabled else { return }
        let snapshot = ExportSnapshot(apps: apps)
        Task { await JSONDataExporter.shared.scheduleExport(snapshot: snapshot) }
    }

    func exportJSONNow() async {
        let snapshot = ExportSnapshot(apps: apps)
        await JSONDataExporter.shared.writeNow(snapshot: snapshot)
    }

    var needsAIProviderPick: Bool = false

    func generateDescription(for appID: String) async {
        guard let idx = apps.firstIndex(where: { $0.id == appID }) else { return }
        guard AIProviderSettings.hasChosenProvider else {
            needsAIProviderPick = true
            return
        }
        generatingDescriptionFor = appID
        defer { generatingDescriptionFor = nil }
        do {
            let app = apps[idx]
            let desc = try await aiService.generateDescription(
                appName: app.name,
                bundleID: app.bundleID
            )
            apps[idx].userDescription = desc
            let data = UserAppData(
                description: desc,
                developer: apps[idx].userDeveloper,
                categories: apps[idx].userCategories.isEmpty ? nil : apps[idx].userCategories,
                notes: apps[idx].userNotes,
                websiteURL: apps[idx].userWebsiteURL,
                isFavorite: apps[idx].isFavorite
            )
            await persistence.save(data, for: appID)
        } catch {
            errorMessage = "AI error: \(error.localizedDescription)"
        }
    }
}
