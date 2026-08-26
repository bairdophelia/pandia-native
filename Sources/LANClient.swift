import Foundation
import SocketIO

// Native counterpart to the PWA's js/lan_client.js — "home mode": Pandia's
// connection to Selene's own Socket.IO server over the LAN, gated by
// SELENE_LAN_TOKEN (see Selene's app.py on_connect handler).
//
// socket.io-client-swift has no working, documented way to set the
// Socket.IO protocol-level `auth` handshake payload — the equivalent of the
// PWA's `io(url, {auth: {token}})` — as of this writing (see that library's
// open GitHub issues #1350 and #1381). So this sends the token as a
// `connectParams` query-string param instead, which the library DOES
// support. Selene's ../../app.py on_connect handler was updated (2026-08-24)
// to accept the token from either channel — same check either way, just a
// second valid path for it to arrive on — so this isn't working around
// Selene's back, it's a deliberate, matched pair of changes.
//
// LEAST CERTAIN FILE IN THIS STAGE: the exact SocketIOClientOption case
// names below (.connectParams, .reconnects, .forceNew) and the
// .on(clientEvent:) handler shape are based on the library's own README
// example plus its GitHub issue history, not a compile I could verify
// myself (no Xcode/macOS in this environment — see ../README.md). If the
// first CI build fails inside this file specifically, that's expected as
// the most likely spot, not a sign something upstream is wrong.
enum LANClientError: Error, LocalizedError {
    case notConnected
    case droppedMidReply
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to Selene (home mode)."
        case .droppedMidReply: return "Connection to Selene dropped before she finished replying."
        case .timedOut: return "Selene didn't reply in time."
        }
    }
}

@MainActor
final class LANClient: ObservableObject {
    @Published private(set) var isConnected = false
    /// Set from Selene's own `brain_source` event (see app.py's
    /// _process_message) — "local" or the cloud provider Selene herself
    /// used that turn. nil until the first reply arrives.
    @Published private(set) var lastBrainSource: String?

    private var manager: SocketManager?
    private var socket: SocketIOClient?

    // Stage 4 chat send/receive state — mirrors lan_client.js's onReply
    // buffering in app.js's wireLanEvents: speak_sentence events arrive as
    // Selene talks, sentence by sentence; response_done is the "she's
    // finished" signal. There's exactly one reply in flight at a time
    // (the UI disables Send while waiting), so a single buffer/continuation
    // pair is enough — no need for a queue.
    private var replyBuffer = ""
    private var replyContinuation: CheckedContinuation<String, Error>?
    private static let replyTimeout: TimeInterval = 30

    // Stage 6 sync state — a separate continuation from replyContinuation
    // on purpose. A sync call and a chat send never race in practice (the
    // UI only kicks off a sync right after connecting, before any message
    // is sent), but sharing one continuation would be a landmine the day
    // that assumption changes, so each gets its own slot instead.
    private var syncContinuation: CheckedContinuation<Int, Error>?
    private static let syncTimeout: TimeInterval = 15

    private static let connectTimeout: TimeInterval = 2.5

