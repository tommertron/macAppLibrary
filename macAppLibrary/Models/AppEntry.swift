import Foundation

struct AppEntry: Identifiable, Hashable, Sendable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var bundlePath: String
    var version: String?
    var developer: String?

    // System metadata (loaded async after initial scan)
    var sizeBytes: Int64?
    var lastLaunched: Date?
    var lastModified: Date?
    var dateAdded: Date?
    var systemCategory: String?

    // Community data
    var communityDescription: String?
    var communityCategories: [String] = []
    var communityDeveloper: String?
    var communityURL: String?

    // User overrides
    var userDescription: String?
    var userDeveloper: String?
    var userCategories: [String] = []
    var userNotes: String?
    var userWebsiteURL: String?
    var isFavorite: Bool = false

    var effectiveDescription: String? { userDescription ?? communityDescription }
    var effectiveDeveloper: String? { userDeveloper ?? communityDeveloper ?? developer }
    var effectiveWebsiteURL: String? { userWebsiteURL ?? communityURL }

    var effectiveCategories: [String] {
        if !userCategories.isEmpty { return userCategories }
        if !communityCategories.isEmpty { return communityCategories }
        if let cat = systemCategory { return [cat] }
        return []
    }

    init(bundleID: String, name: String, bundlePath: String) {
        self.bundleID = bundleID
        self.name = name
        self.bundlePath = bundlePath
    }
}

struct UserAppData: Codable {
    var description: String?
    var developer: String?
    var categories: [String]?
    var notes: String?
    var websiteURL: String?
    var isFavorite: Bool = false

    init(description: String? = nil, developer: String? = nil, categories: [String]? = nil, notes: String? = nil, websiteURL: String? = nil, isFavorite: Bool = false) {
        self.description = description
        self.developer = developer
        self.categories = categories
        self.notes = notes
        self.websiteURL = websiteURL
        self.isFavorite = isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        developer = try container.decodeIfPresent(String.self, forKey: .developer)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        websiteURL = try container.decodeIfPresent(String.self, forKey: .websiteURL)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false

        // Migration: support old single "category" key
        if let cats = try container.decodeIfPresent([String].self, forKey: .categories) {
            categories = cats
        } else if let cat = try container.decodeIfPresent(String.self, forKey: .category) {
            categories = [cat]
        } else {
            categories = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case description, developer, categories, category, notes, websiteURL, isFavorite
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(developer, forKey: .developer)
        try container.encodeIfPresent(categories, forKey: .categories)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(websiteURL, forKey: .websiteURL)
        try container.encode(isFavorite, forKey: .isFavorite)
    }
}
