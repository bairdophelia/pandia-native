import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

// Stage 5: on-device inference via MLX Swift — the actual reason this
// native rebuild exists (see ../README.md's "Why a native rebuild": WebGPU
// never reached the PWA's installed home-screen WKWebView, confirmed
// empirically; this talks to the phone's GPU directly through Metal
// instead of through a browser engine, sidestepping that entirely).
//
// HIGHEST-UNCERTAINTY FILE IN THIS PROJECT so far — more so than
// LANClient.swift (Stage 2's actual build failure) or PandiaBrain's
// actor-isolation fix (Stage 4's). Those were built by reading this
// project's own working source. This one is built from mlx-swift-lm's
// own DocC documentation (Libraries/MLXLMCommon/Documentation.docc/
// using.md, shipped inside the library's own source tree — the most
// authoritative thing I could find without reading the .swift source
// directly), not a compile I could verify myself (no Xcode/macOS in this
// environment).
//
// ROUND 1 of this stage's CI run failed here: `loadContainer(configuration:)`
// doesn't exist — the compiler's own error printed the real signature,
// `loadContainer(from:using:configuration:useLatest:progressHandler:)`,
// which needed a `Downloader` and a `TokenizerLoader` I hadn't supplied.
// This round supplies them via the `#hubDownloader()` /
// `#huggingFaceTokenizerLoader()` macros, which that same DocC page
// explicitly calls out as "the simplest way" for anyone on this major
// version of the library — hence the three extra imports above
// (MLXHuggingFace defines the macros; HuggingFace/Tokenizers are what they
// expand to, so the calling file needs those types in scope too). If THIS
// specific pairing is also wrong, the compiler's error should again name
// the real signature directly — that's been reliable both times so far in
// this project (see native/README.md's Stage 2 and this stage's notes).
//
// Deliberately minimal otherwise, to keep the guessed API surface small:
//   - No download-progress reporting (progressHandler has a default and is
//     omitted here) — the UI just shows its normal "sending" spinner for
//     however long the download+load takes.
//   - No response streaming. ChatSession also exposes streamResponse(to:)
//     for token-by-token output; this uses the simpler respond(to:) that
//     returns the whole reply at once, matching CloudBrain.complete's
//     shape so PandiaBrain.swift can treat local and cloud identically.
// Both are reasonable follow-ups once this compiles and runs at all, not
// blockers for a first working version — same sequencing Stage 4 used
// (get LAN/cloud talking first, live-streaming chat bubbles later).
//
// Bug fix (2026-08-28): first real on-device reply came back as a flat
// "I'm an artificial intelligence model..." — correct behavior for this
// code, since ChatSession was created with no persona at all. CloudBrain
// .swift passes `pandiaSystemPrompt` as the system message for both cloud
// providers (PersonalityPrompt.swift); this file just never did the local
// equivalent. Fixed via ChatSession's own `instructions:` parameter —
// confirmed against mlx-swift-lm's actual ChatSession.swift source, not
// guessed — which is documented as "optional system instructions for the
// session," exactly this use.
//
// Follow-up (2026-09-01), from an actual device test: feeding the full
// `pandiaSystemPrompt` still came back generic on the 1B model. Not a
// regression of the fix above — the instructions genuinely reach the
// model — just confirmation of the risk this file already called out:
// the full prompt is nine dense sections built for a full-size cloud
// model, and a 1B model doesn't reliably hold onto or prioritize that
// much at once. Switched to `pandiaLocalSystemPrompt`
// (PersonalityPrompt.swift) — a short, direct version covering only the
// handful of rules that matter most for a brief phone exchange, sized
// for what a small model can actually apply consistently, rather than
// trusting a 1B model to self-prioritize among nine sections.
//
// Second follow-up (2026-09-01), same test session: switching the model
// picker to 1B in Settings while a 3B send was still in flight didn't
// unstick anything — the hourglass stayed up until the ORIGINAL request
// finished or the app was force-quit. That's not a bug so much as a real
// gap this file already called out above ("no download-progress
// reporting... the UI just shows its normal 'sending' spinner for
// however long the download+load takes") actually being hit: `send()`
// captures the model id at the moment Send is tapped and has no
// cancellation path, so there was never going to be a way to abandon a
// slow load short of force-quitting. Force-quitting mid-download is
// itself the likely cause of what happened next — a SECOND 3B attempt
// that ran for a couple of minutes and then closed with no error message
// at all, which is much more consistent with trying to load a half-
// written file left behind by the interrupted first download than with
// the 12GB-RAM iPhone actually running out of memory.
//
// Real fix, scoped to what's actually fixable without a device console:
// a timeout around the load. It doesn't erase the "stuck with no
// progress bar" gap (still a real follow-up worth doing), but it turns
// "wait indefinitely, then force-quit" into "fails after a bounded time
// with an actual, catchable error" — which flows through PandiaBrain's
// existing localOnlyMode/localError handling exactly like any other
// local-model failure. A corrupted partial download, specifically,
// still needs a full reinstall to clear (see ../README.md) — nothing in
// this app has a "clear the model cache" button yet.
//
// Progress bar added (2026-09-01), closing that "stuck with no progress
// bar" gap: `loadContainer` takes a `progressHandler: @Sendable @escaping
// (Progress) -> Void` — confirmed against mlx-swift-lm's own docs, which
// show it called with a plain Foundation `Progress` and read via
// `progress.fractionCompleted`. That closure can fire from any thread,
// and SwiftUI needs `@Published` writes on the main thread, so
// `LocalBrainProgress` below bridges the two the plain, pre-structured-
// concurrency-safe way — a `DispatchQueue.main.async` inside otherwise
// ordinary nonisolated methods — rather than making the bridge itself
// `@MainActor` and reasoning through whether a `@Sendable` closure is
// allowed to hop into a global actor from inside `loadContainer`'s own
// (unknown) calling context. Deliberately the more boring option: this
// file's whole history is a reminder that the guessed API surface here
// is already the risk worth minimizing, not a place to also gamble on
// actor-isolation subtleties.
//
// Worth knowing: `fractionCompleted` tracks bytes downloaded over total
// bytes, not "ready to chat" — it sits at (or near) 1.0 for a real
// stretch after the download itself finishes while MLX loads the
// weights into memory. `ContentView.swift`'s progress UI shows a
// separate "loading into memory" message once fraction crosses ~0.999
// specifically so that stretch doesn't read as a stuck 100% bar.
final class LocalBrainProgress: ObservableObject {
    static let shared = LocalBrainProgress()
    private init() {}

