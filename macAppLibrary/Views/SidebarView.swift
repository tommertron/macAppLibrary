import SwiftUI

struct SidebarView: View {
    @Environment(AppLibraryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: $store.sidebarSelection) {

            // All Apps
            Label("All Apps", systemImage: "square.grid.2x2")
                .tag(SidebarSelection.all)
                .padding(.vertical, 1)

            // Pinned items
            if !store.pinnedItems.isEmpty {
                Section("Pinned") {
                    ForEach(store.pinnedItems, id: \.self) { pin in
                        pinnedRow(for: pin)
                            .tag(pin.sidebarSelection)
                            .padding(.vertical, 1)
                            .contextMenu {
                                Button("Unpin") {
                                    store.togglePin(for: pin.sidebarSelection)
                                }
                            }
                    }
                }
            }

            // Smart Lists
            CollapsibleSection(title: "Smart Lists", sectionID: "smartLists", store: store) {
                ForEach(SmartFilter.allCases) { filter in
                    HStack {
                        Label(filter.rawValue, systemImage: filter.icon)
                            .foregroundStyle(filter == .running ? .green : .primary)
                        Spacer()
                        let n = store.count(for: filter)
                        if n > 0 {
                            Text("\(n)")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(SidebarSelection.smartFilter(filter))
                    .padding(.vertical, 1)
                    .contextMenu {
                        pinContextMenu(for: .smartFilter(filter))
                    }
                }
            }

            // Categories
            CollapsibleSection(title: "Categories", sectionID: "categories", store: store) {
                ForEach(store.categories, id: \.self) { category in
                    Label(category, systemImage: categoryIcon(for: category))
                        .tag(SidebarSelection.category(category))
                        .padding(.vertical, 1)
                        .contextMenu {
                            pinContextMenu(for: .category(category))
                        }
                }
            }

            // Developers
            CollapsibleSection(title: "Developers", sectionID: "developers", store: store) {
                ForEach(store.developers, id: \.self) { developer in
                    Label(developer, systemImage: "person")
                        .tag(SidebarSelection.developer(developer))
                        .padding(.vertical, 1)
                        .contextMenu {
                            pinContextMenu(for: .developer(developer))
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("App Library")
        .searchable(text: $store.searchText, placement: .sidebar, prompt: "Search apps…")
        .toolbar {
            ToolbarItem {
                if store.isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pinnedRow(for pin: SidebarPin) -> some View {
        switch pin.kind {
        case .smartFilter:
            if let filter = SmartFilter(rawValue: pin.value) {
                HStack {
                    Label(filter.rawValue, systemImage: filter.icon)
                        .foregroundStyle(filter == .running ? .green : .primary)
                    Spacer()
                    let n = store.count(for: filter)
                    if n > 0 {
                        Text("\(n)")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .category:
            Label(pin.value, systemImage: categoryIcon(for: pin.value))
        case .developer:
            Label(pin.value, systemImage: "person")
        }
    }

    @ViewBuilder
    private func pinContextMenu(for selection: SidebarSelection) -> some View {
        let pinned = store.isPinned(selection)
        Button(pinned ? "Unpin" : "Pin to Top") {
            store.togglePin(for: selection)
        }
    }

    private func categoryIcon(for category: String) -> String {
        let c = category.lowercased()
        if c.contains("developer") { return "hammer" }
        if c.contains("productivity") { return "checkmark.circle" }
        if c.contains("utilities") || c.contains("utility") { return "wrench.and.screwdriver" }
        if c.contains("graphics") || c.contains("design") { return "paintbrush" }
        if c.contains("music") || c.contains("audio") { return "music.note" }
        if c.contains("video") { return "film" }
        if c.contains("social") { return "bubble.left.and.bubble.right" }
        if c.contains("news") { return "newspaper" }
        if c.contains("business") { return "briefcase" }
        if c.contains("photo") { return "photo" }
        if c.contains("game") || c.contains("entertain") { return "gamecontroller" }
        if c.contains("food") { return "fork.knife" }
        if c.contains("health") { return "heart" }
        if c.contains("reference") { return "books.vertical" }
        return "app"
    }
}

/// A sidebar section that can be collapsed/expanded by the user, with state persisted.
struct CollapsibleSection<Content: View>: View {
    let title: String
    let sectionID: String
    let store: AppLibraryStore
    @ViewBuilder let content: () -> Content

    private var isCollapsed: Bool {
        store.collapsedSections.contains(sectionID)
    }

    var body: some View {
        Section {
            if !isCollapsed {
                content()
            }
        } header: {
            Button {
                if isCollapsed {
                    store.collapsedSections.remove(sectionID)
                } else {
                    store.collapsedSections.insert(sectionID)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(title)
                    Spacer()
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    NavigationSplitView {
        SidebarView()
    } detail: {
        Text("Detail")
    }
    .environment(AppLibraryStore())
}
