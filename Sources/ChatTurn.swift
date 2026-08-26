import Foundation
import SwiftData

// Stage 4: persisted chat history, replacing the PWA's IndexedDB
// (../PWA/js/storage.js). One row per turn, user and assistant alike —
// `source` is nil for user turns and set for assistant turns to whichever
// brain actually answered: "lan" (Selene over WiFi, possibly refined by
// her own brain_source event — see LANClient.swift), or a CloudProvider
// rawValue ("anthropic"/"groq") for away mode, or "error" when nothing
// could answer at all. That mirrors the PWA's per-message `mode` field
// (see storage.js/app.js's renderMessage), used the same way there: to
// show a small source tag under each assistant bubble.
@Model
final class ChatTurn {
    var role: String // "user" | "assistant"
    var text: String
    var source: String?
    /// Set only when the on-device model was tried and failed for this
    /// turn, whether or not something else (cloud) answered anyway — see
    /// PandiaBrain.Reply.localError. Lets a local-mode failure stay
    /// visible in history even on a turn that otherwise looks like a
    /// normal successful cloud reply.
    var localError: String?
    var timestamp: Date
    /// Stage 6: has this turn been folded into Selene's own memory yet
    /// (see LANClient.syncTurns / ContentView.syncPendingTurnsIfNeeded)?
    /// Mirrors the PWA's storage.js row flag of the same name. A turn
    /// answered directly by Selene (source "lan"/"local") is created
    /// already synced — she lived through it, there's nothing to fold in.
    /// A turn answered on-device or by cloud starts false and gets synced
    /// the next time home mode is reachable.
    var synced: Bool

    init(role: String, text: String, source: String? = nil, localError: String? = nil, synced: Bool = false, timestamp: Date = Date()) {
        self.role = role
        self.text = text
        self.source = source
        self.localError = localError
        self.synced = synced
        self.timestamp = timestamp
    }
}
