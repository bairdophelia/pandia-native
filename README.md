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

**Status banner bug fix (2026-08-28):** with "Local only — don't fall
back to cloud" turned on in Settings, the away-mode banner at the top of
the chat screen still read "Away — using cloud fallback" — misleading,
and the exact opposite of what would actually happen on Send.
`PandiaBrain.reply`'s precedence (LAN → on-device → cloud) was always
correct — `localOnlyMode` genuinely skips cloud and surfaces the real
on-device error instead (see `PandiaBrain.swift`'s own comment on that
branch). The bug was purely cosmetic: `ContentView.swift`'s `statusLine`
picked its text from just `lan.isConnected`/`settings.lanHost`, never
looking at `settings.useLocalModel`/`settings.localOnlyMode` at all.
Fixed by giving it two more states so the banner actually matches what a
Send will do while away: "Away — on-device only" (local model on, cloud
fallback off), "Away — on-device, cloud fallback" (local model on, cloud
fallback still allowed), and the original "Away — using cloud fallback"
only when the on-device model is off entirely.

**Diagnostic logging added (2026-08-28):** while investigating the bug
below, added `print("[Pandia] ...")` lines through `send()`
(`ContentView.swift`), `PandiaBrain.reply` (its on-device branch
specifically), and `LocalBrain.session(for:)` — visible in Xcode's
console if this is ever run from a Mac with the phone attached. No
behavior change, just makes the next investigation faster than pulling
apart a screen recording frame by frame (see below).

**Chat history silently not saving with the on-device model on
(2026-08-28), diagnosed from a screen recording:** typing a message and
hitting Send showed the send button flip to an hourglass for about 300ms
and revert — the code was running and finishing — but NEITHER the user's
own message NOR any reply ever appeared in the chat, for several seconds
after. That's the important detail: `send()` inserts the user's
`ChatTurn` into SwiftData *before* any LAN/local-model/cloud call even
starts, so whatever's failing here can't be `PandiaBrain`'s reply logic —
it has to be something about SwiftData itself not persisting or
displaying that insert.

Best-supported explanation: Stage 6 added `ChatTurn.synced`, a new field,
on top of an on-device store that already had real chat history from
earlier Stage 4/5 testing. `.modelContainer(for: ChatTurn.self)`
(`PandiaApp.swift`) didn't crash, so container creation technically
succeeded — but SwiftData's automatic lightweight migration for a
schema change against a store with existing data is known to be less
reliable than it sounds, and a background autosave silently failing on
the old, now-mismatched rows can roll back the *entire* pending save —
new inserts included — without ever surfacing an error. That fingerprint
(runs fine, completes fine, nothing persists, no crash, no visible
error) matches exactly.

Two-part fix:
1. **For the store already wedged on-device:** delete and reinstall the
   app. That's the only thing that actually clears whatever's stuck in
   the current store — the code fix below only prevents this from
   happening again on the *next* schema change, it can't retroactively
   repair data already on disk.
2. **For every future schema change** (and there will be more — this is
   the second time `ChatTurn` has grown a field): `PandiaApp.swift` now
   builds its `ModelContainer` explicitly instead of using the
   convenience `.modelContainer(for:)` form, and if creation throws, it
   deletes the on-disk store (main file plus SQLite's `-wal`/`-shm`
   sidecars, which can otherwise resurrect the old mismatched data on
   next launch) and recreates it fresh rather than leaving something
   half-migrated in place. Early-stage local chat history isn't worth
   protecting at the cost of the app silently not working — turns worth
   keeping long-term reach Selene through Stage 6's own sync anyway.
   This makes container-creation *failures* self-healing; it doesn't
   (and structurally can't) catch a migration that "succeeds" but still
   leaves autosave broken the way this one did, which is why part 1
   above is still the actual fix for what's on your phone right now.

**Confirmed working (2026-08-28):** after a reinstall to clear the wedged
store, both bubbles now appear and persist correctly — the fix above was
right. Next thing that showed up, from an actual on-device reply: flat,
generic "I'm an artificial intelligence model..." text, nothing like
Selene's voice. Root cause was much simpler than the storage bug —
`LocalBrain.swift`'s `ChatSession` was created with no persona at all.
`CloudBrain.swift` passes `pandiaSystemPrompt` (`PersonalityPrompt.swift`)
as the system message for both cloud providers; the on-device path just
never had an equivalent. Fixed via `ChatSession`'s own `instructions:`
parameter — confirmed against `mlx-swift-lm`'s actual `ChatSession.swift`
source rather than guessed, documented there as "optional system
instructions for the session," exactly this use.

Worth knowing: `pandiaSystemPrompt` was written with a full-size cloud
model in mind; a tiny on-device model (the default is a 1B-parameter
Llama) is much less likely to follow it faithfully — expect a rougher
approximation of the voice on-device than from Anthropic/Groq. Feeding it
the same instructions anyway is still the right default (same call the
PWA's `brain.js` already made: "same personality as Selene for now") — a
weaker imitation beats no persona at all, and it's an easy thing to
revisit with a shorter, on-device-specific prompt later if the full one
proves too much for a 1B model to hold onto.

**On-device model upgraded, and made switchable in Settings
(2026-08-28):** Fia's ask, right after confirming the personality fix
above actually worked on a 1B model — a natural next question once it's
clearly working at all. Default bumped from Llama-3.2-1B-Instruct-4bit to
**Llama-3.2-3B-Instruct-4bit** (`Settings.swift`) — deliberately the same
architecture family, not a jump to a different one. Reasoning: this
stage's whole history (see the four CI rounds above) is evidence that
getting mlx-swift-lm to load a NEW model *family* correctly is real,
nontrivial work — LLMModelFactory has to explicitly support the
architecture. Staying within Llama 3.2 means the 3B is essentially
guaranteed to load the same way the 1B already does, confirmed working
end-to-end on-device today; only the parameter count (and therefore
quality, speed, and the ~1.8GB vs. ~0.7GB download) changes.

`SettingsView.swift` also gained an actual picker for this — until now
`localModelId` was a real, persisted, per-user setting in
`Settings.swift`, but the UI only ever showed it as read-only `Text`;
changing it meant editing code. Now: a picker with the 1B and 3B options
plus "Custom…", which reveals a plain text field for any other
`mlx-community` Hugging Face repo id. Deliberately didn't pre-populate
Custom with a curated list of newer/bigger options (Qwen3.5, Gemma 4,
etc. all exist on `mlx-community` as of this writing) — those are
different architectures from the one this project has actually gotten
working, so trying one is a real experiment with a real chance of
hitting a new round of the same compatibility issues Stage 5 went
through, not a safe default to hand someone via a picker label. Custom
is there for that experiment when wanted, opted into deliberately.
Switching models (including via Custom) downloads that model's weights
on first use after switching, same as the very first on-device use did —
worth doing on WiFi, same reasoning, now called out in the section's
footer text too.
