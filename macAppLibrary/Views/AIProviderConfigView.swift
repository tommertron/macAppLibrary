import SwiftUI

struct AIProviderConfigView: View {
    @State private var provider: AIProviderID = AIProviderSettings.selectedProvider
    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var model: String = ""
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var fetchError: String?
    @State private var savedFlash = false

    var body: some View {
        Picker("Provider", selection: $provider) {
            ForEach(AIProviderID.allCases) { p in
                Text(p.displayName).tag(p)
            }
        }
        .onChange(of: provider) { _, newValue in
            AIProviderSettings.setSelectedProvider(newValue)
            AIProviderSettings.hasChosenProvider = true
            loadProvider()
        }

        SecureField(provider == .anthropic ? "sk-ant-…" : "API key (leave empty for local servers)", text: $apiKey)

        if provider == .openAICompatible {
            TextField("Base URL", text: $baseURL)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(true)
                .help("Examples: https://api.openai.com/v1, https://openrouter.ai/api/v1, http://localhost:11434/v1 (Ollama), http://localhost:1234/v1 (LM Studio)")
        }

        HStack {
            if availableModels.isEmpty {
                TextField("Model", text: $model)
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker("Model", selection: $model) {
                    ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                    if !availableModels.contains(model), !model.isEmpty {
                        Text("\(model) (custom)").tag(model)
                    }
                }
                .labelsHidden()
            }

            Button {
                Task { await fetchModels() }
            } label: {
                if isFetchingModels {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .help("Fetch available models from this provider")
            .disabled(isFetchingModels)
        }

        HStack {
            Button("Save") { save() }
            if savedFlash {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            Spacer()
            Button("Clear Key", role: .destructive) {
                KeychainHelper.delete(for: provider.keychainKey)
                apiKey = ""
            }
            .disabled(apiKey.isEmpty)
        }

        if let fetchError {
            Text(fetchError)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        Text("API key is stored securely in your Keychain and used only for generating app descriptions.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .onAppear(perform: loadProvider)
    }

    private func loadProvider() {
        apiKey = AIProviderSettings.apiKey(for: provider) ?? ""
        baseURL = AIProviderSettings.baseURL(for: provider)
        model = AIProviderSettings.model(for: provider)
        availableModels = []
        fetchError = nil
    }

    private func save() {
        if !apiKey.isEmpty {
            KeychainHelper.save(apiKey, for: provider.keychainKey)
        }
        AIProviderSettings.setBaseURL(baseURL, for: provider)
        AIProviderSettings.setModel(model, for: provider)
        AIProviderSettings.hasChosenProvider = true
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedFlash = false }
    }

    private func fetchModels() async {
        // Persist any in-flight key/baseURL first so the fetch uses them.
        save()
        isFetchingModels = true
        fetchError = nil
        defer { isFetchingModels = false }
        do {
            let models = try await AIService.fetchModels(for: provider)
            availableModels = models
            if model.isEmpty, let first = models.first { model = first }
        } catch {
            fetchError = "Couldn't fetch models: \(error.localizedDescription)"
        }
    }
}
