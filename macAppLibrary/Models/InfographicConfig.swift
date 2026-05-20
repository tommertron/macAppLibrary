import Foundation
import AppKit
import Observation

/// User-editable settings for the "Share Your Apps" infographic.
///
/// Held as a single instance on `AppLibraryStore` so the configure sheet
/// (in the main window) and the preview window stay in sync without having
/// to thread state through SwiftUI scenes.
@Observable
final class InfographicConfig {
    var displayName: String
    var websiteURL: String
    var excludedBundleIDs: Set<String>

    private static let kName = "infographic.displayName"
    private static let kSite = "infographic.websiteURL"
    private static let kExcluded = "infographic.excludedBundleIDs"

    init() {
        let d = UserDefaults.standard
        self.displayName = d.string(forKey: Self.kName) ?? NSFullUserName()
        self.websiteURL = d.string(forKey: Self.kSite) ?? ""
        self.excludedBundleIDs = Set(d.stringArray(forKey: Self.kExcluded) ?? [])
    }

    func persist() {
        let d = UserDefaults.standard
        d.set(displayName, forKey: Self.kName)
        d.set(websiteURL, forKey: Self.kSite)
        d.set(Array(excludedBundleIDs), forKey: Self.kExcluded)
    }

    func isIncluded(_ bundleID: String) -> Bool {
        !excludedBundleIDs.contains(bundleID)
    }
}
