import SwiftUI

struct ContentView: View {
    @Environment(AppLibraryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
        } content: {
            AppListView()
        } detail: {
            AppDetailView()
        }
        .task { await store.refresh() }
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
