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

**3B default reverted, personality prompt split by model size
(2026-09-01), from real device testing once the AltServer install issue
above got resolved:**

- **3B crashed.** Not a hang, not a slow download — an actual crash,
  consistent with memory pressure: ~1.8GB of weights alone, before MLX's
  own runtime overhead and per-turn KV cache, is enough to get an app
  killed by iOS on some phones. An OS memory kill isn't a thrown Swift
  error — there's nothing to catch or recover from in code, which means
  the fix has to be about what gets defaulted to, not about handling the
  failure more gracefully. `Settings.swift`'s `defaultLocalModelId`
  reverted to 1B; 3B stays selectable in `SettingsView.swift`'s picker
  (relabeled to say plainly that it may crash on some phones, no longer
  called "recommended") for anyone on higher-RAM hardware who wants to
  opt in deliberately, but it's no longer what a fresh install gets
  without asking.
- **1B still came back generic**, even with the personality fix from
  2026-08-28 correctly wired up (confirmed — the `instructions:`
  parameter genuinely reaches the model). Root cause: `pandiaSystemPrompt`
  is nine dense sections — tone, address rules, register examples,
  signature lines, speech rules, honesty, autonomy, standby, away-mode —
  written for a full-size cloud model. A 1B model doesn't reliably hold
  onto or prioritize that much at once; asking it to was the actual bug,
  not the wiring. Added `pandiaLocalSystemPrompt`
  (`PersonalityPrompt.swift`) — a short, direct version keeping only the
  handful of rules that matter most for a brief phone exchange (identity,
  brevity, address rules, the forbidden-phrases list, away-mode context)
  — and pointed `LocalBrain.swift` at that instead. `CloudBrain.swift`
  is untouched and still uses the full prompt; cloud models are exactly
  what it was written for.

**3B crash re-examined, timeout added around model load (2026-09-01),
same test session, from a more detailed play-by-play:** the "almost
certainly memory pressure" line in the entry above was called out as
overconfident, fairly — the iPhone 17 Pro has 12GB of RAM, not the ~8GB
this project had assumed, which undercuts a simple "not enough total RAM"
explanation. The actual sequence Fia described: said hi to 3B, waited
~30s with the hourglass still up, switched the Settings picker to 1B
mid-flight (which does nothing to the in-flight request — `send()`
captures the model id at the moment Send is tapped, and there's no
cancellation path in this code, so the original 3B load just kept
running in the background), then force-quit the app. A second 3B attempt
afterward ran for a couple of minutes and then closed with no error
dialog at all. That fingerprint — silent close, no error, after an
interrupted first download — points more at a corrupted or half-written
cached model file left behind by the force-quit than at the device
running out of memory outright. Not confirmed (no way to pull a crash log
off the phone without a Mac/Xcode), just the better-supported theory of
the two.

Either way, the actual fixable gap is the one flagged back in Stage 5's
own doc comment: no download-progress reporting, so a slow-but-working
load and a genuinely stuck one look identical — just an indefinite
hourglass with no way to abandon it short of force-quitting. Fixed with a
240-second timeout around `LLMModelFactory.shared.loadContainer(...)` in
`LocalBrain.swift`, using `withThrowingTaskGroup` to race the real load
against a `Task.sleep` + throw and cancelling whichever one loses. A
load that's genuinely just slow (big model, slow WiFi) still has four
minutes to finish; a hung or corrupted one now fails with an actual,
catchable `LocalBrainError.timedOut` instead of spinning forever — which
flows through `PandiaBrain`'s existing `localOnlyMode`/`localError`
handling exactly like any other local-model failure, so it's visible in
the chat bubble instead of just a stuck hourglass.

This does not by itself clear a corrupted cache if that's what's actually
going on — there's no "clear the model cache" button in the app yet, so
if 3B still fails (now with a visible timeout error rather than a silent
crash), the next thing to try is a full delete-and-reinstall to force a
completely fresh download, the same recovery Stage 6's SwiftData bug
needed for the same underlying reason: some code fixes can only prevent a
problem going forward, not repair a store or a cache that's already bad
on disk.

