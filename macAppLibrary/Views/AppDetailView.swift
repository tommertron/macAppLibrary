import SwiftUI
import AppKit

struct AppDetailView: View {
    @Environment(AppLibraryStore.self) private var store
    @State private var editedApp: AppEntry?
    @State private var isEditingDescription = false
    @State private var isRefreshingCommunity = false

    var body: some View {
        if let app = store.selectedApp {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection(app: app)
                    Divider()
                    descriptionSection(app: app)
                    Divider()
                    metadataSection(app: app)
                    Divider()
                    notesSection(app: app)
                    communitySection(app: app)
                    Spacer(minLength: 20)
                }
                .padding(24)
            }
            .navigationTitle(app.name)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        NSWorkspace.shared.openApplication(
                            at: URL(fileURLWithPath: app.bundlePath),
                            configuration: .init()
                        )
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }

                    if store.runningBundleIDs.contains(app.bundleID) {
                        Button {
                            if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == app.bundleID }) {
                                runningApp.terminate()
                            }
                        } label: {
                            Label("Quit", systemImage: "xmark.circle")
                        }
                        .tint(.red)
                    }

                    Button {
                        NSWorkspace.shared.selectFile(app.bundlePath, inFileViewerRootedAtPath: "")
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }

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
                    .tint(app.isFavorite ? .yellow : .primary)
                }
            }
            .id(app.id)
        } else {
            ContentUnavailableView(
                "Select an App",
                systemImage: "square.grid.2x2",
                description: Text("Choose an app from the list to see its details.")
            )
        }
    }

    @ViewBuilder
    private func headerSection(app: AppEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                AppIconView(bundlePath: app.bundlePath)
                    .frame(width: 80, height: 80)

                Text(app.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    DeveloperField(app: app, store: store)
                    if let version = app.version {
                        Text("Version \(version)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            CategoryPickerInline(app: app, store: store)
        }
    }

    @ViewBuilder
    private func descriptionSection(app: AppEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description")
                    .font(.headline)
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
    }

    @ViewBuilder
    private func metadataSection(app: AppEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                metaRow("Bundle ID", value: app.bundleID)
                metaRow("Version", value: app.version ?? "—")
                metaRow("Size", value: app.sizeBytes.map {
                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                } ?? (store.isLoadingMetadata ? "Loading…" : "—"))
                metaRow("Last Launched", value: app.lastLaunched.map { formatted($0) } ?? "—")
                metaRow("Last Modified", value: app.lastModified.map { formatted($0) } ?? "—")
                metaRow("Path", value: app.bundlePath)
                WebsiteRow(app: app, store: store)
            }
        }
    }

    @ViewBuilder
    private func metaRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .gridColumnAlignment(.leading)
        }
    }

    @ViewBuilder
    private func notesSection(app: AppEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
            NotesEditor(app: app, store: store)
        }
    }

    @ViewBuilder
    private func communitySection(app: AppEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Community")
                    .font(.headline)
                Spacer()
                Button {
                    isRefreshingCommunity = true
                    Task {
                        await store.refreshCommunityData(for: app.bundleID)
                        isRefreshingCommunity = false
                    }
                } label: {
                    if isRefreshingCommunity {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(isRefreshingCommunity)
                .help("Pull the latest community data for this app")
            }
            if app.communityDescription != nil {
                Label("This app has a community description", systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This app isn't in the community database yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Submit to Community…") {}
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(true)
                        .help("Coming soon — submissions will create a GitHub PR for review")
                }
            }
        }
    }

    private func formatted(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: .now)
    }
}

// MARK: - Editable developer field
struct DeveloperField: View {
    let app: AppEntry
    let store: AppLibraryStore
    @State private var isEditing = false
    @State private var text = ""

    var body: some View {
        HStack(spacing: 4) {
            if isEditing {
                TextField("Developer name", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit { commit() }
                Button("Save") { commit() }
                    .controlSize(.small)
                Button("Cancel") { isEditing = false }
                    .controlSize(.small)
            } else if let dev = app.effectiveDeveloper {
                Text(dev)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    text = app.userDeveloper ?? app.effectiveDeveloper ?? ""
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            } else {
                Button("Add developer…") {
                    text = ""
                    isEditing = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.caption)
            }
        }
    }

    private func commit() {
        var updated = app
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.userDeveloper = trimmed.isEmpty ? nil : trimmed
        store.updateApp(updated)
        isEditing = false
    }
}

// MARK: - Website Row (editable URL in metadata grid)
struct WebsiteRow: View {
    let app: AppEntry
    let store: AppLibraryStore
    @State private var isEditing = false
    @State private var urlText = ""

