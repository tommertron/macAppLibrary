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

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(bundlePath: app.bundlePath)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .fontWeight(.medium)
                if let desc = app.effectiveDescription {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if !app.effectiveCategories.isEmpty {
                    Text(app.effectiveCategories.joined(separator: ", "))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let size = app.sizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if app.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 2)
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
