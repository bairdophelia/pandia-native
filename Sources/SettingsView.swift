import SwiftUI

// Stage 4: pulled the LAN + cloud config fields out of ContentView's old
// dual test-button layout (Stage 2/3) into their own sheet, now that
// ContentView is a real chat screen and doesn't have room for a full Form
// inline. Same fields, same behavior — this view has no logic of its own
// beyond presenting PandiaSettings' bindings and (re)triggering a LAN
// connect attempt, mirroring the PWA's separate Settings panel
// (app.js's openSettings).
struct SettingsView: View {
    @ObservedObject var settings: PandiaSettings
    @ObservedObject var lan: LANClient
    var onConnect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Home connection") {
                    TextField("PC address (e.g. 192.168.1.42:5000)", text: $settings.lanHost)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("LAN token", text: $settings.lanToken)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button(isConnecting ? "Connecting…" : (lan.isConnected ? "Reconnect" : "Connect")) {
                        isConnecting = true
                        Task {
                            onConnect()
                            // onConnect kicks off tryConnect; give it a beat
                            // to flip isConnected before dropping the spinner.
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            isConnecting = false
                        }
                    }
                    .disabled(isConnecting || settings.lanHost.isEmpty)
                    if lan.isConnected {
                        Label("Connected to Selene", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.teal)
                    }
                }

                Section("Away mode — cloud fallback") {
                    Picker("Provider", selection: $settings.cloudProvider) {
                        Text("Anthropic (recommended)").tag(CloudProvider.anthropic)
                        Text("Groq").tag(CloudProvider.groq)
                    }
                    SecureField("API key", text: $settings.cloudApiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Toggle("Ask before every cloud call", isOn: $settings.requireCloudConsent)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
