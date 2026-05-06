import SwiftUI

struct SettingsView: View {
    @Environment(AppLibraryStore.self) private var store
    @Environment(UpdateService.self) private var updateService
    @State private var apiKey = ""
    @State private var isSaved = false
    @State private var updateStatus: UpdateCheckStatus = .idle

    enum UpdateCheckStatus: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateInfo)
        case failed(String)
    }

    var body: some View {
        Form {
            Section("Anthropic API Key") {
                SecureField("sk-ant-…", text: $apiKey)
                    .onAppear { apiKey = KeychainHelper.load(for: "anthropic-api-key") ?? "" }

                HStack {
                    Button("Save Key") {
                        KeychainHelper.save(apiKey, for: "anthropic-api-key")
                        isSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isSaved = false }
                    }
                    .disabled(apiKey.isEmpty)

                    if isSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }

                    Spacer()

                    Button("Clear Key", role: .destructive) {
                        KeychainHelper.delete(for: "anthropic-api-key")
                        apiKey = ""
                    }
                    .disabled(apiKey.isEmpty)
                }

                Text("Used only to generate app descriptions. Stored securely in your Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section("Community Contributions") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("PR Submission — Coming Soon", systemImage: "arrow.triangle.branch")
                        .fontWeight(.medium)
                    Text("Submitting missing apps to the community database will create a GitHub pull request for review. This will be handled by a Cloudflare Worker so no GitHub account is required.")
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
        .frame(width: 480)
        .padding()
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
