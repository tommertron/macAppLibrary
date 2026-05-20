import SwiftUI

/// Configuration sheet for the "Share Your Apps" flow. Lets the user set
/// their display name and website, and pick which apps to include in the
/// generated infographic. Tapping **Preview** persists the config and opens
/// the infographic preview window.
struct ShareLibrarySheet: View {
    @Environment(AppLibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @Bindable var config: InfographicConfig
    @State private var search = ""

    private var sortedApps: [AppEntry] {
        store.apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var visibleApps: [AppEntry] {
        guard !search.isEmpty else { return sortedApps }
        return sortedApps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var includedCount: Int {
        store.apps.reduce(into: 0) { acc, app in
            if config.isIncluded(app.bundleID) { acc += 1 }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share Your Apps")
                .font(.title2).bold()
            Text("Create a shareable infographic of your library. You can edit your name and website, and exclude apps you'd rather not share.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                Section("Your Info") {
                    TextField("Display name", text: $config.displayName)
                    TextField("Website (optional)", text: $config.websiteURL,
                              prompt: Text("example.com"))
                }

                Section {
                    appsList
                } header: {
                    HStack {
                        Text("Apps to include")
                        Spacer()
                        Text("\(includedCount) of \(store.apps.count) selected")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .textCase(nil)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Preview →") {
                    config.persist()
                    dismiss()
                    openWindow(id: "infographic-preview")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 640, height: 640)
    }

    @ViewBuilder
    private var appsList: some View {
        HStack {
            TextField("Search apps", text: $search)
                .textFieldStyle(.roundedBorder)
            Button("Select All") {
                config.excludedBundleIDs.removeAll()
            }
            .disabled(config.excludedBundleIDs.isEmpty)
            Button("Deselect All") {
                config.excludedBundleIDs = Set(store.apps.map(\.bundleID))
            }
            .disabled(includedCount == 0)
        }

        List {
            ForEach(visibleApps) { app in
                Toggle(isOn: binding(for: app.bundleID)) {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(app.name)
                    }
                }
            }
        }
        .frame(minHeight: 240)
    }

    private func binding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { config.isIncluded(bundleID) },
            set: { included in
                if included { config.excludedBundleIDs.remove(bundleID) }
                else { config.excludedBundleIDs.insert(bundleID) }
            }
        )
    }
}
