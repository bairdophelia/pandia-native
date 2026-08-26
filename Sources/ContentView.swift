import SwiftUI

// Stage 3: LAN connect (Stage 2) plus an independently-testable cloud
// fallback path — a message field, a consent alert (same gate brain.js
// enforces: no cloud call fires without an explicit yes when
// requireCloudConsent is on), and the reply or error shown right on
// screen. No chat history, no local model yet — see ../README.md's staged
// plan. Not meant to be the permanent UI; gets replaced by a real chat
// screen once all three brains (LAN, cloud, local) are proven individually.
struct ContentView: View {
    @StateObject private var settings = PandiaSettings()
    @StateObject private var lan = LANClient()

    @State private var isConnecting = false
    @State private var lanFailed = false

    @State private var testMessage = ""
    @State private var cloudReply = ""
    @State private var isSending = false
    @State private var pendingConsentProvider: CloudProvider?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)
            Text("Pandia")
                .font(.title2)
                .bold()

            statusLine

            Form {
                Section("Home connection") {
                    TextField("PC address (e.g. 192.168.1.42:5000)", text: $settings.lanHost)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("LAN token", text: $settings.lanToken)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button(isConnecting ? "Connecting…" : "Connect") { attemptConnect() }
                        .disabled(isConnecting || settings.lanHost.isEmpty)
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

                Section("Test cloud message") {
                    TextField("Say something…", text: $testMessage)
                    Button(isSending ? "Sending…" : "Send via cloud") { attemptCloudSend() }
                        .disabled(isSending || testMessage.isEmpty || settings.cloudApiKey.isEmpty)
                    if !cloudReply.isEmpty {
                        Text(cloudReply)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.top)
        .alert(
            "Send this to the cloud?",
            isPresented: Binding(
                get: { pendingConsentProvider != nil },
                set: { if !$0 { pendingConsentProvider = nil } }
            )
        ) {
            Button("Not now", role: .cancel) { resolveConsent(false) }
            Button("Send it") { resolveConsent(true) }
        } message: {
            Text("Selene's not reachable, so this would go straight to \(pendingConsentProvider?.rawValue.capitalized ?? "the cloud") instead of staying on your phone.")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if lan.isConnected {
            Label("Home — connected to Selene", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.teal)
        } else if lanFailed {
            Label("Couldn't reach Selene", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            Text("Native build pipeline — online.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func attemptConnect() {
        isConnecting = true
        lanFailed = false
        Task {
            let ok = await lan.tryConnect(host: settings.lanHost, token: settings.lanToken)
            isConnecting = false
            lanFailed = !ok
        }
    }

    private func attemptCloudSend() {
        isSending = true
        cloudReply = ""
        let message = testMessage
        Task {
            do {
                let reply = try await CloudBrain.complete(
                    history: [ChatMessage(role: "user", text: message)],
                    provider: settings.cloudProvider,
                    apiKey: settings.cloudApiKey,
                    requireConsent: settings.requireCloudConsent,
                    confirm: { provider in
                        await withCheckedContinuation { continuation in
                            Task { @MainActor in
                                pendingConsentProvider = provider
                                consentResolver = { continuation.resume(returning: $0) }
                            }
                        }
                    }
                )
                cloudReply = reply
            } catch {
                cloudReply = error.localizedDescription
            }
            isSending = false
        }
    }

    // Bridges the alert's Yes/No taps back into CloudBrain's `confirm`
    // async closure: CloudBrain suspends on withCheckedContinuation until
    // resolveConsent() below calls this, which only happens from a button
    // tap. @State (not a plain var) so it survives this struct's view
    // updates between the alert appearing and being answered.
    @State private var consentResolver: ((Bool) -> Void)?

    private func resolveConsent(_ allowed: Bool) {
        pendingConsentProvider = nil
        consentResolver?(allowed)
        consentResolver = nil
    }
}
