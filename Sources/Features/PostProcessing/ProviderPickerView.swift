import SwiftUI

struct ProviderPickerView: View {
    let providers: [LLMProvider]
    @Binding var selectedProviderID: String

    var body: some View {
        Picker("Provider", selection: $selectedProviderID) {
            ForEach(providers, id: \.id) { provider in
                Text(provider.displayName)
                    .tag(provider.id)
            }
        }
        .pickerStyle(.menu)
    }
}
