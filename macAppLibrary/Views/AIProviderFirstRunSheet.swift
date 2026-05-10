import SwiftUI

struct AIProviderFirstRunSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose an AI Provider")
                .font(.title2).bold()
            Text("macAppLibrary uses an AI provider to generate app descriptions. Pick one and add your API key (or point it at a local server like Ollama).")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                AIProviderConfigView()
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") {
                    AIProviderSettings.hasChosenProvider = true
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