**Real download progress added (2026-09-01), Fia's direct ask right
after hitting the exact gap this file's own notes had flagged since
Stage 5:** waiting on an on-device model download showed nothing but the
normal hourglass, with no way to tell "downloading normally, on a slow
connection" apart from "hung." `LLMModelFactory.shared.loadContainer`
already takes a `progressHandler: @Sendable @escaping (Progress) ->
Void` — present in the API since Stage 5, just never wired up (see that
stage's "deliberately minimal" list above).

`LocalBrain.swift` now has a small `LocalBrainProgress` (`ObservableObject`,
`@Published var fractionCompleted: Double?`) that the progress handler
feeds. Deliberately kept boring on the concurrency side: rather than
making the bridge `@MainActor` and reasoning through whether a
`@Sendable` closure fired from inside `loadContainer`'s own internals is
allowed to hop into a global actor, it's a plain class with
`DispatchQueue.main.async` inside otherwise ordinary methods — the same
pre-structured-concurrency pattern that's been safe for bridging
arbitrary-thread callbacks into SwiftUI for years. This file already
carries more guessed API surface than anywhere else in the project; this
addition tries to add zero *additional* uncertainty on top of that,
rather than also gambling on actor-isolation subtleties.

`ContentView.swift` observes `LocalBrainProgress.shared` directly and
renders a `ProgressView` + percentage right above the input bar whenever
a load's in flight — invisible the rest of the time (LAN and cloud sends
never touch it, so the normal chat flow is unchanged). One wrinkle
called out in `LocalBrain.swift`'s own comment: `fractionCompleted`
tracks bytes downloaded, not "ready to chat" — it sits at/near 1.0 for a
real stretch afterward while MLX loads the weights into memory, so the
UI swaps to a distinct "Loading model into memory…" message once it
crosses ~99.9%, rather than leaving a bar that looks stuck at 100%.

**Full personality prompt made an opt-in toggle (2026-09-01), Fia's ask
right after confirming 3B answers well on-device with the condensed
prompt:** now that a real progress bar means a load reads as "in
progress" instead of "stuck," worth trying the same full
`pandiaSystemPrompt` cloud gets, deliberately, on a model big enough to
maybe hold it. Added `PandiaSettings.useFullPersonalityPrompt` (off by
default — the condensed prompt is still what's confirmed working on 1B)
and a matching toggle in `SettingsView.swift`'s on-device section, footer
updated to say plainly it's worth trying on 3B+, not recommended on 1B.

`LocalBrain.swift` needed a small restructure to support this without
forcing an unnecessary reload: it now caches the `ModelContainer` and the
`ChatSession` separately, keyed on `(modelId, useFullPrompt)`. A modelId
change still does the full network-aware load with the progress bar and
timeout; a prompt-choice change alone (same modelId) reuses the
already-loaded container and just builds a fresh `ChatSession` from it —
cheap, instant, no network, no progress bar needed for that part. Without
this split, flipping the toggle would have re-triggered the entire
loadContainer path (and its download check) just to change which string
gets passed as `instructions:`.

**Selene's own desktop side, not Pandia:** while testing, Fia hit Selene
(`../selene`) answering "who are you" as "a virtual assistant developed
by Alibaba Cloud" — Nyx's character dropping entirely. Traced to a
documented Qwen-specific quirk (Selene's local model is `qwen3:8b` via
Ollama, `SELENE_LOCAL_FIRST` on by default): Qwen models have their real
identity trained in hard enough that direct meta-questions can override a
custom system-prompt persona, confirmed against a matching report on
Ollama's own GitHub (`ollama/ollama#6873`) and the Qwen3 chat-template
writeup. Not a Pandia bug and not a wiring bug in Selene either —
`selene_local.py` genuinely sends the full system prompt every call, read
directly to confirm. Fixed with an explicit IDENTITY paragraph added to
`selene_personality.py`'s `_CHARACTER_PART_A` (so it flows into every
variant — cloud included, harmlessly, since cloud was never affected)
that directly forbids naming the underlying model. Noted here rather than
skipped since Pandia's own prompt is a hand-copy of the same character
text — worth knowing this block exists if Pandia's local models ever move
off the Llama family and hit the same symptom.

