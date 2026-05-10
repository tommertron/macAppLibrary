import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(AppLibraryStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let favorites = store.apps.filter(\.isFavorite).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let running = store.apps.filter { store.runningBundleIDs.contains($0.bundleID) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let categories = store.categories

        if favorites.isEmpty {
            Text("No Favourites")
                .disabled(true)
        } else {
            ForEach(favorites) { app in
                Button(app.name) { launch(app) }
            }
        }

        Divider()

        Menu("Running") {
            if running.isEmpty {
                Text("No Tracked Apps Running").disabled(true)
            } else {
                ForEach(running) { app in
                    Button(app.name) { launch(app) }
                }
            }
        }

        Menu("Categories") {
            if categories.isEmpty {
                Text("No Categories").disabled(true)
            } else {
                ForEach(categories, id: \.self) { category in
                    Menu(category) {
                        let appsInCat = store.apps
                            .filter { $0.effectiveCategories.contains(category) }
                            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                        if appsInCat.isEmpty {
                            Text("Empty").disabled(true)
                        } else {
                            ForEach(appsInCat) { app in
                                Button(app.name) { launch(app) }
                            }
                        }
                    }
                }
            }
        }

        Divider()

        Button("Show macAppLibrary") {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit macAppLibrary") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func launch(_ app: AppEntry) {
        let url = URL(fileURLWithPath: app.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}
