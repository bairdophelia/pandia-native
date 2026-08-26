import SwiftUI
import SwiftData

// Stage 4: the real chat screen, replacing Stage 2/3's two independent
// test-button sections now that PandiaBrain.swift ties LAN and cloud
// together. One Send button, one decision (home-first, cloud-fallback —
// see PandiaBrain.reply), one persisted history via SwiftData (ChatTurn.swift,
// replacing the PWA's IndexedDB). LAN/cloud config moved to SettingsView,
// reached via the gear icon, same split the PWA has between its chat
// screen and its Settings panel.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatTurn.timestamp) private var turns: [ChatTurn]

    @StateObject private var settings = PandiaSettings()
    @StateObject private var lan = LANClient()

    @State private var draft = ""
    @State private var isSending = false
    @State private var showSettings = false
    @State private var hasAttemptedInitialConnect = false

    @State private var pendingConsentProvider: CloudProvider?
    @State private var consentResolver: ((Bool) -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusLine
                    .padding(.top, 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(turns) { turn in
                                ChatBubble(turn: turn)
                                    .id(turn.persistentModelID)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: turns.count) {
                        if let last = turns.last {
                            withAnimation { proxy.scrollTo(last.persistentModelID, anchor: .bottom) }
                        }
                    }
                }

                inputBar
            }
            .navigationTitle("P.A.N.D.I.A.")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings, lan: lan, onConnect: attemptConnect)
            }
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
            .task {
                guard !hasAttemptedInitialConnect else { return }
                hasAttemptedInitialConnect = true
                if !settings.lanHost.isEmpty {
                    attemptConnect()
                }
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if lan.isConnected {
            Label("Home — connected to Selene", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.teal)
                .font(.footnote)
        } else if !settings.lanHost.isEmpty {
            Label("Away — using cloud fallback", systemImage: "cloud.fill")
                .foregroundStyle(.secondary)
                .font(.footnote)
        } else {
            Text("Set up Selene's address in Settings to enable home mode.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var inputBar: some View {
        HStack {
            TextField("Message Pandia…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            Button {
                send()
            } label: {
                Image(systemName: isSending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
            }
            .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    private func attemptConnect() {
        Task {
            _ = await lan.tryConnect(host: settings.lanHost, token: settings.lanToken)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        isSending = true

        let userTurn = ChatTurn(role: "user", text: text)
        modelContext.insert(userTurn)

        // Same 20-turn window brain.js's awayModeReply is handed for
        // context — see app.js's sendText.
        let history = turns.suffix(20).map { ChatMessage(role: $0.role, text: $0.text) }

        Task {
            let reply = await PandiaBrain.reply(
                to: text,
                history: history,
                lan: lan,
                settings: settings,
                confirm: { provider in
                    await withCheckedContinuation { continuation in
                        Task { @MainActor in
                            pendingConsentProvider = provider
                            consentResolver = { continuation.resume(returning: $0) }
                        }
                    }
                }
            )
            let assistantTurn = ChatTurn(role: "assistant", text: reply.text, source: reply.source)
            modelContext.insert(assistantTurn)
            isSending = false
        }
    }

    private func resolveConsent(_ allowed: Bool) {
        pendingConsentProvider = nil
        consentResolver?(allowed)
        consentResolver = nil
    }
}

private struct ChatBubble: View {
    let turn: ChatTurn

    var body: some View {
        VStack(alignment: turn.role == "user" ? .trailing : .leading, spacing: 2) {
            Text(turn.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(turn.role == "user" ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            if let source = turn.source {
                Text(sourceLabel(source))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: turn.role == "user" ? .trailing : .leading)
    }

    // "lan"/"local" both mean Selene answered from home (her own
    // brain_source event refines "lan" to "local" when SHE used her PC-side
    // model — see PandiaBrain.swift's Reply.source doc comment). "device"
    // is a different thing: this phone's own on-device model (Stage 5,
    // LocalBrain.swift) answering with no PC involved at all. Anything
    // else is whichever cloud provider actually answered, or "error" when
    // nothing could.
    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "lan", "local": return "Selene · home"
        case "device": return "this phone · offline"
        case "error": return "couldn't reach either brain"
        default: return "cloud · \(source.capitalized)"
        }
    }
}
