# P.A.N.D.I.A. (Native)

**P**ortable **A**ccess **N**ode: **D**aily **I**nteractive **A**ssistant — the
native iOS rebuild of Pandia, Selene's phone-side companion.

This lives at `C:\AI\pandia\native` — a separate, self-contained codebase
from the Progressive Web App, a sibling folder at `C:\AI\pandia\PWA`
(`index.html`, `js/`, `css/`), not a replacement (yet). The PWA stays put
and keeps working while this one gets built out — see `..\PWA\PANDIA.md`
for the full background on Pandia's relationship to Selene (`C:\AI\selene`)
and Nyx, the character both share.

## Why a native rebuild

The PWA's away-mode local model depends on WebGPU inside a home-screen web
app's WKWebView, which iOS does not currently expose (confirmed empirically
on iOS 26.6 — Safari's own WebGPU support does not reach an installed web
app). A native app sidesteps that entirely by talking to Metal directly
instead of through a browser engine.

## Stack

- **SwiftUI** for the interface.
- **MLX Swift** (`https://github.com/ml-explore/mlx-swift`) for on-device
  local-model inference — Apple's own on-device ML framework, added as a
  plain Swift Package Manager dependency, no extra native toolchain.
- **SwiftData** for local chat history (replaces the PWA's IndexedDB).
- A Socket.IO-compatible client for home-mode LAN chat with Selene, mirroring
  the PWA's `../PWA/js/lan_client.js`.
- Direct HTTPS calls to Anthropic (recommended) / Groq for away-mode cloud
  fallback, mirroring the PWA's `../PWA/js/brain.js` — same consent-gate
  behavior before any cloud call.

## Build & install — no Mac owned, $0 cost

1. GitHub Actions' hosted macOS runners compile an unsigned `.ipa` on every
   push to this repo (free and unmetered on a **public** repo — that's why
   this repo should stay public; nothing sensitive belongs in it, since API
   keys are entered into the app's own Settings on-device, never committed
   here).
2. AltServer + AltStore (free) on the Windows PC install and sign that
   `.ipa` onto the phone using a free Apple ID — no $99/year Developer
   Program needed.
3. The free Apple ID's signing certificate expires every 7 days; AltStore
   re-signs it automatically over Wi-Fi once the one-time USB bootstrap
   (installing AltStore itself onto the phone) is done.

## Status

**Stage 1 — confirmed working (2026-08-23):** the minimal build pipeline —
push → GitHub Actions builds an unsigned `.ipa` → AltServer signs it with a
free Apple ID and installs it — ran green on the first try. `.github/
workflows/build.yml` is driven by `project.yml` via XcodeGen (see that
file's comment for why nobody hand-edits an `.xcodeproj` here).

**Stage 2 — confirmed working on a real device (2026-08-26):** a real Socket.IO
LAN client (`Sources/LANClient.swift`), matching the PWA's
`../PWA/js/lan_client.js` — connects to Selene over WiFi, gated by the same
`SELENE_LAN_TOKEN`.
`ContentView.swift` now has a bare-bones settings form (PC address, LAN
token) and a Connect button so this stage is independently testable before
any chat UI exists. `Sources/LANClient.swift`'s own top comment flags it as
the file most likely to need a fix on the first real build — `socket.io-
client-swift`'s exact config API (`.connectParams`, `.reconnects`,
`.forceNew`, the `.on(clientEvent:)` handler shape) is based on that
library's README and GitHub issues, not a compile I could verify myself (no
Xcode/macOS in this environment). If CI fails, that file is where to look
first. It did fail once, exactly there: a raw string literal on line 43 had
its delimiters backwards (`#":\d+$#"` instead of `#":\d+$"#`) — an
`unterminated string literal` compile error, fixed by swapping the closing
delimiter. Confirmed on a real device afterward: the app connects to Selene
over WiFi and shows "Home — connected to Selene."

