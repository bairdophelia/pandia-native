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
@MainActor
final class LANClient: ObservableObject {
    @Published private(set) var isConnected = false

    private var manager: SocketManager?
    private var socket: SocketIOClient?

    private static let connectTimeout: TimeInterval = 2.5

    /// Attempts a home-mode connection. Never throws — callers treat this
    /// as a plain yes/no, mirroring lan_client.js's tryConnect contract.
    func tryConnect(host: String, token: String) async -> Bool {
        guard !host.isEmpty else { return false }

        // Defensive, same reasoning as lan_client.js: a host with no
        // explicit port is valid syntax but silently tries port 80 (nothing
        // listening there) instead of erroring loudly — default to
        // Selene's Flask-SocketIO port if none was given.
        let hasPort = host.range(of: #":\d+$#", options: .regularExpression) != nil
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
                // makes — nothing to do with it yet in this stage beyond
                // flipping the published flag; chat streaming (speak_
                // sentence/response_done/brain_source) wires in once
                // there's a chat UI to feed it, see ../README.md.
                self?.isConnected = false
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectTimeout) {
                finish(false)
            }

            socket.connect()
        }
    }

    func disconnect() {
        socket?.removeAllHandlers()
        socket?.disconnect()
        socket = nil
        manager = nil
        isConnected = false
    }
}