    var body: some View {
        GridRow {
            Text("Website")
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            HStack(spacing: 4) {
                if isEditing {
                    TextField("https://example.com", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 250)
                        .onSubmit { commit() }
                    Button("Save") { commit() }
                        .controlSize(.small)
                    Button("Cancel") { isEditing = false }
                        .controlSize(.small)
                } else if let urlString = app.effectiveWebsiteURL, let url = URL(string: urlString) {
                    Link(urlString, destination: url)
                        .font(.body)
                    Button {
                        urlText = app.userWebsiteURL ?? urlString
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(app.userWebsiteURL == nil ? "From community data — click to override" : "Edit website")
                } else {
                    Button("Add website…") {
                        urlText = ""
                        isEditing = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .font(.caption)
                }
            }
            .gridColumnAlignment(.leading)
        }
    }

    private func commit() {
        var updated = app
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.userWebsiteURL = trimmed.isEmpty ? nil : trimmed
        store.updateApp(updated)
        isEditing = false
    }
}

// MARK: - Multi-category picker with autocomplete
struct CategoryPickerInline: View {
    let app: AppEntry
    let store: AppLibraryStore
    @State private var newCategory = ""
    @State private var isAdding = false

    var body: some View {
        HStack(spacing: 4) {
            // Show existing category chips
            ForEach(app.effectiveCategories, id: \.self) { category in
                HStack(spacing: 2) {
                    Text(category)
                    // Only show remove button for user-set categories
                    if app.userCategories.contains(category) || app.userCategories.isEmpty {
                        Button {
                            removeCategory(category)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .foregroundStyle(Color.accentColor)
                .font(.subheadline)
            }

            if app.effectiveCategories.isEmpty {
                Text("Uncategorized")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                    .font(.subheadline)
            }

            if isAdding {
                CategoryAutocompleteField(
                    text: $newCategory,
                    suggestions: store.categories,
                    onCommit: { commitNew() },
                    onCancel: { isAdding = false; newCategory = "" }
                )
            } else {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func removeCategory(_ category: String) {
        var updated = app
        // If user hasn't overridden categories yet, start from effective
        if updated.userCategories.isEmpty {
            updated.userCategories = app.effectiveCategories
        }
        updated.userCategories.removeAll { $0 == category }
        store.updateApp(updated)
    }

    private func commitNew() {
        let trimmed = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { isAdding = false; newCategory = ""; return }

        var updated = app
        // If user hasn't overridden categories yet, start from effective
        if updated.userCategories.isEmpty {
            updated.userCategories = app.effectiveCategories
        }
        if !updated.userCategories.contains(trimmed) {
            updated.userCategories.append(trimmed)
        }
        store.updateApp(updated)
        isAdding = false
        newCategory = ""
    }
}

// MARK: - Autocomplete text field for categories
struct CategoryAutocompleteField: View {
    @Binding var text: String
    let suggestions: [String]
    let onCommit: () -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var filteredSuggestions: [String] {
        guard !text.isEmpty else { return [] }
        let q = text.lowercased()
        return suggestions.filter { $0.lowercased().contains(q) }.prefix(6).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                TextField("Category", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .focused($isFocused)
                    .onSubmit { onCommit() }
                Button("Add") { onCommit() }
                    .controlSize(.small)
                Button("Cancel") { onCancel() }
                    .controlSize(.small)
            }

            if !filteredSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredSuggestions, id: \.self) { suggestion in
                        Button {
                            text = suggestion
                            onCommit()
                        } label: {
                            Text(suggestion)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(.background)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .frame(width: 160)
            }
        }
        .onAppear { isFocused = true }
    }
}

// MARK: - Inline editable description
struct DescriptionEditor: View {
    let app: AppEntry
    let store: AppLibraryStore
    @State private var text = ""
    @State private var isEditing = false
    @FocusState private var focused: Bool

    var displayed: String { app.effectiveDescription ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                TextEditor(text: $text)
                    .focused($focused)
                    .font(.body)
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                HStack {
                    Button("Save") { commit() }.buttonStyle(.borderedProminent).controlSize(.small)
                    Button("Cancel") { isEditing = false }.controlSize(.small)
                }
            } else {
                if displayed.isEmpty {
                    Text("No description. Generate one with AI or type below.")
                        .foregroundStyle(.tertiary)
                        .italic()
                } else {
                    Text(displayed)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Edit Description") {
                    text = app.userDescription ?? app.communityDescription ?? ""
                    isEditing = true
                    focused = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.caption)
            }
        }
    }

    private func commit() {
        var updated = app
        updated.userDescription = text.isEmpty ? nil : text
        store.updateApp(updated)
        isEditing = false
    }
}

// MARK: - Inline notes editor
struct NotesEditor: View {
    let app: AppEntry
    let store: AppLibraryStore
    @State private var text = ""
    @State private var isEditing = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                TextEditor(text: $text)
                    .focused($focused)
                    .font(.body)
                    .frame(minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                HStack {
                    Button("Save") { commit() }.buttonStyle(.borderedProminent).controlSize(.small)
                    Button("Cancel") { isEditing = false }.controlSize(.small)
                }
            } else {
                if let notes = app.userNotes, !notes.isEmpty {
                    Text(notes)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No notes.")
                        .foregroundStyle(.tertiary)
                        .italic()
                }
                Button("Edit Notes") {
                    text = app.userNotes ?? ""
                    isEditing = true
                    focused = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.caption)
            }
        }
    }

    private func commit() {
        var updated = app
        updated.userNotes = text.isEmpty ? nil : text
        store.updateApp(updated)
        isEditing = false
    }
}