**Sent-bubble color, gold → teal (2026-09-02), Fia's ask:** `ContentView
.swift`'s `ChatBubble` now backs the user's own messages with
`Color.seleneTeal.opacity(0.22)` instead of gold — same treatment, same
opacity, just the other color, so the quiet/muted feel carries over.
Teal otherwise means "Selene/home" specifically everywhere else in the
app (the status line, the "Selene · home" source tag right under this
same bubble) — a deliberate ask, not a bug, just noted since it's the
one spot that breaks Theme.swift's one-color-one-meaning rule.

**"Selene/home" meaning moved off teal onto moon-white (2026-09-02),
Fia's direct follow-up to the change above:** "make selene/home more of
a silver or a white? that way it more references the fact that I'm
talking to the moon when I'm home." Rather than inventing a silver,
checked Selene's own `styles.css` first (same sourcing rule this whole
file follows) and found `--full-moon-white: #f3efe4` already exists
there for exactly this purpose — it's literally the color her wireframe
shell (and `--cyan-bright`, the teal this project already pulled)
switches to during an actual full moon
(`body.full-moon{ --cyan-bright:var(--full-moon-white); }`). Added as
`Color.seleneMoonWhite` in `Theme.swift` and swapped in everywhere the
"connected to Selene / home" meaning lived: `ContentView.swift`'s status
line and `sourceColor`'s "lan"/"local" case, and `SettingsView.swift`'s
"Connected to Selene" label. Also resolves the note left in the entry
right above this one — teal is now cleanly just "the app's general
accent + the user's own bubble," no longer double-booked with a
state meaning, so the one-color-one-meaning rule holds again.
`seleneTeal`'s general app-tint uses (`ContentView`/`SettingsView`'s
`.tint(.seleneTeal)`) were left alone — Fia's ask was specifically about
the Selene/home indicator, not the whole app's accent color.

**Selene/Pandia parity check (2026-09-02), Fia's ask after the Qwen
identity fix landed on the Selene side:** rather than eyeballing it, ran
an actual `diff` between `selene_personality.py`'s
`_CHARACTER_PART_A + _HONESTY_NO_TOOLS + _CHARACTER_PART_B` (the exact
pieces this file's own docstring says get hand-copied) and this
project's `pandiaSystemPrompt` with its Pandia-specific "PANDIA AWAY
MODE" ending stripped off first. Result: byte-for-byte identical except
for one gap — the IDENTITY paragraph added to Selene earlier that same
day hadn't been copied over yet. Fixed in `PersonalityPrompt.swift`:
the full paragraph added to `pandiaSystemPrompt` verbatim, and a
one-line condensed version added to `pandiaLocalSystemPrompt` (which
was never a 1:1 hand-copy of anything Selene-side to begin with, so
there was no drift there, just the same precaution worth having).
Re-ran the diff after the fix — clean. Pandia's own on-device models
are Llama-family, not Qwen, so this isn't patching an observed bug the
way it was on Selene, but `SettingsView.swift`'s Custom model option
means a user could point on-device inference at a Qwen (or similarly
identity-stubborn) model without this paragraph existing to guard
against it — worth having regardless of what ships as the default.

**Known remaining gap, not fixed (out of scope for this pass):** the
PWA's `../PWA/js/brain.js`'s `PANDIA_SYSTEM_PROMPT` — the actual
original source this file's own `pandiaSystemPrompt` was hand-copied
from — also doesn't have the IDENTITY paragraph. Left alone since this
pass was scoped to Selene/native-Pandia parity specifically and the PWA
hasn't been touched otherwise this session; flag if the PWA still needs
to stay in sync too.
