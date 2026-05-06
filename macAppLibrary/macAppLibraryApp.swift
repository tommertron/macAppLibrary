import SwiftUI

@main
struct macAppLibraryApp: App {
    @State private var store = AppLibraryStore()
    @State private var updateService = UpdateService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(updateService)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    await updateService.checkAndPromptIfDue()
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Refresh Library") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Import All Community Data…") {
                    let alert = NSAlert()
                    alert.messageText = "Import Community Data for All Apps"
                    alert.informativeText = "This will overwrite any custom information you've entered with data from the community database."
                    alert.addButton(withTitle: "Import")
                    alert.addButton(withTitle: "Cancel")
                    alert.alertStyle = .warning
                    if alert.runModal() == .alertFirstButtonReturn {
                        Task { await store.refreshAllCommunityData() }
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.isRefreshingAllCommunity)

                Button("Submit All Changes to Community…") {
                    let count = store.appsWithUserChanges.count
                    let alert = NSAlert()
                    if count == 0 {
                        alert.messageText = "Nothing to Submit"
                        alert.informativeText = "No apps found with local changes that differ from the community."
                        alert.runModal()
                        return
                    }
                    alert.messageText = "Submit \(count) App\(count == 1 ? "" : "s") to Community?"
                    alert.informativeText = "A GitHub PR will be created for each app where your information differs from the community. Blank fields are skipped. All submissions are reviewed before being accepted."
                    alert.addButton(withTitle: "Submit")
                    alert.addButton(withTitle: "Cancel")
                    alert.alertStyle = .informational
                    guard alert.runModal() == .alertFirstButtonReturn else { return }
                    Task {
                        let result = await store.submitAllChangedToCommunity()
                        let doneAlert = NSAlert()
                        doneAlert.messageText = "Submission Complete"
                        doneAlert.informativeText = "\(result.submitted) PR\(result.submitted == 1 ? "" : "s") created\(result.failed > 0 ? ", \(result.failed) failed" : "")."
                        doneAlert.runModal()
                    }
                }
                .disabled(store.isSubmittingAllToCommunity)
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(updateService)
        }
    }
}
