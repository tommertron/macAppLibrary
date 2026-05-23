import Foundation
import UserNotifications
import AppKit

/// Posts a local notification when a backgrounded publish finishes, and opens
/// the published page when the user clicks it. Used when the publish progress
/// sheet is dismissed via "Continue in Background" — the polling keeps running
/// and this delivers the result.
final class PublishNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PublishNotifier()
    private override init() { super.init() }

    /// Ask once; safe to call repeatedly. macOS only prompts the first time.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyLive(url: URL, displayName: String, confirmed: Bool) {
        let content = UNMutableNotificationContent()
        content.title = confirmed ? "Your library is live" : "Your library is publishing"
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = name.isEmpty ? "Your" : "\(name)’s"
        content.body = confirmed
            ? "\(who) Mac App Library is online. Click to open it."
            : "\(who) Mac App Library was published and should be online shortly. Click to open it."
        content.sound = .default
        content.userInfo = ["url": url.absoluteString]
        post(content)
    }

    func notifyFailed(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Couldn’t publish your library"
        content.body = message
        content.sound = .default
        post(content)
    }

    private func post(_ content: UNNotificationContent) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // Show the banner even if the app happens to be frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Clicking the notification opens the published page.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let string = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
