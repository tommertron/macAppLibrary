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

    @State private var isPublishing = false
    @State private var confirmingPublish = false
    @State private var publishedURL: URL?
    @State private var publishError: String?

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

                    Button {
                        confirmingPublish = true
                    } label: {
                        if isPublishing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Publish…", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(isPublishing)
                    .help("Publish this infographic to a shareable page on coefficiencies.com")
                }
            }
            .task { rerender() }
            .onChange(of: config.excludedBundleIDs) { _, _ in rerender() }
            .onChange(of: config.displayName) { _, _ in rerender() }
            .onChange(of: config.websiteURL) { _, _ in rerender() }
            .confirmationDialog(
                "Publish your library to the web?",
                isPresented: $confirmingPublish,
                titleVisibility: .visible
            ) {
                Button("Publish \(includedCount) Apps") {
                    Task { await publish() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This creates a public page on coefficiencies.com with your name, "
                     + "website, and the apps shown here. You can take it down anytime.")
            }
            .alert("Library Published", isPresented: publishedBinding) {
                Button("Open in Browser") {
                    if let url = publishedURL { NSWorkspace.shared.open(url) }
                    publishedURL = nil
                }
                Button("Done", role: .cancel) { publishedURL = nil }
            } message: {
                Text("""
                Your library is live at:
                \(publishedURL?.absoluteString ?? "")

                The link has been copied to your clipboard. The page may take a \
                minute to finish building before it loads.
                """)
            }
            .alert("Couldn’t Publish", isPresented: publishErrorBinding) {
                Button("OK", role: .cancel) { publishError = nil }
            } message: {
                Text(publishError ?? "")
            }
    }

    private var includedCount: Int {
        store.apps.filter { config.isIncluded($0.bundleID) }.count
    }

    private var publishedBinding: Binding<Bool> {
        Binding(get: { publishedURL != nil }, set: { if !$0 { publishedURL = nil } })
    }

    private var publishErrorBinding: Binding<Bool> {
        Binding(get: { publishError != nil }, set: { if !$0 { publishError = nil } })
    }

    private func publish() async {
        isPublishing = true
        defer { isPublishing = false }
        config.persist()
        do {
            let url = try await PublishService.publish(apps: store.apps, config: config)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            publishedURL = url
        } catch {
            publishError = error.localizedDescription
        }
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
