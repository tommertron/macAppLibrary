import Foundation
import AppKit

struct AppScanner {
    private static let searchPaths = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"),
    ]

    func scan() async -> [AppEntry] {
        await Task.detached(priority: .userInitiated) {
            var seen = Set<String>()
            var entries: [AppEntry] = []
            for path in Self.searchPaths {
                for entry in Self.scanDirectory(path) {
                    if seen.insert(entry.bundleID).inserted {
                        entries.append(entry)
                    }
                }
            }
            return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }.value
    }

    private static func scanDirectory(_ url: URL) -> [AppEntry] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return items.compactMap { itemURL in
            guard itemURL.pathExtension == "app" else { return nil }
            return makeEntry(from: itemURL)
        }
    }

    private static func makeEntry(from url: URL) -> AppEntry? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard
            let plist = NSDictionary(contentsOf: plistURL),
            let bundleID = plist["CFBundleIdentifier"] as? String,
            !bundleID.isEmpty
        else { return nil }

        let name = plist["CFBundleDisplayName"] as? String
            ?? plist["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent

        var entry = AppEntry(bundleID: bundleID, name: name, bundlePath: url.path)
        entry.version = plist["CFBundleShortVersionString"] as? String

        if let rawCat = plist["LSApplicationCategoryType"] as? String {
            entry.systemCategory = rawCat
                .replacingOccurrences(of: "public.app-category.", with: "")
                .split(separator: "-")
                .map { $0.capitalized }
                .joined(separator: " ")
        }

        if let copyright = plist["NSHumanReadableCopyright"] as? String {
            entry.developer = Self.extractDeveloper(from: copyright)
        }

        return entry
    }

    private static let companySuffixes = [
        ", Inc.", " Inc.", ", Inc", " Inc",
        ", LLC", " LLC", ", Ltd.", " Ltd.", ", Ltd", " Ltd",
        ", GmbH", " GmbH", ", S.A.", " S.A.", ", Corp.", " Corp.",
    ]

    /// Extract a developer/company name from a copyright string.
    /// e.g. "Copyright © 2014 William C. Gustafson. All rights reserved." → "William C. Gustafson"
    /// e.g. "©1992-2025 Bare Bones Software, Inc." → "Bare Bones Software"
    static func extractDeveloper(from copyright: String) -> String? {
        var s = copyright

        // Remove "All rights reserved." and similar trailing boilerplate
        if let range = s.range(of: "All rights reserved", options: .caseInsensitive) {
            s = String(s[s.startIndex..<range.lowerBound])
        }

        // Remove copyright symbols and the word "Copyright"
        s = s.replacingOccurrences(of: "©", with: "")
        s = s.replacingOccurrences(of: "Copyright", with: "", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "(c)", with: "", options: .caseInsensitive)

        // Remove year patterns like "2023", "2019-2025", "2019–2025"
        let yearPattern = #"\d{4}\s*[-–]\s*\d{4}|\d{4}"#
        if let regex = try? NSRegularExpression(pattern: yearPattern) {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }

        // Clean up trailing suffixes
        for suffix in companySuffixes {
            if s.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count))
            }
        }

        // Trim leftover punctuation, whitespace, periods, commas
        s = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:- ")))

        return s.isEmpty ? nil : s
    }
}
