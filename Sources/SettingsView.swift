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

    // Bug fix / upgrade (2026-08-28): localModelId was already a free
    // string in Settings.swift, but this view only ever showed it as
    // read-only Text — no way to actually change it without editing code.
    // Curated to two options rather than a long list: both are the SAME
    // architecture family (Llama 3.2) as the 1B default this project has
    // already confirmed loads and runs correctly end-to-end on Fia's
    // phone, which matters — mlx-swift-lm has to explicitly support a
    // model's architecture (see LocalBrain.swift's "highest-uncertainty
    // file" doc comment on how much CI back-and-forth THIS family's
    // support took to nail down). Reaching for a newer/different family
    // (Qwen3.5, Gemma 4, etc.) is a reasonable later experiment, just a
    // real risk of repeating that same round of trial-and-error — Custom
    // is there for exactly that, opted into deliberately rather than
    // stumbled into.
    // 3B's label downgraded from "recommended" (2026-09-01) after it
    // crashed on an actual device — almost certainly memory pressure, not
    // something a retry fixes. Left in the list rather than removed: it
    // may well be fine on a newer/higher-RAM phone, just not something to
    // imply is a safe default the way "recommended" did.
    private static let presetModels: [(label: String, id: String)] = [
        ("Llama 3.2 1B — fastest, most reliable (~0.7 GB)", "mlx-community/Llama-3.2-1B-Instruct-4bit"),
        ("Llama 3.2 3B — better replies, may crash on some phones (~1.8 GB)", "mlx-community/Llama-3.2-3B-Instruct-4bit"),
    ]
    private static let customTag = "custom"

    private var modelSelection: Binding<String> {
        Binding(
            get: {
                Self.presetModels.contains { $0.id == settings.localModelId } ? settings.localModelId : Self.customTag
            },
            set: { newValue in
                guard newValue != Self.customTag else { return }
                settings.localModelId = newValue
            }
        )
    }

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
                            .foregroundStyle(.seleneMoonWhite)
                    }
                }

                Section {
                    Toggle("Use on-device model when away", isOn: $settings.useLocalModel)
                    if settings.useLocalModel {
                        Picker("Model", selection: modelSelection) {
                            ForEach(Self.presetModels, id: \.id) { model in
                                Text(model.label).tag(model.id)
                            }
                            Text("Custom…").tag(Self.customTag)
                        }
                        .pickerStyle(.navigationLink)
                        if modelSelection.wrappedValue == Self.customTag {
                            TextField("mlx-community/… (Hugging Face repo id)", text: $settings.localModelId)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.caption)
                        }
                        Toggle("Local only — don't fall back to cloud", isOn: $settings.localOnlyMode)
                        // Added (2026-09-01), Fia's direct ask to try the
                        // full personality prompt again now that a real
                        // progress bar (LocalBrainProgress) means waiting
                        // on a load reads as "downloading," not "stuck."
                        // Off by default — see Settings.swift's doc
                        // comment: the condensed prompt is what actually
                        // held up on the default 1B model.
                        Toggle("Use full personality prompt", isOn: $settings.useFullPersonalityPrompt)
                    }
                } header: {
                    Text("On-device model (experimental)")
                } footer: {
                    // Stage 5, LocalBrain.swift — tried between LAN and
                    // cloud (see PandiaBrain.swift). Off by default: the
                    // first message after turning this on downloads the
                    // model (several hundred MB) before it can answer, so
                    // worth doing on WiFi the first time. Switching models
                    // (2026-08-28) downloads the new one the same way —
                    // it's a different set of weights, not a config
                    // tweak — so also worth doing that switch on WiFi.
                    Text("Answers on this phone with no internet needed, once the model's downloaded. First use (and switching models) downloads it — do that on WiFi; you'll see real progress while it does. Normally falls back to cloud if it's not ready yet; turn on \"Local only\" to see the real error instead, useful while testing. \"Full personality prompt\" is the same one Selene's cloud replies use — more character, but a lot for a small model to hold onto; worth trying on 3B or larger, not recommended on 1B.")
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
            .tint(.seleneTeal)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
