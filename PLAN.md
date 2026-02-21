# LinkBridge iOS — Incremental Build Plan

Each step is a single commit that should build and (where possible) run.
The goal is to never have more than one new thing that could break.

## Prerequisites

- GitHub repo (public for free unlimited macOS CI minutes)
- Apple ID (you have one)
- Sideloader installed on Linux (`libimobiledevice` + GTK 4 frontend)
- iPad connected via USB (at least for first sideload)

---

## Step 1 — Empty iOS app + CI

**Goal:** Prove the GitHub Actions → unsigned .ipa → sideload pipeline works.

**What to build:**
- Xcode project: single-view app, deployment target iOS 16+
- One `ContentView.swift` that shows "LinkBridge" label
- `Info.plist` with bundle ID (e.g. `com.yourname.linkbridge`)
- GitHub Actions workflow: `xcodebuild archive` → unsigned `.ipa` artifact

**What to test:**
- GH Actions builds green
- Download `.ipa` artifact
- Sign with Sideloader on Linux, install on iPad
- App launches, shows the label

**Why this step matters:**
Validates the entire toolchain before any real code. If sideloading fails,
you fix it here — not after writing 500 lines of Swift.

---

## Step 2 — WebSocket server (no Link yet)

**Goal:** A working WebSocket server on the iPad that a browser can connect to.

**What to build:**
- `WebSocketServer.swift` using `Network.framework` (`NWListener` + `NWProtocolWebSocket`)
- Listen on port 20809, accept connections
- On connect: send `{"type":"hello","tempo":120,"isPlaying":false,"beat":0,"phase":0,"quantum":4,"numPeers":0,"numClients":1,"nextBar0Delay":0}`
- Track connected clients count
- UI: show "Listening on ws://<ip>:20809" and client count
- `Info.plist`: add `NSLocalNetworkUsageDescription`

**What to test:**
- Install on iPad
- Open browser on any device on the same Wi-Fi
- Connect via browser devtools: `new WebSocket('ws://<ipad-ip>:20809')`
- Receive the `hello` message
- Client count updates in the app UI

**What to skip:**
- No Link, no periodic broadcast, no incoming commands yet
- Tempo/beat/phase are hardcoded zeros

---

## Step 3 — Periodic state broadcast + incoming commands

**Goal:** The WebSocket server behaves like the real bridge (minus Link).

**What to build:**
- Timer-based `state` broadcast at 20Hz with hardcoded/simulated values
- JSON parsing of incoming messages
- Handle `set-tempo`: update internal tempo variable, broadcast `tempo` message
- Handle `play`/`stop`: toggle internal `isPlaying`, broadcast `playing` message
- Handle `relay`: forward payload to other clients
- Handle `loop-beat`: store per-client, include `jmxBeat` in broadcasts
- UI: show current tempo, playing state

**What to test:**
- Connect browser, see `state` messages arriving ~20/s
- Send `{"type":"set-tempo","tempo":140}` — see tempo change in broadcasts
- Send `{"type":"play"}` — see `isPlaying` flip to true
- Connect two browser tabs, test `relay` between them
- This is testable with the same browser you use for Joymixa

**What to skip:**
- No Link integration — all values are local/simulated
- No `request-quantized-start` or `force-beat-at-time` (need Link for those)

**Why this step matters:**
At this point you have a fully functional WebSocket bridge with the complete
protocol — just no actual Link sync. You can test Joymixa against it.
If Joymixa works with the simulated bridge, the protocol is correct.

---

## Step 4 — Add LinkKit

**Goal:** Real Ableton Link integration.

**What to build:**
- Add LinkKit framework to the Xcode project (download from GitHub releases)
- `LinkManager.swift` wrapping ABLLink C API:
  - `init(bpm:)` → `ABLLinkNew(bpm)`
  - `enable()` → `ABLLinkSetActive(true)`
  - `getTempo()`, `getBeat()`, `getPhase(quantum:)`, `isPlaying()`
  - `setTempo()`, `setIsPlaying()`, `requestBeatAtStartPlayingTime()`, `forceBeatAtTime()`
  - `getNumPeers()`
- Replace hardcoded values in BridgeService with LinkManager calls
- Register Link callbacks: tempo, start/stop, peer count
- UI: show Link peer count

**What to test:**
- Run Ableton Live (or another Link app) on the same network
- Peer count should appear in the app
- Change tempo in Live → bridge broadcasts the new tempo
- Send `set-tempo` from browser → Live shows the new tempo
- Play/stop syncs between Live and browser

**What could go wrong:**
- LinkKit framework not found at build time → check framework search paths
- ABLLink C API bridging header issues → may need a module.modulemap
- Callbacks not firing → check Link is enabled + start/stop sync enabled

---

## Step 5 — Background audio + polish

**Goal:** App stays alive when backgrounded.

**What to build:**
- `Info.plist`: add `UIBackgroundModes` → `audio`
- Configure `AVAudioSession` with `.playback` category
- `AVAudioEngine` playing a silent buffer on loop
- Start silent audio when bridge starts
- Minimal status UI: peers, clients, tempo, IP address, on/off toggle

**What to test:**
- Start bridge, connect browser, switch to another app on iPad
- WebSocket connection stays alive
- Link sync continues
- Come back to app — everything still running

**What could go wrong:**
- iOS still suspends the app → check audio session category and route
- Audio interruption (phone call, other audio app) → handle interruption notifications

---

## Step 6 (optional) — Extras

Only if everything above works:

- `request-quantized-start` and `force-beat-at-time` commands
- Reconnection handling (client drops and reconnects)
- mDNS/Bonjour advertisement so clients can discover the bridge
- Settings UI (port, quantum, broadcast rate)

---

## Working with Claude in the new repo

Yes — run Claude from `/home/rama/dev/joymixa-bridge-ios/`. For each step:

```
1. Ask Claude to implement step N
2. Push to GitHub
3. Wait for GH Actions build
4. If build fails → paste the error, ask Claude to fix
5. If build passes → download .ipa, sideload, test on iPad
6. If works → move to step N+1
```

Create a `CLAUDE.md` in the new repo so Claude has context:

```markdown
# CLAUDE.md

## Project
iOS app that bridges Ableton Link to WebSocket clients.
See SPEC.md for the full protocol specification.
See PLAN.md for the incremental build plan.

## Build
This project builds via GitHub Actions (no local macOS).
The .ipa is unsigned — sideloaded onto iPad via Sideloader on Linux.

## Constraints
- Swift, targeting iOS 16+
- Use Network.framework for WebSocket server (no external dependencies except LinkKit)
- LinkKit: https://github.com/Ableton/LinkKit (Ableton's iOS SDK for Link)
- Keep it minimal — no SwiftUI previews, no unit test target initially
- Each commit should build independently
```

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Sideloading pipeline doesn't work | Low | Step 1 tests this before any real code |
| LinkKit build issues in CI | Medium | Step 4 is isolated — WS server already works without it |
| iOS kills background WebSocket | Medium | Step 5's silent audio trick is proven by other Link apps |
| Network.framework WS server tricky | Medium | Step 2 is isolated — just the server, nothing else |
| Mixed content blocks `ws://` from `https://` page | Known | Test with Joymixa on iPad directly, not cross-device |
| 7-day sideload expiry annoying | Certain | SideStore auto-refreshes, or just re-sign weekly |
