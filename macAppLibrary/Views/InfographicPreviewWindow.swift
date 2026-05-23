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

    @State private var confirmingPublish = false
    @State private var publishPhase: PublishPhase?
    @State private var publishTask: Task<Void, Never>?
    @State private var publishBackgrounded = false

    /// Stages of a publish, surfaced in the progress sheet.
    enum PublishPhase: Equatable, Identifiable {
        case submitting               // POSTing the payload to the worker
        case building(URL)            // committed; polling until the page is live
        case live(URL, confirmed: Bool) // confirmed=false means we stopped waiting first
        case failed(String)

        var id: String {
            switch self {
            case .submitting: return "submitting"
            case .building(let url): return "building-\(url.absoluteString)"
            case .live(let url, let confirmed): return "live-\(confirmed)-\(url.absoluteString)"
            case .failed(let message): return "failed-\(message)"
            }
        }
    }

    private var isPublishing: Bool {
        switch publishPhase {
        case .submitting, .building: return true
        default: return false
        }
    }

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
                Button("Publish \(includedCount) Apps") { startPublish() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This creates a public page on coefficiencies.com with your name, "
                     + "website, and the apps shown here. You can take it down anytime.")
            }
            .sheet(item: publishPhaseBinding) { phase in
                PublishProgressSheet(
                    phase: phase,
                    onOpen: { url in NSWorkspace.shared.open(url) },
                    onBackground: backgroundPublish,
                    onDismiss: dismissPublish
                )
            }
    }

    private var includedCount: Int {
        store.apps.filter { config.isIncluded($0.bundleID) }.count
    }

    /// Bridges the optional phase to `.sheet(item:)` (needs an `Identifiable`).
    private var publishPhaseBinding: Binding<PublishPhase?> {
        Binding(get: { publishPhase }, set: { publishPhase = $0 })
    }

    private func startPublish() {
        config.persist()
        publishBackgrounded = false
        publishPhase = .submitting
        PublishNotifier.shared.requestAuthorization()
        publishTask = Task {
            do {
                let url = try await PublishService.publish(apps: store.apps, config: config)
                // Copy the link right away so it's usable even while building.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                if Task.isCancelled { return }
                if !publishBackgrounded { publishPhase = .building(url) }

                let live = await PublishService.waitUntilLive(url)
                if Task.isCancelled { return }
                if publishBackgrounded {
                    // Sheet was dismissed — deliver the result as a notification.
                    PublishNotifier.shared.notifyLive(url: url, displayName: config.displayName, confirmed: live)
                } else {
                    publishPhase = .live(url, confirmed: live)
                }
            } catch {
                if Task.isCancelled { return }
                if publishBackgrounded {
                    PublishNotifier.shared.notifyFailed(message: error.localizedDescription)
                } else {
                    publishPhase = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// "Continue in Background" while building: hide the sheet but keep polling;
    /// the result arrives as a notification.
    private func backgroundPublish() {
        publishBackgrounded = true
        publishPhase = nil
    }

    private func dismissPublish() {
        publishTask?.cancel()
        publishTask = nil
        publishPhase = nil
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

/// Modal progress for a publish: spins through submit → build, then resolves to
/// a "live" or "failed" state. Keeps the user from re-publishing mid-flight and
/// only announces success once the page has actually been verified online.
private struct PublishProgressSheet: View {
    let phase: InfographicPreviewWindow.PublishPhase
    let onOpen: (URL) -> Void
    let onBackground: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            content
        }
        .padding(28)
        .frame(width: 380)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .submitting:
            ProgressView()
                .controlSize(.large)
            Text("Publishing your library…")
                .font(.headline)
            Text("Uploading your apps to coefficiencies.com.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

        case .building:
            ProgressView()
                .controlSize(.large)
            Text("Building your page…")
                .font(.headline)
            Text("This usually takes a minute or two while the site rebuilds. "
                 + "The link is already on your clipboard.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Continue in Background", action: onBackground)
                .buttonStyle(.link)
            Text("We’ll notify you when it’s ready.")
                .font(.caption)
                .foregroundStyle(.tertiary)

        case .live(let url, let confirmed):
            Image(systemName: confirmed ? "checkmark.circle.fill" : "clock.badge.checkmark")
                .font(.system(size: 44))
                .foregroundStyle(confirmed ? Color.green : Color.accentColor)
            Text(confirmed ? "Your library is live!" : "Almost there…")
                .font(.headline)
            Text(confirmed
                 ? "It’s published and loading. The link is on your clipboard."
                 : "Published — your page is still finishing its build and should "
                   + "load shortly. The link is on your clipboard.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link(url.absoluteString, destination: url)
                .font(.footnote)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Button("Open in Browser") { onOpen(url); onDismiss() }
                    .keyboardShortcut(.defaultAction)
                Button("Done", action: onDismiss)
            }
            .padding(.top, 4)

        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Couldn’t Publish")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("OK", action: onDismiss)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
        }
    }
}
