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
actor LocalBrain {
    static let shared = LocalBrain()

    private var session: ChatSession?
    private var loadedModelId: String?

    /// `modelId` is a Hugging Face repo id in mlx-community's MLX-converted
    /// format, e.g. "mlx-community/Llama-3.2-1B-Instruct-4bit" (Settings'
    /// default — see PandiaSettings.swift). First call downloads the
    /// model's weights to the device (a few hundred MB to ~1GB depending
    /// on which model, so worth doing on WiFi) and caches the session;
    /// later calls with the same modelId reuse it. Switching modelId
    /// mid-session drops the old one — no multi-model cache in this pass.
    private func session(for modelId: String) async throws -> ChatSession {
        if let session, loadedModelId == modelId {
            return session
        }
        print("[Pandia] LocalBrain: loading container for \(modelId) — first use downloads weights, can take a while")
        let container = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: .init(id: modelId)
        )
        print("[Pandia] LocalBrain: container loaded")
        let newSession = ChatSession(container)
        session = newSession
        loadedModelId = modelId
        return newSession
    }

    /// Single-shot reply — the local-model counterpart to CloudBrain
    /// .complete, called from PandiaBrain.swift between the LAN attempt
    /// and the cloud fallback, same order the PWA's awayModeReply tries
    /// local before cloud. History isn't threaded through explicitly yet;
    /// ChatSession keeps its own internal turn history per loaded session
    /// (reset only when modelId changes, see above) — good enough for a
    /// first pass, worth revisiting once this stage is confirmed working
    /// on a device.
    func reply(to text: String, modelId: String) async throws -> String {
        let activeSession = try await session(for: modelId)
        return try await activeSession.respond(to: text)
    }
}
