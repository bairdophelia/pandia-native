import Foundation

// Stage 4: the piece that was missing before this stage — a single place
// that decides LAN vs cloud, the native counterpart to ../PWA/js/brain.js's
// awayModeReply plus app.js's sendText mode check combined into one call.
// Until this existed, LANClient and CloudBrain were two independent brains
// a test button called directly; this ties them together the same
// local(home)-first-then-cloud shape the PWA uses, with "home" (LAN) taking
// the place the PWA gives the on-device local model, since Stage 5's MLX
// model doesn't exist yet — see ../README.md's staged plan.
enum PandiaBrain {
    struct Reply {
        let text: String
        /// "lan", refined to whatever Selene's own brain_source event says
        /// once one arrives ("local" or her cloud provider) — or a
        /// CloudProvider rawValue when this device went straight to cloud,
        /// or "error" when neither path could answer at all.
        let source: String
    }

    static func reply(
        to text: String,
        history: [ChatMessage],
        lan: LANClient,
        settings: PandiaSettings,
        confirm: (@Sendable (CloudProvider) async -> Bool)?
    ) async -> Reply {
        // LANClient is @MainActor-isolated (see LANClient.swift), and this
        // function isn't — it's called from ContentView's MainActor context,
        // but the function body itself has no actor of its own, so reading
        // across into LANClient's properties needs an explicit hop either
        // way. Cheap: these are just property reads, not real async work.
        if await lan.isConnected {
            do {
                let replyText = try await lan.send(text)
                return Reply(text: replyText, source: await lan.lastBrainSource ?? "lan")
            } catch {
                // Falls through to cloud below — same recovery app.js's
                // sendText does when lan.sendMessage throws mid-send
                // (connection dropped between the status pill saying
                // "Home" and the message actually going out).
            }
        }

        do {
            let replyText = try await CloudBrain.complete(
                history: history + [ChatMessage(role: "user", text: text)],
                provider: settings.cloudProvider,
                apiKey: settings.cloudApiKey,
                requireConsent: settings.requireCloudConsent,
                confirm: confirm
            )
            return Reply(text: replyText, source: settings.cloudProvider.rawValue)
        } catch {
            let declined = (error as? CloudBrainError).map {
                if case .consentDeclined = $0 { return true }
                return false
            } ?? false
            let text = declined
                ? "Okay — didn't send that anywhere. Ask again if you change your mind, or reconnect to Selene at home."
                : "Couldn't answer that away from the PC: \(error.localizedDescription)"
            return Reply(text: text, source: "error")
        }
    }
}
