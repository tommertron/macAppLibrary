import SwiftUI
import AppKit

struct GalleryCardView: View {
    let app: AppEntry
    @Environment(AppLibraryStore.self) private var store

    private var isExpanded: Bool {
        store.expandedAppID == app.id
    }

    @State private var isHovering = false

    private var isRunning: Bool {
        store.runningBundleIDs.contains(app.bundleID)
    }

    var body: some View {
        cardContent
            // Top-left of card: running indicator or quit button
            .overlay(alignment: .topLeading) {
                if isRunning {
                    if isHovering {
                        Button {
                            quitApp()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(.red, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Quit \(app.name)")
                        .padding(6)
                    } else {
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                            .shadow(color: .green.opacity(0.5), radius: 3)
                            .padding(8)
                    }
                }
            }
            // Top-right of card: action buttons on hover
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    HStack(spacing: 4) {
                        cardButton(icon: "arrow.up.forward.app", color: .accentColor, tooltip: "Open \(app.name)") {
                            NSWorkspace.shared.openApplication(
                                at: URL(fileURLWithPath: app.bundlePath),
                                configuration: .init()
                            )
                        }

                        cardButton(
                            icon: app.isFavorite ? "star.fill" : "star",
                            color: app.isFavorite ? .yellow : .secondary,
                            tooltip: app.isFavorite ? "Unfavorite" : "Favorite"
                        ) {
                            var updated = app
                            updated.isFavorite.toggle()
                            store.updateApp(updated)
                        }

                        cardButton(icon: "folder", color: .secondary, tooltip: "Reveal in Finder") {
                            NSWorkspace.shared.selectFile(app.bundlePath, inFileViewerRootedAtPath: "")
                        }
                    }
                    .padding(6)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isExpanded ? Color.accentColor.opacity(0.08) : Color(.controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isExpanded ? Color.accentColor.opacity(0.4) : Color(.separatorColor).opacity(0.5), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            .onTapGesture(count: 2) {
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: app.bundlePath),
                    configuration: .init()
                )
            }
            .onTapGesture(count: 1) {
                if store.expandedAppID == app.id {
                    store.expandedAppID = nil
                } else {
                    store.expandedAppID = app.id
                    store.selectedAppID = app.id
                }
            }
    }

    private var cardContent: some View {
        VStack(spacing: 10) {
            AppIconView(bundlePath: app.bundlePath)
                .frame(width: 80, height: 80)

            HStack(spacing: 4) {
                if app.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text(app.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
            }

            if !app.effectiveCategories.isEmpty {
                HStack(spacing: 4) {
                    ForEach(app.effectiveCategories.prefix(3), id: \.self) { cat in
                        Text(cat)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                }
            }

            if let desc = app.effectiveDescription {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(14)
    }

    private func cardButton(icon: String, color: Color, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(color, in: Circle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func quitApp() {
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == app.bundleID }) {
            runningApp.terminate()
        }
    }
}
