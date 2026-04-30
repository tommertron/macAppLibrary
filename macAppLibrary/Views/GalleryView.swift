import SwiftUI

struct GalleryView: View {
    @Environment(AppLibraryStore.self) private var store

    private let cardMinWidth: CGFloat = 220
    private let spacing: CGFloat = 16

    var body: some View {
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
                galleryGrid
            }
        }
        .navigationTitle(store.navigationTitle)
        .navigationSubtitle("\(store.filteredApps.count) app\(store.filteredApps.count == 1 ? "" : "s")")
    }

    private var galleryGrid: some View {
        GeometryReader { geo in
            let columnCount = max(1, Int((geo.size.width - 40) / (cardMinWidth + spacing)))
            let rows = store.filteredApps.chunked(into: columnCount)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: spacing) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            // Card row
                            HStack(alignment: .top, spacing: spacing) {
                                ForEach(row) { app in
                                    GalleryCardView(app: app)
                                        .frame(maxWidth: .infinity)
                                        .id("card-\(app.id)")
                                }
                                // Fill remaining space if row is not full
                                if row.count < columnCount {
                                    ForEach(0..<(columnCount - row.count), id: \.self) { _ in
                                        Color.clear.frame(maxWidth: .infinity)
                                    }
                                }
                            }

                            // Expanded detail: show after the row containing the expanded app
                            if let expandedID = store.expandedAppID,
                               row.contains(where: { $0.id == expandedID }),
                               let expandedApp = store.apps.first(where: { $0.id == expandedID }) {
                                GalleryExpandedDetailView(app: expandedApp)
                                    .id("expanded-\(expandedID)")
                                    .transition(.opacity)
                            }
                        }
                    }
                    .padding(20)
                }
                .onChange(of: store.expandedAppID) { _, newID in
                    if let id = newID {
                        // Small delay lets the detail view insert into the layout first,
                        // then we smoothly scroll just enough to reveal it.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo("expanded-\(id)", anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Array chunking helper

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
