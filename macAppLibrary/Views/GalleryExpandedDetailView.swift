import SwiftUI
import AppKit

struct GalleryExpandedDetailView: View {
    let app: AppEntry
    @Environment(AppLibraryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header bar with actions
            HStack {
                AppIconView(bundlePath: app.bundlePath)
                    .frame(width: 40, height: 40)

                Text(app.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.openApplication(
                            at: URL(fileURLWithPath: app.bundlePath),
                            configuration: .init()
                        )
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        NSWorkspace.shared.selectFile(app.bundlePath, inFileViewerRootedAtPath: "")
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        var updated = app
                        updated.isFavorite.toggle()
                        store.updateApp(updated)
                    } label: {
                        Label(
                            app.isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: app.isFavorite ? "star.fill" : "star"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(app.isFavorite ? .yellow : nil)

                    Button {
                        store.expandedAppID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Collapse")
                }
            }

            Divider()

            // Two-column layout: description/notes on left, metadata on right
            HStack(alignment: .top, spacing: 24) {
                // Left column
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Description")
                                .font(.headline)
                            CommunityPullButton(
                                state: communityStringPullState(app.communityDescription, current: app.effectiveDescription),
                                action: {
                                    var updated = app
                                    updated.userDescription = app.communityDescription
                                    store.updateApp(updated)
                                }
                            )
                            Spacer()
                            if store.generatingDescriptionFor == app.id {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Button("Generate with AI") {
                                    Task { await store.generateDescription(for: app.id) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        DescriptionEditor(app: app, store: store)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        NotesEditor(app: app, store: store)
                    }

                    Divider()

                    CommunitySectionView(app: app, store: store)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right column
                VStack(alignment: .leading, spacing: 12) {
                    DeveloperField(app: app, store: store)
                    CategoryPickerInline(app: app, store: store)

                    Divider()

                    AppMetadataGrid(app: app, store: store)
                        .font(.subheadline)
                }
                .frame(maxWidth: 300, alignment: .leading)
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        }
        .id(app.id)
    }

}
