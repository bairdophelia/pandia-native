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
            .background(Color.seleneInk.ignoresSafeArea())
            .tint(.seleneTeal)
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
                .foregroundStyle(.seleneTeal)
                .font(.footnote)
        } else if !settings.lanHost.isEmpty {
            Label("Away — using cloud fallback", systemImage: "cloud.fill")
                .foregroundStyle(.seleneOrange)
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
            let connected = await lan.tryConnect(host: settings.lanHost, token: settings.lanToken)
            if connected {
                await syncPendingTurnsIfNeeded()
            }
        }
    }

    /// Stage 6: the native equivalent of sync.js's syncPendingTurns, run
    /// once per successful reconnect (see attemptConnect above) — mirrors
    /// when the PWA calls it (app.js, right after wireLanEvents' connect
    /// handler fires). Pairs consecutive unsynced (user, assistant) turns
    /// and hands them to Selene via LANClient.syncTurns; a stray trailing
    /// unpaired turn (message sent, app closed before a reply came back)
    /// is left unsynced on purpose — same reasoning as sync.js.
    private func syncPendingTurnsIfNeeded() async {
        let unsynced = turns.filter { !$0.synced }
        guard !unsynced.isEmpty else { return }

        var pairs: [(user: String, reply: String)] = []
        var consumed: [ChatTurn] = []
        var i = 0
        while i < unsynced.count - 1 {
            let a = unsynced[i]
            let b = unsynced[i + 1]
            if a.role == "user" && b.role == "assistant" {
                pairs.append((user: a.text, reply: b.text))
                consumed.append(a)
                consumed.append(b)
                i += 2
            } else {
                i += 1
            }
        }
        guard !pairs.isEmpty else { return }

        do {
            let syncedCount = try await lan.syncTurns(pairs)
            for turn in consumed { turn.synced = true }
            print("[Pandia] synced \(syncedCount) away-mode turn(s) into Selene's memory.")
        } catch {
            // Will retry on next reconnect — same as sync.js's catch block.
            print("[Pandia] sync failed, will retry on next reconnect — \(error.localizedDescription)")
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        isSending = true

        // Stage 6: assume unsynced until we know what actually answered —
        // corrected right below once `reply` comes back, since a
        // LAN-answered turn (Selene lived through it) never needs syncing.
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
            // "lan"/"local" both mean Selene answered directly — she was
            // there for it, so it's already part of her memory and never
            // needs folding back in. Anything else (on-device or cloud)
            // starts unsynced. See syncPendingTurnsIfNeeded above.
            let livedThroughIt = reply.source == "lan" || reply.source == "local"
            userTurn.synced = livedThroughIt
            let assistantTurn = ChatTurn(role: "assistant", text: reply.text, source: reply.source, localError: reply.localError, synced: livedThroughIt)
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
                .background(turn.role == "user" ? Color.seleneGold.opacity(0.22) : Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            if let source = turn.source {
                Text(sourceLabel(source))
                    .font(.caption2)
                    .foregroundStyle(sourceColor(source))
            }
            // Rides along even on a turn where something else (cloud)
            // still answered — see ChatTurn.localError's doc comment.
            // Without this, a local-mode failure is invisible whenever
            // the fallback succeeds, which is exactly backwards for
            // actually testing the on-device model.
            if let localError = turn.localError {
                Text("on-device model failed: \(localError)")
                    .font(.caption2)
                    .foregroundStyle(.seleneDangerRed)
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

    // Same state-color meanings Selene's own CSS uses (see Theme.swift's
    // doc comment): teal = her, lilac = local, orange = cloud, red = dead
    // end. Applying that here, not just the hex values, is the actual
    // point of matching her palette — not just "colors from the same
    // family" but "the same color still means the same thing."
    private func sourceColor(_ source: String) -> Color {
        switch source {
        case "lan", "local": return .seleneTeal
        case "device": return .seleneLilac
        case "error": return .seleneDangerRed
        default: return .seleneOrange
        }
    }
}
