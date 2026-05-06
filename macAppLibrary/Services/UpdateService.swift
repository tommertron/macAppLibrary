import Foundation
import AppKit

struct UpdateInfo: Equatable {
    let currentVersion: String
    let latestVersion: String
    let downloadURL: URL

    var isUpdateAvailable: Bool {
        currentVersion.compare(latestVersion, options: .numeric) == .orderedAscending
    }
}

@Observable
final class UpdateService {
    private static let manifestURL = URL(string: "https://coefficiencies.com/apps/macapplibrary/latest.json")!
    private static let landingURL = URL(string: "https://coefficiencies.com/apps/macapplibrary/")!
    private static let lastCheckedKey = "UpdateService.lastChecked"
    private static let checkInterval: TimeInterval = 60 * 60 * 24

    var lastChecked: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastCheckedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastCheckedKey) }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private struct Manifest: Decodable {
        let version: String
        let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case version
            case downloadURL = "download_url"
        }
    }

    func check() async throws -> UpdateInfo {
        let (data, _) = try await URLSession.shared.data(from: Self.manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        lastChecked = Date()
        return UpdateInfo(
            currentVersion: currentVersion,
            latestVersion: manifest.version,
            downloadURL: manifest.downloadURL
        )
    }

    func checkAndPromptIfDue() async {
        if let last = lastChecked, Date().timeIntervalSince(last) < Self.checkInterval {
            return
        }
        guard let info = try? await check(), info.isUpdateAvailable else { return }
        await MainActor.run { presentUpdateAlert(info: info) }
    }

    @MainActor
    private func presentUpdateAlert(info: UpdateInfo) {
        let alert = NSAlert()
        alert.messageText = "macAppLibrary \(info.latestVersion) is available"
        alert.informativeText = "You're running version \(info.currentVersion). Open the download page to grab the latest DMG."
        alert.addButton(withTitle: "Open Download Page")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Self.landingURL)
        }
    }

    @MainActor
    func openDownloadPage() {
        NSWorkspace.shared.open(Self.landingURL)
    }
}
