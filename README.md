# P.A.N.D.I.A. (Native)

**P**ortable **A**ccess **N**ode: **D**aily **I**nteractive **A**ssistant — the
native iOS rebuild of Pandia, Selene's phone-side companion.

This lives at `C:\AI\pandia\native` — a separate, self-contained codebase
from the Progressive Web App one level up (`C:\AI\pandia`'s `index.html`,
`js/`, `css/`), not a replacement (yet). The PWA stays put and keeps working
while this one gets built out — see `..\PANDIA.md` for the full background
on Pandia's relationship to Selene (`C:\AI\selene`) and Nyx, the character
both share.

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
  the PWA's `lan_client.js`.
- Direct HTTPS calls to Anthropic (recommended) / Groq for away-mode cloud
  fallback, mirroring the PWA's `brain.js` — same consent-gate behavior
  before any cloud call.

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

Stage 1: a deliberately minimal SwiftUI app (`Sources/`) plus the
GitHub Actions build (`.github/workflows/build.yml`, driven by
`project.yml` via XcodeGen — see that file's comment for why nobody hand-edits
an `.xcodeproj` here) whose only job is to prove the whole pipeline works:
push → GitHub's Mac hardware builds an unsigned `.ipa` → AltServer signs it
with your free Apple ID and installs it → the phone shows "Pandia — native
build pipeline online."

Once that's confirmed working end to end, the real features get layered in
on top of a known-good baseline, roughly in this order: home-mode LAN chat
to Selene (needs `../app.py`'s `on_connect` fix, already applied — see its
comment on why `socket.io-client-swift` needs the token as a query param,
not the protocol auth payload the PWA uses), away-mode cloud fallback
(Anthropic/Groq, mirroring `../js/brain.js`), then the on-device local model
via MLX Swift — that last one gets its own stage specifically because its
exact package/API surface is the least certain of everything here and is
easiest to debug in isolation against a working app rather than mixed in
with everything else failing at once.
