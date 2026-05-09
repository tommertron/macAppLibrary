import Foundation

enum APIDTO {
    static let version = "1.0.0"
    static let apiVersion = "v1"
}

struct HealthResponse: Codable {
    let status: String
    let appVersion: String
    let apiVersion: String
}

struct VersionResponse: Codable {
    let appVersion: String
    let apiVersion: String
    let build: String?
}

struct ErrorResponse: Codable {
    let error: String
    let message: String
}

struct AppDTO: Codable {
    let bundleID: String
    let name: String
    let bundlePath: String
    let version: String?
    let developer: String?
    let description: String?
    let categories: [String]
    let websiteURL: String?
    let isFavorite: Bool
    let isRunning: Bool
    let sizeBytes: Int64?
    let lastLaunched: Date?
    let lastModified: Date?
    let dateAdded: Date?
    let systemCategory: String?
    let community: CommunityFields?
    let user: UserFields?

    struct CommunityFields: Codable {
        let description: String?
        let categories: [String]
        let developer: String?
        let websiteURL: String?
    }

    struct UserFields: Codable {
        let description: String?
        let developer: String?
        let categories: [String]
        let notes: String?
        let websiteURL: String?
    }

    init(_ entry: AppEntry, isRunning: Bool, includeOverrides: Bool) {
        bundleID = entry.bundleID
        name = entry.name
        bundlePath = entry.bundlePath
        version = entry.version
        developer = entry.effectiveDeveloper
        description = entry.effectiveDescription
        categories = entry.effectiveCategories
        websiteURL = entry.effectiveWebsiteURL
        isFavorite = entry.isFavorite
        self.isRunning = isRunning
        sizeBytes = entry.sizeBytes
        lastLaunched = entry.lastLaunched
        lastModified = entry.lastModified
        dateAdded = entry.dateAdded
        systemCategory = entry.systemCategory
        if includeOverrides {
            community = CommunityFields(
                description: entry.communityDescription,
                categories: entry.communityCategories,
                developer: entry.communityDeveloper,
                websiteURL: entry.communityURL
            )
            user = UserFields(
                description: entry.userDescription,
                developer: entry.userDeveloper,
                categories: entry.userCategories,
                notes: entry.userNotes,
                websiteURL: entry.userWebsiteURL
            )
        } else {
            community = nil
            user = nil
        }
    }
}
