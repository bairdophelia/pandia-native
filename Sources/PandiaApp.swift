import SwiftUI
import SwiftData

@main
struct PandiaApp: App {
    // Bug fix (2026-08-28): `.modelContainer(for: ChatTurn.self)` (Stage 4)
    // hands SwiftUI the plain, non-throwing convenience form, which force-
    // creates the container and crashes if that fails. It DIDN'T crash when
    // this bug was reported, so container creation itself was "succeeding"
    // — but a real-device test after Stage 6 added `ChatTurn.synced` (a new
    // field, on top of a store that already had Stage 4/5 chat history on
    // disk) showed something more specific and quieter than a crash: typing
    // a message and hitting Send never showed EITHER bubble (not even the
    // user's own message, which is inserted before any network/model call
    // even runs) — the send button still flipped to an hourglass and back,
    // so the code path was running and completing, just not persisting
    // anything. That fingerprint matches a background autosave silently
    // failing on the mismatched old rows and rolling back the whole
    // pending save (new inserts included) rather than surfacing an error —
    // SwiftData's automatic lightweight migration is known to be less
    // reliable than it sounds for schema changes made mid-development
    // against a store that already has real data in it, which is exactly
    // this project's situation every time ChatTurn gains a field.
    //
    // This explicit, throwing container setup doesn't fix a store that's
    // already wedged (that needs a real reinstall to clear — see README),
    // but it makes the NEXT schema change self-healing instead of
    // repeating this same silent failure: if the container can't be
    // created or migrated cleanly, wipe the on-disk store and start fresh
    // rather than leaving something half-migrated in place. Early-stage
    // local chat history isn't worth protecting at the cost of the app
    // silently not working — the away-mode turns worth keeping are the
    // ones that make it to Selene via Stage 6's sync anyway.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([ChatTurn.self])
        let configuration = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            print("[Pandia] ModelContainer failed (\(error)) — wiping the on-device chat store and starting fresh")
            wipeStore(at: configuration.url)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("[Pandia] ModelContainer still failed after wiping the store: \(error)")
            }
        }
    }

    /// SQLite (what SwiftData's default store is backed by) keeps two
    /// sidecar files alongside the main store — -wal (write-ahead log) and
    /// -shm (shared memory index) — that have to go too, or the old,
    /// mismatched data can resurrect itself from them on next launch.
    private static func wipeStore(at url: URL) {
        let dir = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        for suffix in ["", "-wal", "-shm"] {
            let sidecar = dir.appendingPathComponent(name + suffix)
            try? FileManager.default.removeItem(at: sidecar)
        }
    }

    private let container = makeContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