    /// nil = no on-device load in flight. 0...1 while one is — see the
    /// doc comment above for why this can sit near 1.0 for a while
    /// before the model's actually usable.
    @Published private(set) var fractionCompleted: Double?

    /// Called from `loadContainer`'s progress closure, which is not
    /// guaranteed to run on the main thread — hence the manual hop
    /// instead of relying on `@Published`'s own thread-safety (it has
    /// none; that's Combine's/SwiftUI's job on the *reading* side, not
    /// a guarantee on the writing side).
    func began() {
        DispatchQueue.main.async { self.fractionCompleted = 0 }
    }
    func update(_ fraction: Double) {
        // Progress can briefly report a non-finite fraction (e.g. NaN)
        // if totalUnitCount hasn't been set yet at the very start — a
        // guarded 0 beats a SwiftUI ProgressView choking on NaN.
        let safeFraction = fraction.isFinite ? fraction : 0
        DispatchQueue.main.async { self.fractionCompleted = safeFraction }
    }
    func finished() {
        DispatchQueue.main.async { self.fractionCompleted = nil }
    }
}

actor LocalBrain {
    static let shared = LocalBrain()

    // container is cached separately from session (2026-09-01, added
    // alongside the full-prompt toggle in Settings/SettingsView): the
    // instructions passed to ChatSession can't be changed after creation,
    // but rebuilding a ChatSession from a container already sitting in
    // memory is instant — no network, no progress bar, no timeout risk.
    // Keeping the two separate means flipping "use full personality
    // prompt" only rebuilds the cheap part.
    private var container: ModelContainer?
    private var session: ChatSession?
    private var loadedModelId: String?
    private var loadedUsesFullPrompt: Bool?

    /// Generous on purpose — a multi-GB model on a slow connection is a
    /// real case, not just a hang, and failing too eagerly would turn a
    /// legitimately-slow-but-working download into a false failure. Long
    /// enough to cover that; short enough that a truly stuck load (or,
    /// per the doc comment above, a corrupted cached file) fails with a
    /// real error instead of leaving the UI stuck until a force-quit.
    private static let loadTimeout: TimeInterval = 240

    private enum LocalBrainError: Error, LocalizedError {
        case timedOut
        var errorDescription: String? {
            "On-device model took too long to load (over \(Int(loadTimeout / 60)) minutes) — check your connection, or it may need a fresh install to clear a corrupted download."
        }
    }

    /// `modelId` is a Hugging Face repo id in mlx-community's MLX-converted
    /// format, e.g. "mlx-community/Llama-3.2-1B-Instruct-4bit" (Settings'
    /// default — see PandiaSettings.swift). First call downloads the
    /// model's weights to the device (a few hundred MB to ~1GB depending
    /// on which model, so worth doing on WiFi) and caches both the
    /// container and the session; later calls with the same modelId AND
    /// the same prompt choice reuse the session outright. A modelId
    /// change forces a real reload (different weights); a prompt-choice
    /// change alone reuses the cached container and just builds a fresh
    /// ChatSession from it — see the container/session split above.
    /// Switching modelId mid-session drops the old container — no
    /// multi-model cache in this pass.
    private func session(for modelId: String, useFullPrompt: Bool) async throws -> ChatSession {
        if let session, loadedModelId == modelId, loadedUsesFullPrompt == useFullPrompt {
            return session
        }

        let activeContainer: ModelContainer
        if let container, loadedModelId == modelId {
            activeContainer = container
        } else {
            print("[Pandia] LocalBrain: loading container for \(modelId) — first use downloads weights, can take a while")
            LocalBrainProgress.shared.began()
            do {
                activeContainer = try await withThrowingTaskGroup(of: ModelContainer.self) { group in
                    group.addTask {
                        try await LLMModelFactory.shared.loadContainer(
                            from: #hubDownloader(),
                            using: #huggingFaceTokenizerLoader(),
                            configuration: .init(id: modelId),
                            progressHandler: { progress in
                                LocalBrainProgress.shared.update(progress.fractionCompleted)
                            }
                        )
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(Self.loadTimeout * 1_000_000_000))
                        throw LocalBrainError.timedOut
                    }
                    // First to finish wins — success or the timeout's throw — and
                    // the loser gets cancelled rather than left running in the
                    // background wasting bandwidth/battery on a load nothing's
                    // waiting on anymore.
                    defer { group.cancelAll() }
                    guard let result = try await group.next() else {
                        throw LocalBrainError.timedOut
                    }
                    return result
                }
                LocalBrainProgress.shared.finished()
                print("[Pandia] LocalBrain: container loaded")
                container = activeContainer
            } catch {
                // Reset on every exit path — timeout, a real load failure, or
                // task cancellation — so a failed load doesn't leave the bar
                // stuck at whatever percentage it last reported.
                LocalBrainProgress.shared.finished()
                throw error
            }
        }

        let instructions = useFullPrompt ? pandiaSystemPrompt : pandiaLocalSystemPrompt
        let newSession = ChatSession(activeContainer, instructions: instructions)
        session = newSession
        loadedModelId = modelId
        loadedUsesFullPrompt = useFullPrompt
        return newSession
    }

    /// Single-shot reply — the local-model counterpart to CloudBrain
    /// .complete, called from PandiaBrain.swift between the LAN attempt
    /// and the cloud fallback, same order the PWA's awayModeReply tries
    /// local before cloud. History isn't threaded through explicitly yet;
    /// ChatSession keeps its own internal turn history per loaded session
    /// (reset when modelId OR the prompt choice changes, see above) —
    /// good enough for a first pass, worth revisiting once this stage is
    /// confirmed working on a device.
    func reply(to text: String, modelId: String, useFullPrompt: Bool) async throws -> String {
        let activeSession = try await session(for: modelId, useFullPrompt: useFullPrompt)
        return try await activeSession.respond(to: text)
    }
}
