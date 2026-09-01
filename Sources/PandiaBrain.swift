import Foundation

// Stage 4 built the piece that was missing before it — a single place
// that decides LAN vs cloud, the native counterpart to ../PWA/js/brain.js's
// awayModeReply plus app.js's sendText mode check combined into one call.
// Stage 5 slots the on-device model (LocalBrain.swift) in between the two,
// matching the PWA's own precedence exactly: LAN (home) first, then the
// on-device local model, then cloud — see brain.js's awayModeReply, which
// is "local-then-cloud" for the same reason once you're not on LAN.
enum PandiaBrain {
    struct Reply {
        let text: String
        /// "lan" (refined to whatever Selene's own brain_source event says
        /// once one arrives — "local" or her cloud provider — note that's
        /// SELENE's local model, on the PC), "device" (this phone's own
        /// on-device model, see LocalBrain.swift — deliberately not
        /// "local" too, so the two can't collide), a CloudProvider
        /// rawValue when it went straight to cloud, or "error" when
        /// nothing could answer at all.
        let source: String
        /// Set only when the on-device model was tried and failed. If
        /// cloud then answered anyway, this rides along on that Reply so
        /// the failure isn't invisible just because something else picked
        /// up the slack — mirrors the PWA's brain.js `localError` field
        /// (see app.js's renderMessage). See PandiaSettings.localOnlyMode
        /// for forcing this to surface as the actual reply instead of
        /// being masked by a cloud fallback.
        var localError: String? = nil
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
                // Falls through to local/cloud below — same recovery
                // app.js's sendText does when lan.sendMessage throws
                // mid-send (connection dropped between the status pill
                // saying "Home" and the message actually going out).
            }
        }

        var localError: String?
        if settings.useLocalModel {
            print("[Pandia] trying on-device model \(settings.localModelId)…")
            do {
                let replyText = try await LocalBrain.shared.reply(
                    to: text,
                    modelId: settings.localModelId,
                    useFullPrompt: settings.useFullPersonalityPrompt
                )
                print("[Pandia] on-device model answered (\(replyText.count) chars)")
                return Reply(text: replyText, source: "device")
            } catch {
                print("[Pandia] on-device model threw: \(error)")
                // Normally falls through to cloud below — same recovery
                // brain.js's awayModeReply does when the on-device model
                // throws (not supported / failed to load / generation
                // error). See LocalBrain.swift's doc comment for why this
                // stage's error cases are broader and less certain than
                // LAN's or cloud's. localOnlyMode turns that fallback off:
                // the point of it is to see the on-device model's own
                // failures, not have cloud quietly paper over them.
                localError = error.localizedDescription
                if settings.localOnlyMode {
                    return Reply(
                        text: "On-device model didn't answer: \(localError!)",
                        source: "error",
                        localError: localError
                    )
                }
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
            return Reply(text: replyText, source: settings.cloudProvider.rawValue, localError: localError)
        } catch {
            let declined = (error as? CloudBrainError).map {
                if case .consentDeclined = $0 { return true }
                return false
            } ?? false
            let text = declined
                ? "Okay — didn't send that anywhere. Ask again if you change your mind, or reconnect to Selene at home."
                : "Couldn't answer that away from the PC: \(error.localizedDescription)"
            return Reply(text: text, source: "error", localError: localError)
        }
    }
}