**Stage 3 — confirmed working on a real device (2026-08-26):** away-mode cloud
fallback (`Sources/CloudBrain.swift`, plain `URLSession` + `JSONSerialization`
— no third-party dependency, so meaningfully lower first-build risk than
Stage 2's Socket.IO library), the personality prompt ported verbatim
(`Sources/PersonalityPrompt.swift`, hand-copied from `../PWA/js/brain.js` —
no shared import across the Swift/JS boundary, same caveat that file's own
comment documents about staying in sync manually), and the same consent gate
the PWA enforces before any cloud call. `ContentView.swift` now has a "Test
cloud message" section (provider picker, API key field, consent toggle, a
message field, and a Send button) so this stage is independently testable
too, same pattern as Stage 2. The consent-alert bridging in `ContentView
.swift` (turning a SwiftUI alert's button tap into something `CloudBrain`
can `await`) is this stage's least-certain spot, concurrency-wise — worth
a look first if Stage 3 specifically fails to build where Stage 2 didn't. It
didn't — built clean and confirmed on a real device: sent "hii" through the
Test cloud message field and got back an in-character reply, "Hey, Fia.",
consent alert and all.

**Both LAN and cloud are now proven end-to-end on a real device — two of
the three brains (LAN, cloud, local) working, not just compiling.** Local
(MLX Swift, Stage 5 below) is the one still unproven.

