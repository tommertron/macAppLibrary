import SwiftUI

struct SettingsView: View {
    @Environment(AppLibraryStore.self) private var store
    @Environment(UpdateService.self) private var updateService
    @State private var updateStatus: UpdateCheckStatus = .idle
    @AppStorage(APIServer.mcpEnabledKey) private var mcpEnabled = false
    @AppStorage("menubarEnabled") private var menubarEnabled = true
    @AppStorage(JSONDataExporter.enabledKey) private var jsonExportEnabled = false
    @AppStorage(JSONDataExporter.customPathKey) private var jsonExportCustomPath = ""
    @State private var apiInfo: APIDiscoveryInfo?
    @State private var claudeInstallStatus: ClaudeInstallStatus = .idle

    enum ClaudeInstallStatus: Equatable {
        case idle
        case success
        case failure(String)
    }

    enum UpdateCheckStatus: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateInfo)
        case failed(String)
    }

    var body: some View {
        Form {
            Section("AI Provider") {
                AIProviderConfigView()
            }

            Section("Smart Lists") {
                @Bindable var store = store
                ThresholdRow(
                    label: "Unused Apps: not launched in",
                    threshold: $store.unusedThreshold
                )
                ThresholdRow(
                    label: "New Apps: installed within",
                    threshold: $store.newAppsThreshold
                )
                ThresholdRow(
                    label: "Recently Updated: within",
                    threshold: $store.recentlyUpdatedThreshold
                )
            }

            Section("Community Data") {
                Text("App descriptions are crowd-sourced from a GitHub-hosted JSON file. Your local edits always take precedence over community data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Refresh Community Data") {
                    Task { await store.refresh() }
                }
            }

            Section("JSON Data Export") {
                Toggle("Export library to JSON file", isOn: $jsonExportEnabled)
                    .onChange(of: jsonExportEnabled) { _, newValue in
                        if newValue {
                            Task { await store.exportJSONNow() }
                        }
                    }

                LabeledContent("Location") {
                    HStack {
                        Text(jsonExportCustomPath.isEmpty ? JSONDataExporter.defaultDirectory.path : jsonExportCustomPath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseExportDirectory() }
                        if !jsonExportCustomPath.isEmpty {
                            Button("Reset") { jsonExportCustomPath = "" }
                        }
                    }
                }

                HStack {
                    Button("Export Now") {
                        Task { await store.exportJSONNow() }
                    }
                    .disabled(!jsonExportEnabled)

                    Button("Reveal in Finder") {
                        let dir = JSONDataExporter.resolvedDirectory
                        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([dir.appendingPathComponent("apps.json")])
                    }
                    .disabled(!jsonExportEnabled)
                }

                Text("Writes apps.json whenever your library changes. Useful for Raycast/Alfred/CLI workflows that need offline access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menubar") {
                Toggle("Show macAppLibrary in menubar", isOn: $menubarEnabled)
                Text("Adds a menubar icon with quick access to favourites, running apps, and categories.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("MCP Server") {
                Toggle("Enable MCP server", isOn: $mcpEnabled)

                Text("Lets MCP-aware tools (Claude Desktop, IDE plugins) read and edit your library. Off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if mcpEnabled, let info = apiInfo {
                    let url = "http://127.0.0.1:\(info.port)/mcp"
                    LabeledContent("URL") {
                        HStack {
                            Text(url).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url, forType: .string)
                            } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        Button("Install for Claude Desktop") {
                            installForClaudeDesktop(port: info.port, token: info.token)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Copy config") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(claudeDesktopConfig(url: url, token: info.token), forType: .string)
                        }
                    }

                    switch claudeInstallStatus {
                    case .idle:
                        Text("Builds an MCP extension with this server's port and token, then hands it to Claude Desktop to install. Uses Claude Desktop's bundled Node — no separate install required.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .success:
                        Label("Sent to Claude Desktop — confirm the install prompt over there.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    case .failure(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if mcpEnabled {
                    Text("Waiting for API server to publish discovery info…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Updates") {
                if let last = updateService.lastChecked {
                    LabeledContent("Last Checked", value: last.formatted(date: .abbreviated, time: .shortened))
                }

                HStack {
                    Button("Check for Updates") {
                        Task { await runUpdateCheck() }
                    }
                    .disabled(updateStatus == .checking)

                    switch updateStatus {
                    case .idle:
                        EmptyView()
                    case .checking:
                        ProgressView().controlSize(.small)
                    case .upToDate:
                        Label("Up to date", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    case .available(let info):
                        Button("Download \(info.latestVersion)") {
                            updateService.openDownloadPage()
                        }
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: updateService.currentVersion)
                LabeledContent("Build", value: updateService.currentBuild)
                LabeledContent("Source", value: "github.com/tommertron/macAppLibrary")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
        .onAppear { apiInfo = APIDiscoveryInfo.load() }
    }

    private func claudeDesktopConfig(url: String, token: String) -> String {
        """
        {
          "mcpServers": {
            "macAppLibrary": {
              "command": "npx",
              "args": [
                "-y",
                "mcp-remote",
                "\(url)",
                "--header",
                "Authorization:${AUTH_HEADER}",
                "--allow-http",
                "--transport",
                "http-only"
              ],
              "env": {
                "AUTH_HEADER": "Bearer \(token)"
              }
            }
          }
        }
        """
    }

    private func installForClaudeDesktop(port: Int, token: String) {
        do {
            _ = try ClaudeDesktopInstaller.installMCPB(port: port, token: token)
            // Claude Desktop now owns the install flow — show a soft-success
            // hint while it presents its own prompt.
            claudeInstallStatus = .success
        } catch {
            claudeInstallStatus = .failure(error.localizedDescription)
        }
    }

    private func chooseExportDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            jsonExportCustomPath = url.path
            if jsonExportEnabled {
                Task { await store.exportJSONNow() }
            }
        }
    }

    private func runUpdateCheck() async {
        updateStatus = .checking
        do {
            let info = try await updateService.check()
            updateStatus = info.isUpdateAvailable ? .available(info) : .upToDate
        } catch {
            updateStatus = .failed("Couldn't check: \(error.localizedDescription)")
        }
    }
}

struct APIDiscoveryInfo {
    let host: String
    let port: Int
    let token: String

    static func load() -> APIDiscoveryInfo? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appendingPathComponent("macAppLibrary/api.json")
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let host = json["host"] as? String,
            let port = json["port"] as? Int,
            let token = json["token"] as? String
        else { return nil }
        return APIDiscoveryInfo(host: host, port: port, token: token)
    }
}

private struct ThresholdRow: View {
    let label: String
    @Binding var threshold: ThresholdDuration

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField("", value: $threshold.value, format: .number)
                    .frame(width: 48)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.squareBorder)

                Picker("", selection: $threshold.unit) {
                    ForEach(TimeUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: 90)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppLibraryStore())
        .environment(UpdateService())
}
