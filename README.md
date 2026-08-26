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

**Stage 2 — built, not yet installed/tested on a device:** a real Socket.IO
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
first.

**Stage 3 — built, not yet installed/tested on a device:** away-mode cloud
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
a look first if Stage 3 specifically fails to build where Stage 2 didn't.

**Next, once Stages 2 and 3 are both confirmed against a device:** a real
chat UI + SwiftData history tying LAN/cloud together with the same
local-first-then-cloud fallback shape as `../PWA/js/brain.js`'s
`awayModeReply`, then the on-device local model via MLX Swift — that last one gets its own
stage specifically because its exact package/API surface is even less
certain than Socket.IO's and is easiest to debug in isolation against an
otherwise-working app.
