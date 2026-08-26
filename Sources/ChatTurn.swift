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
    var timestamp: Date

    init(role: String, text: String, source: String? = nil, timestamp: Date = Date()) {
        self.role = role
        self.text = text
        self.source = source
        self.timestamp = timestamp
    }
}