**Stage 4 — built, not yet installed/tested on a device:** a real chat
screen (`ContentView.swift`, rewritten) with a persisted history
(`ChatTurn.swift`, SwiftData — replaces the PWA's IndexedDB) and, the actual
missing piece before now, `PandiaBrain.swift`: one function that decides
home vs. cloud per message, the native counterpart to `../PWA/js/brain.js`'s
`awayModeReply` + `app.js`'s mode check combined. Prefers LAN when
`lan.isConnected`, falls back to cloud (same consent gate) on any LAN
failure — including a message sent mid-connection-drop, same recovery
`app.js`'s `sendText` does. `LANClient.swift` gained a `send(_:) async throws
-> String` that reassembles Selene's `speak_sentence` stream into one reply
and resolves on `response_done` (mirroring `lan_client.js`'s `onReply`
buffering in `wireLanEvents`), plus a 30s timeout and a
`brain_source`-driven `lastBrainSource` so the chat bubble can show "Selene ·
home" vs. "cloud · Anthropic" instead of just "Home". LAN/cloud config moved
out of the chat screen into `SettingsView.swift` (gear icon), same split the
PWA has between its chat view and its own Settings panel. Least certain
spot: `LANClient.send`'s continuation/timeout interplay with a live
`disconnect` mid-reply — untested against a real dropped connection, only
reasoned through.

**Stage 4 — confirmed working on a real device (2026-08-26):** LAN and
cloud both proven live in the new chat screen, consent gate included.

**Stage 5 — built, not yet installed/tested on a device:** the on-device
local model, via [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm)
(`Sources/LocalBrain.swift`) — the actual reason this native rebuild
exists in the first place (see "Why a native rebuild" above). Tried
between LAN and cloud in `PandiaBrain.swift`, matching the PWA's own
precedence exactly (`brain.js`'s `awayModeReply`: local before cloud, once
you're not on LAN). Off by default in Settings — turning it on downloads
the model (mlx-community's `Llama-3.2-1B-Instruct-4bit`, ~0.5GB, chosen for
being small enough for a phone) the first time it's used.

**BY FAR the least certain file in this project so far.** Every other
stage's riskiest file was built by reading source that already existed in
this repo or the PWA. `LocalBrain.swift` is built from `mlx-swift-lm`'s own
docs, fetched via web search rather than read directly, because that
library split out of `mlx-swift-examples` recently (v3, with breaking
changes to how it handles tokenizers/downloading).

*Round 1* guessed `LLMModelFactory.shared.loadContainer(configuration:)` —
wrong, but usefully wrong: the compiler's own error named the real method,
`loadContainer(from:using:configuration:useLatest:progressHandler:)`,
which needs a `Downloader` and a `TokenizerLoader` to be passed in. *Round
2* (current) supplies those via the `#hubDownloader()` /
`#huggingFaceTokenizerLoader()` macros — mlx-swift-lm's own DocC page
(`Libraries/MLXLMCommon/Documentation.docc/using.md`, shipped in the
library's source, about as authoritative as a source gets without reading
the Swift itself) calls this out by name as "the simplest way" for this
major version. That needed three more packages (`MLXHuggingFace`,
`SwiftHuggingFace` → `HuggingFace`, `SwiftTransformers` → `Tokenizers` —
see `project.yml`) and three more imports, since the macros expand to code
that references those modules' types.

*Round 3* (current) hit a different kind of wall — not a wrong API, but a
process one: `Macro "MLXHuggingFaceMacros" from package "mlx-swift-lm" must
be enabled before it can be used`. SPM normally handles that with an
interactive "trust this macro plugin" dialog the first time a package uses
one; there's no Xcode GUI in CI to click through. Fixed in
`.github/workflows/build.yml` by adding `-skipMacroValidation` to the
`xcodebuild archive` call — the documented workaround for exactly this
(same fix people use for Xcode Cloud, which hits the identical wall for
the identical reason). Nothing in `LocalBrain.swift` itself changed for
this round.

*Round 4* (current): past the macro-trust wall, straight into a version
mismatch — `Missing package product 'Tokenizers'`. The `main`-branch docs
this stage was researched from describe a newer, not-yet-tagged shape of
`swift-transformers`; the actual published version SPM resolved (0.1.24,
picked to satisfy `project.yml`'s `from: 0.1.0` floor) has a different
`Package.swift` — its real product is named `Transformers` (capitalized,
singular), with `Tokenizers` as a target bundled inside it rather than a
product of its own. Fixed by pointing `project.yml`'s `SwiftTransformers`
dependency at `product: Transformers` instead — confirmed against that
exact tag's own `Package.swift`, not the `main` branch, this time.
`LocalBrain.swift`'s `import Tokenizers` didn't need to change: that
module is still reachable once the right product is linked in.

Round 4 built clean and installed — first real on-device test of this
stage. Surfaced a behavior gap, not a compile bug: with "Use on-device
model" on but not yet actually working, replies were quietly going to
cloud with no visible sign the local attempt even happened or why it
failed — `PandiaBrain.swift` swallowed that error on its way to the
fallback. Fixed by adding `PandiaSettings.localOnlyMode` (Settings toggle:
"Local only — don't fall back to cloud") to skip the cloud fallback
entirely and surface the real error instead, plus threading a
`localError` string through `PandiaBrain.Reply` → `ChatTurn` → the chat
bubble so a local failure is visible (in orange, under the reply) even
in normal mode, on whichever turn it actually happened, whether or not
cloud picked up the slack that turn.

Deliberately left out of this first pass, to keep the guessed surface
small: download-progress reporting (shows nothing but the normal "sending"
spinner while the model downloads) and response streaming (waits for the
whole reply like cloud does, no token-by-token). Both are reasonable
follow-ups once this compiles and runs at all.

**App icon added (2026-08-26):** the app had none before this — a real
gap, since Stage 1 through 5 all installed fine but showed as a blank/
default icon on the home screen. `Sources/Assets.xcassets/AppIcon
.appiconset` now holds a single 1024×1024 generated image (a gold crescent
moon with a couple of sparkle stars on a near-black background, matching
the `moon.stars.fill` motif used elsewhere and the Selene/Pandia moon
theming), wired in via `project.yml`'s `ASSETCATALOG_COMPILER_APPICON
_NAME`. Single-size icon is the modern minimum — iOS 17+ generates every
other size/scale from that one image, no need to hand-produce a set of
@1x/@2x/@3x variants.

**Icon v2 + style alignment with Selene (2026-08-26):** the v1 icon used
generic moon colors picked from memory, not Selene's actual palette, and
nothing else in the app referenced her visual identity at all. Fixed both,
reading Selene's real source rather than guessing:

- `../selene/static/v2/styles.css`'s `:root` block gave the exact palette:
  `--ink #02040a`, `--cyan-bright #4fc6bd` (her signature teal), `--gold
  #d9b768` (muted, not bright yellow), `--lilac #c9a8f5`, `--warn-orange
  #e0923c`, `--danger-red #e05a44`. Selene's CSS explicitly keeps a state
  palette where "the same color always means the same thing everywhere on
  screen" — worth carrying the *meanings* over, not just the hex values.
- `../selene/static/v2/js/sphere.js` confirmed Selene's literal visual
  identity: her 3D moon sits inside a faint teal icosahedral wireframe
  shell (`SHELL_TEAL = 0x4fc6bd`, "a touch of containment magic... teal to
  tie in" per its own comment), with lilac "wireframe walker" particles
  (`WALKER_COLOR`) traveling along it. That's specifically what "the real
  wireframe" refers to.

`Sources/Theme.swift` (new) now defines `Color.selene*` constants pulled
directly from that palette, with doc comments tying each one back to its
source and its *meaning* — teal for "connected to Selene," lilac for
local/on-device, orange for cloud, red for a dead end. `ContentView.swift`
and `SettingsView.swift` were updated to use these throughout (background,
tint, chat bubble colors, the per-reply source tag) in place of the
generic `.accentColor`/`.teal`/`.orange` they used before. The app icon
(`generate_icon.py`, regenerated) was rebuilt on the same palette and
gained a subtle teal wireframe-globe motif — an outer circle plus nested
latitude/longitude ellipses at low opacity — sitting behind the crescent
moon, echoing sphere.js's wireframe shell without literally copying
Selene's animated 3D scene (that's her signature, not Pandia's).

*CI caught a real compile bug in this round:* `.foregroundStyle(.seleneTeal)`
(and `.seleneDangerRed`) failed with `type 'ShapeStyle' has no member
'seleneTeal'`. Reason: `Color`'s own `.teal`/`.red`/etc. shorthand only
works in `.foregroundStyle`/`.tint` calls because Apple declares those
colors *twice* — once as plain `Color` statics, and again as `ShapeStyle`
statics constrained to `Self == Color` (`.foregroundStyle` infers its
argument type from a generic `ShapeStyle`, not from `Color` directly, so
a `Color`-only static isn't visible there). `Theme.swift`'s original pass
only added the first declaration. Fixed by adding the matching
`extension ShapeStyle where Self == Color { static var seleneTeal: Color ... }`
block, mirroring Apple's own pattern — a one-file fix, `ContentView.swift`/
`SettingsView.swift` needed no changes. (A third reported error, in
`SettingsView.swift`'s `Section` call, was a type-checker cascade from
this same root cause, not a separate bug — it cleared once this fixed.)

**Stage 6 — syncing away-mode turns back into Selene's memory
(2026-08-26):** closes a real gap flagged during testing: anything said to
Pandia while away (on-device model or cloud) previously stayed local to
the phone forever — Selene never found out it happened, unlike the PWA,
which already had this via `js/sync.js` + `js/lan_client.js`'s
`syncTurns`. Native now matches:

- `ChatTurn.swift` gained a `synced: Bool` field (default `false`).
  Turns Selene answered directly (`source == "lan"` or `"local"`) are
  created already synced — she lived through them, there's nothing to
  fold in. Turns from the on-device model or cloud start unsynced.
- `LANClient.swift` gained `syncTurns(_:) async throws -> Int`, emitting
  `pandia_sync_turns` with `{"turns": [{"user":, "reply":}, ...]}` and
  awaiting a `pandia_sync_ack` event carrying `{"synced": Int}` — the
  exact contract `../selene/app.py`'s `on_pandia_sync_turns` handler
  expects, confirmed by reading it directly. Uses its own
  `syncContinuation`, separate from chat's `replyContinuation`, so a sync
  call can never collide with an in-flight message send; both get failed
  on disconnect/timeout the same way.
- `ContentView.swift` gained `syncPendingTurnsIfNeeded()`, run right after
  every successful `attemptConnect()` — same trigger point the PWA uses.
  It pairs up consecutive unsynced `(user, assistant)` turns in order (a
  stray unpaired trailing turn — message sent, app closed before a reply
  came — is left unsynced on purpose, same as `sync.js`), hands the pairs
  to `LANClient.syncTurns`, and marks the consumed turns `synced = true`
  on success. A failed sync just logs and retries on the next reconnect.
- `send()` now sets `synced` on both the user and assistant turn based on
  which brain actually answered that turn, instead of always defaulting
  to `false`.

Selene's handler folds these in as history and, for turns worth
remembering, into long-term memory — without asking her brain to
re-answer, since these turns already have a reply.
