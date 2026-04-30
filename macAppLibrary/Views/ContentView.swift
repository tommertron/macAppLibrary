import SwiftUI

struct ContentView: View {
    @Environment(AppLibraryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Group {
            switch store.viewMode {
            case .list:
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
                } content: {
                    AppListView()
                        .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 500)
                } detail: {
                    AppDetailView()
                        .id(store.selectedApp?.bundleID)
                }
            case .gallery:
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
                } detail: {
                    GalleryView()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ViewModeToggle()
            }
        }
        .task {
            await store.refresh()
            store.startRunningAppsTimer()
        }
        .alert("Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct ViewModeToggle: View {
    @Environment(AppLibraryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Picker("View Mode", selection: $store.viewMode) {
            Label("List", systemImage: "list.bullet")
                .tag(ViewMode.list)
            Label("Gallery", systemImage: "square.grid.2x2")
                .tag(ViewMode.gallery)
        }
        .pickerStyle(.segmented)
        .frame(width: 100)
        .help("Switch between list and gallery view")
    }
}
