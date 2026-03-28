import SwiftUI

struct ProviderConfigurationSection: View {
    @Binding var actionName: String
    @Binding var selectedProviderID: String
    @Binding var providerAPIKey: String
    @Binding var customProviderName: String
    @Binding var customBaseURL: String
    @Binding var modelID: String

    let providers: [LLMProvider]
    let selectedProviderIsCustom: Bool
    let availableModels: [String]
    let isLoadingModels: Bool
    let modelsError: String?
    let refreshModels: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Action name", text: $actionName)

                ProviderPickerView(providers: providers, selectedProviderID: $selectedProviderID)

                if selectedProviderIsCustom {
                    TextField("Custom provider name", text: $customProviderName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Base URL", text: $customBaseURL)
                        .textFieldStyle(.roundedBorder)

                    Text("Default local endpoint: \(LLMProvider.customDefaultBaseURL)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SecureField("API key", text: $providerAPIKey)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Picker("Model", selection: $modelID) {
                        if availableModels.isEmpty {
                            Text(isLoadingModels ? "Loading..." : "No models")
                                .tag("")
                        }

                        ForEach(availableModels, id: \.self) { model in
                            Text(model)
                                .tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isLoadingModels || availableModels.isEmpty)

                    if isLoadingModels {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        refreshModels()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh models")
                }

                if let modelsError, !modelsError.isEmpty {
                    Text(modelsError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .groupBoxStyle(GlassGroupBoxStyle())
    }
}
