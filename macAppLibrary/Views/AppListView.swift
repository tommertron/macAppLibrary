import SwiftUI
import AppKit

struct AppListView: View {
    @Environment(AppLibraryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Group {
            if store.isLoading && store.apps.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning applications…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.filteredApps.isEmpty {
                ContentUnavailableView(
                    "No Apps Found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search or category.")
                )
            } else {
                List(store.filteredApps, id: \.id, selection: $store.selectedAppID) { app in
                    AppRowView(app: app)
                        .tag(app.id)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(store.navigationTitle)
        .navigationSubtitle("\(store.filteredApps.count) app\(store.filteredApps.count == 1 ? "" : "s")")
    }
}

struct AppRowView: View {
    let app: AppEntry
    @Environment(AppLibraryStore.self) private var store

    private var isRunning: Bool {
        store.runningBundleIDs.contains(app.bundleID)
    }

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(bundlePath: app.bundlePath)
                .frame(width: 40, height: 40)
                .overlay(alignment: .topLeading) {
                    if app.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                            .shadow(color: .black.opacity(0.3), radius: 1)
                            .offset(x: -4, y: -4)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .fontWeight(.medium)
                if let desc = app.effectiveDescription {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(app.bundleID)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if !app.effectiveCategories.isEmpty {
                    Text(app.effectiveCategories.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .lineLimit(1)
                        .compositingGroup()
                }
                if let size = app.sizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Circle()
                .fill(isRunning ? .green : .clear)
                .stroke(isRunning ? .clear : Color.secondary.opacity(0.3), lineWidth: 1)
                .frame(width: 8, height: 8)
                .help(isRunning ? "Running" : "Not running")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct AppIconView: View {
    let bundlePath: String
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(contentMode: .fit)
        .task(id: bundlePath) {
            icon = await loadIcon(bundlePath)
        }
    }

    private func loadIcon(_ path: String) async -> NSImage? {
        await MainActor.run {
            NSWorkspace.shared.icon(forFile: path)
        }
    }
}