    /// Attempts a home-mode connection. Never throws — callers treat this
    /// as a plain yes/no, mirroring lan_client.js's tryConnect contract.
    func tryConnect(host: String, token: String) async -> Bool {
        guard !host.isEmpty else { return false }

        // Defensive, same reasoning as lan_client.js: a host with no
        // explicit port is valid syntax but silently tries port 80 (nothing
        // listening there) instead of erroring loudly — default to
        // Selene's Flask-SocketIO port if none was given.
        let hasPort = host.range(of: #":\d+$"#, options: .regularExpression) != nil
        let hostWithPort = hasPort ? host : "\(host):5000"
        guard let url = URL(string: "http://\(hostWithPort)") else { return false }

        disconnect() // tear down any previous attempt first, no dangling sockets

        let manager = SocketManager(socketURL: url, config: [
            .connectParams(["token": token]),
            .reconnects(false), // this app owns retry cadence, not the library's own backoff
            .forceNew(true),
        ])
        self.manager = manager
        let socket = manager.defaultSocket
        self.socket = socket

        return await withCheckedContinuation { continuation in
            var settled = false
            let finish: (Bool) -> Void = { [weak self] ok in
                guard !settled else { return }
                settled = true
                if !ok {
                    socket.removeAllHandlers()
                    socket.disconnect()
                    self?.socket = nil
                    self?.manager = nil
                }
                continuation.resume(returning: ok)
            }

            socket.on(clientEvent: .connect) { [weak self] _, _ in
                self?.isConnected = true
                finish(true)
            }
            socket.on(clientEvent: .error) { _, _ in finish(false) }
            socket.on(clientEvent: .disconnect) { [weak self] _, _ in
                // A disconnect AFTER we already resolved true is a real
                // "lost home mode" event, same distinction lan_client.js
                // makes. Stage 4: if a reply was in flight, fail it instead
                // of leaving the caller hanging — PandiaBrain.swift falls
                // back to cloud on this exact error, mirroring app.js's
                // sendText catch block.
                self?.isConnected = false
                self?.failPendingReply(with: .droppedMidReply)
                self?.failPendingSync(with: .droppedMidReply)
            }

            // Stage 4 chat events — see lan_client.js's _wireSocket for the
            // PWA equivalent. Selene streams her reply sentence-by-sentence
            // via speak_sentence (same events her own browser UI gets) and
            // signals completion with response_done; brain_source tells us
            // which brain actually answered (local vs cloud) so the UI can
            // show that instead of just "Home".
            socket.on("speak_sentence") { [weak self] data, _ in
                guard let self, let dict = data.first as? [String: Any],
                      let sentence = dict["text"] as? String else { return }
                self.replyBuffer += self.replyBuffer.isEmpty ? sentence : " \(sentence)"
            }
            socket.on("response_done") { [weak self] _, _ in
                guard let self else { return }
                let text = self.replyBuffer
                self.replyBuffer = ""
                self.replyContinuation?.resume(returning: text)
                self.replyContinuation = nil
            }
            socket.on("brain_source") { [weak self] data, _ in
                guard let self, let dict = data.first as? [String: Any],
                      let source = dict["source"] as? String else { return }
                self.lastBrainSource = source
            }

            // Stage 6 — ack for syncTurns below. See app.py's
            // on_pandia_sync_turns handler for the {"synced": Int} shape.
            socket.on("pandia_sync_ack") { [weak self] data, _ in
                guard let self, let dict = data.first as? [String: Any],
                      let synced = dict["synced"] as? Int else { return }
                self.syncContinuation?.resume(returning: synced)
                self.syncContinuation = nil
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectTimeout) {
                finish(false)
            }

            socket.connect()
        }
    }

    /// Sends one message and awaits Selene's full reply, reassembled from
    /// her speak_sentence stream (see socket wiring above) — the native
    /// equivalent of app.js's sendText home-mode branch, just collapsed
    /// into a single async call instead of a live-updating bubble, since
    /// Stage 4 doesn't yet stream partial text into the UI (that's a
    /// reasonable later polish pass, not a functional gap).
    func send(_ text: String) async throws -> String {
        guard let socket, isConnected else { throw LANClientError.notConnected }
        replyBuffer = ""
        return try await withCheckedThrowingContinuation { continuation in
            self.replyContinuation = continuation
            socket.emit("user_message", ["text": text])
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.replyTimeout) { [weak self] in
                self?.failPendingReply(with: .timedOut)
            }
        }
    }

    /// Folds away-mode turns into Selene's permanent memory — the native
    /// equivalent of lan_client.js's syncTurns, called by
    /// ContentView.syncPendingTurnsIfNeeded once home mode reconnects. Pass
    /// already-paired (user, reply) turns; pairing/filtering happens on the
    /// caller side, same split the PWA keeps between sync.js (pairing) and
    /// lan_client.js (transport). Selene's own handler decides what's
    /// worth remembering long-term — this just hands her the raw turns.
    func syncTurns(_ turns: [(user: String, reply: String)]) async throws -> Int {
        guard let socket, isConnected else { throw LANClientError.notConnected }
        guard !turns.isEmpty else { return 0 }
        let payload = turns.map { ["user": $0.user, "reply": $0.reply] }
        return try await withCheckedThrowingContinuation { continuation in
            self.syncContinuation = continuation
            socket.emit("pandia_sync_turns", ["turns": payload])
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.syncTimeout) { [weak self] in
                self?.failPendingSync(with: .timedOut)
            }
        }
    }

    private func failPendingReply(with error: LANClientError) {
        guard let continuation = replyContinuation else { return }
        replyContinuation = nil
        replyBuffer = ""
        continuation.resume(throwing: error)
    }

    private func failPendingSync(with error: LANClientError) {
        guard let continuation = syncContinuation else { return }
        syncContinuation = nil
        continuation.resume(throwing: error)
    }

    func disconnect() {
        failPendingReply(with: .notConnected)
        failPendingSync(with: .notConnected)
        socket?.removeAllHandlers()
        socket?.disconnect()
        socket = nil
        manager = nil
        isConnected = false
    }
}
