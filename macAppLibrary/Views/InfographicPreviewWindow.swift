import SwiftUI
import UniformTypeIdentifiers

/// Standalone window that previews the rendered infographic in a WKWebView.
/// Opened via `openWindow(id: "infographic-preview")` after the user clicks
/// Preview in `ShareLibrarySheet`. Re-renders whenever the shared
/// `InfographicConfig` changes so toggling apps in the sheet (re-opened via
/// the toolbar's **Edit Selections** button) updates the preview live.
struct InfographicPreviewWindow: View {
    @Environment(AppLibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var html: String = ""

    private var config: InfographicConfig { store.shareConfig }

    var body: some View {
        WebView(html: html)
            .frame(minWidth: 800, minHeight: 600)
            .navigationTitle("Library Infographic")
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        editSelections()
                    } label: {
                        Label("Edit Selections", systemImage: "slider.horizontal.3")
                    }
                    .help("Reopen the configuration sheet to change apps or your info")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        rerender()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button {
                        saveHTML()
                    } label: {
                        Label("Save HTML…", systemImage: "square.and.arrow.down")
                    }
                    .help("Save the infographic as a standalone HTML file")
                }
            }
            .task { rerender() }
            .onChange(of: config.excludedBundleIDs) { _, _ in rerender() }
            .onChange(of: config.displayName) { _, _ in rerender() }
            .onChange(of: config.websiteURL) { _, _ in rerender() }
    }

    private func rerender() {
        html = InfographicRenderer.render(apps: store.apps, config: config)
    }

    /// Close this window and reopen the configuration sheet on the main window.
    private func editSelections() {
        store.showShareSheet = true
        dismiss()
    }

    private func saveHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "\(safeFileNameFragment())-app-library.html"
        panel.title = "Save Infographic"
        if panel.runModal() == .OK, let url = panel.url {
            try? html.data(using: .utf8)?.write(to: url)
        }
    }

    private func safeFileNameFragment() -> String {
        let raw = config.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = raw.isEmpty ? "my" : raw.lowercased()
        return base
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
