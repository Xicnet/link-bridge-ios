# Ableton Link WebSocket Bridge — Protocol Spec & iOS Port Plan

A bridge application that exposes an [Ableton Link](https://ableton.github.io/link/)
session to browser clients over WebSocket. This spec is implementation-agnostic —
any platform (desktop, iOS, Android) can implement a conforming bridge.

The reference implementation is the Electron/TypeScript bridge in this repository.

---

## 1. Overview

```
┌──────────────┐   UDP multicast   ┌──────────────┐   WebSocket (JSON)   ┌─────────┐
│ Ableton Live │ <──────────────>  │    Bridge     │ <──────────────────> │ Browser │
│ or any Link  │   (Link protocol) │              │    ws://host:20809   │ client  │
│ peer         │                   └──────────────┘                      └─────────┘
└──────────────┘                         │
                                         ├──> client 1
                                         ├──> client 2
                                         └──> client N
```

The bridge:
1. Joins the Ableton Link mesh as a peer (tempo, beat, phase, start/stop sync)
2. Runs a WebSocket server on port **20809**, binding to `0.0.0.0` (all interfaces)
3. Broadcasts Link state to all connected WebSocket clients at a configurable rate
4. Accepts commands from clients to control the Link session
5. Relays arbitrary messages between clients

---

## 2. Configuration

| Parameter    | Type   | Default | Description                              |
|-------------|--------|---------|------------------------------------------|
| `port`      | int    | 20809   | WebSocket server port                    |
| `defaultBpm`| float  | 120     | Initial tempo when no Link peers exist   |
| `quantum`   | int    | 4       | Musical quantum (beats per bar)          |
| `stateHz`   | int    | 20      | State broadcast frequency (times/second) |

---

## 3. Server → Client Messages

All messages are JSON objects with a `type` field.

### 3.1 `hello` — sent once on connection

Sent immediately when a client connects. Contains a full state snapshot.

```json
{
  "type": "hello",
  "tempo": 120.0,
  "isPlaying": false,
  "beat": 0.0,
  "phase": 1.23,
  "quantum": 4,
  "numPeers": 1,
  "numClients": 2,
  "nextBar0Delay": 345.67,
  "jmxBeat": 2.5
}
```

| Field           | Type    | Description                                              |
|----------------|---------|----------------------------------------------------------|
| `tempo`        | float   | Current tempo in BPM, rounded to 2 decimal places        |
| `isPlaying`    | boolean | Link transport state                                     |
| `beat`         | float   | Current beat position on the Link timeline               |
| `phase`        | float   | Position within the current bar (0 to quantum)           |
| `quantum`      | int     | Beats per bar                                            |
| `numPeers`     | int     | Number of Link peers (excluding self)                    |
| `numClients`   | int     | Number of connected WebSocket clients (including this one)|
| `nextBar0Delay`| float   | Milliseconds until the next bar boundary (beat 0 of bar) |
| `jmxBeat`      | float?  | Optional. Application-level loop beat from first active client that reported one (see `loop-beat` command) |

`numClients` includes the newly connected client.

`jmxBeat` is only present if at least one connected client has sent a `loop-beat` message.

### 3.2 `state` — periodic broadcast

Sent to all clients at `stateHz` frequency (default: every 50ms).

```json
{
  "type": "state",
  "tempo": 120.0,
  "isPlaying": true,
  "beat": 45.67,
  "phase": 1.67,
  "quantum": 4,
  "numPeers": 1,
  "numClients": 3,
  "nextBar0Delay": 345.67,
  "jmxBeat": 2.5,
  "ts": 1708531200000
}
```

Same fields as `hello`, plus:

| Field | Type | Description                               |
|-------|------|-------------------------------------------|
| `ts`  | int  | Server timestamp (Unix epoch milliseconds)|

### 3.3 `tempo` — tempo change event

Broadcast when tempo changes (either from a Link peer or a client command).

```json
{
  "type": "tempo",
  "tempo": 128.0,
  "beat": 12.34,
  "phase": 0.34,
  "quantum": 4
}
```

When triggered by a Link peer callback, `tempo` is rounded to 2 decimal places.

When triggered by a client `set-tempo` command, `tempo` is the raw value read
back from Link after setting (Link may quantize it).

### 3.4 `playing` — transport state change

Broadcast when Link start/stop state changes.

```json
{
  "type": "playing",
  "isPlaying": true
}
```

### 3.5 `peers` — Link peer count change

Broadcast when the number of Link peers changes.

```json
{
  "type": "peers",
  "numPeers": 2
}
```

### 3.6 `relay` — forwarded client message

Broadcast to all clients **except** the original sender.

```json
{
  "type": "relay",
  "payload": { ... }
}
```

`payload` is the arbitrary JSON object from the sending client, forwarded as-is.

---

## 4. Client → Server Messages

### 4.1 `set-tempo`

Set the Link session tempo.

```json
{ "type": "set-tempo", "tempo": 128.0 }
```

**Validation:** `tempo` must be a finite number > 0. Invalid values are silently ignored.

**Side effect:** Bridge reads back the tempo from Link after setting and broadcasts
a `tempo` message to all clients (see 3.3).

### 4.2 `play`

Start the Link transport.

```json
{ "type": "play" }
```

### 4.3 `stop`

Stop the Link transport.

```json
{ "type": "stop" }
```

### 4.4 `request-quantized-start`

Request playback to start aligned to a bar boundary (beat 0). Sets beat to 0 at
the start-playing time, then starts transport.

```json
{ "type": "request-quantized-start", "quantum": 4 }
```

| Field     | Type  | Required | Description                              |
|-----------|-------|----------|------------------------------------------|
| `quantum` | int   | No       | Override quantum for alignment (defaults to bridge config) |

### 4.5 `force-beat-at-time`

Force a specific beat value at a specific time. Used for manual phase correction.

```json
{ "type": "force-beat-at-time", "beat": 0, "time": 1708531200000, "quantum": 4 }
```

**Validation:** All three fields (`beat`, `time`, `quantum`) must be numbers.
Message is silently ignored if any field is missing or non-numeric.

### 4.6 `relay`

Send an arbitrary message to all other connected clients. The bridge does not
interpret the payload — it wraps it in a `relay` envelope and forwards it.

```json
{ "type": "relay", "payload": { "myKey": "myValue" } }
```

**Validation:** `payload` must be a non-null object. Invalid messages are silently ignored.

**Routing:** Sent to all clients except the sender.

### 4.7 `loop-beat`

Report the current application-level loop beat position. The bridge stores the
most recent value per client and includes it in `state` and `hello` broadcasts
as `jmxBeat`.

```json
{ "type": "loop-beat", "beat": 2.5 }
```

**Validation:** `beat` must be a number.

**Note:** When multiple clients send `loop-beat`, only the first connected client's
value (with an open connection) is used in broadcasts. This is intentional — it
represents the primary session's loop position.

---

## 5. Computed Fields

### `nextBar0Delay`

Milliseconds until the next bar-0 boundary on the Link timeline.

```
remainingBeats = quantum - phase
msPerBeat      = 60000 / tempo
nextBar0Delay  = remainingBeats * msPerBeat
```

This allows clients to schedule events aligned to bar boundaries without
needing direct Link access. A client can `setTimeout(callback, nextBar0Delay)`
to fire at the start of the next bar.

### `tempo` rounding

Tempo values from Link are rounded to 2 decimal places:
```
tempo = round(rawTempo * 100) / 100
```

---

## 6. Connection Lifecycle

1. Client opens WebSocket to `ws://bridge-host:20809`
2. Bridge adds client to its set, sends `hello` with full state snapshot
3. Bridge sends periodic `state` messages at `stateHz` rate
4. Bridge sends `tempo`, `playing`, `peers` events as they occur
5. Client may send commands at any time
6. On disconnect, bridge removes client and cleans up any `loop-beat` state

---

## 7. Error Handling

- Malformed JSON from a client is silently dropped (logged server-side)
- Messages that are not JSON objects are silently dropped
- Unknown message types are silently ignored
- Invalid field values on known message types are silently ignored
- No error messages are sent back to clients

This is intentional — the bridge is a real-time musical sync tool where latency
matters more than error reporting. Clients should validate their own messages
before sending.

---

## 8. iOS Implementation Notes

### 8.1 Link SDK

Use [LinkKit](https://github.com/Ableton/LinkKit) (official iOS SDK) or the
[open-source Link library](https://github.com/Ableton/link) (C++, GPLv2+).

LinkKit provides an Objective-C API (`ABLLink`) that maps directly to the
operations used in this spec:
- `ABLLinkSetActive()` — enable/disable Link
- `ABLLinkSetIsStartStopSyncEnabled()` — enable start/stop sync
- `ABLLinkGetSessionTempo()` — read tempo
- `ABLLinkSetSessionTempo()` — set tempo
- `ABLLinkGetBeatAtTime()` — get beat
- `ABLLinkGetPhaseAtTime()` — get phase
- `ABLLinkIsPlaying()` — transport state
- `ABLLinkSetIsPlaying()` — set transport state
- `ABLLinkRequestBeatAtStartPlayingTime()` — quantized start
- `ABLLinkForceBeatAtTime()` — force beat alignment

### 8.2 WebSocket Server

Use a Swift WebSocket server library. Options:
- **Swift NIO + WebSocketKit** — mature, event-driven, used by Vapor
- **Network.framework** (`NWListener` + `NWProtocolWebSocket`) — Apple-native, no dependencies
- **Starscream** — primarily a client library, not suitable for server

`Network.framework` is the simplest choice for an iOS-only app — no external
dependencies, built into iOS.

### 8.3 Background Execution

iOS suspends apps that are not in the foreground. The bridge needs to stay active.

**Strategy: Audio session background mode**

1. Enable `audio` background mode in `Info.plist`
2. Configure an `AVAudioSession` with category `.playback`
3. Play silence via an `AVAudioEngine` / `AVAudioPlayerNode` with a silent buffer
4. This keeps the app process alive and Link connected

This is how existing Link-enabled iOS apps (like Ableton Note) stay in sync
while backgrounded. It's within App Store guidelines for music apps.

**Alternative for sideloaded apps:** The `audio` background mode trick is still
the most reliable approach, but sideloaded apps don't need to worry about
App Store review.

### 8.4 Local Network

- iOS 14+ requires a **Local Network permission** prompt — add
  `NSLocalNetworkUsageDescription` to `Info.plist`
- Add a Bonjour service type for Link: `_apple-midi._udp` (Link uses mDNS)
- The WebSocket server binds to `0.0.0.0:20809` — Safari on the same device
  can connect to `ws://localhost:20809`, other devices use the device's LAN IP

### 8.5 Mixed Content / TLS

If browser clients load pages over `https://`, they cannot connect to `ws://`
(insecure WebSocket) due to mixed content restrictions.

Options:
- Load the web app over `http://` (works for local/LAN apps)
- Add TLS to the bridge with a self-signed cert (requires trusting it on each client)
- Use a `wss://` proxy or tunnel

For local development and LAN-only use, `http://` + `ws://` is simplest.

### 8.6 App Structure (Minimal)

```
LinkBridge/
├── LinkBridge.xcodeproj
├── LinkBridge/
│   ├── AppDelegate.swift         # App lifecycle, audio session
│   ├── BridgeService.swift       # Core logic: Link + WebSocket server
│   ├── LinkManager.swift         # Wraps LinkKit/ABLLink API
│   ├── WebSocketServer.swift     # NWListener-based WS server
│   ├── Info.plist                # Background modes, network permissions
│   └── Assets.xcassets
├── LinkKit/                      # Ableton LinkKit framework (or via SPM)
└── .github/
    └── workflows/
        └── build.yml             # GitHub Actions: build + export .ipa
```

### 8.7 Build via GitHub Actions

macOS runners have Xcode pre-installed. A minimal workflow:

```yaml
name: Build iOS
on: push
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: |
          xcodebuild -project LinkBridge.xcodeproj \
            -scheme LinkBridge \
            -sdk iphoneos \
            -configuration Release \
            -archivePath build/LinkBridge.xcarchive \
            archive \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_ALLOWED=NO
      - name: Export unsigned IPA
        run: |
          mkdir -p build/Payload
          cp -r build/LinkBridge.xcarchive/Products/Applications/LinkBridge.app build/Payload/
          cd build && zip -r LinkBridge-unsigned.ipa Payload
      - uses: actions/upload-artifact@v4
        with:
          name: LinkBridge-unsigned.ipa
          path: build/LinkBridge-unsigned.ipa
```

The `.ipa` is unsigned — sign it on your Linux machine with Sideloader using
your free Apple ID before installing on the device.

**Free tier budget:** ~300 macOS minutes/month (10x multiplier). A build takes
~5 min, so ~60 builds/month. Public repos get unlimited minutes.

---

## 9. Implementation Checklist

### Phase 1 — Scaffold & CI
- [ ] Create Xcode project with LinkKit dependency
- [ ] Configure audio background mode + local network permission
- [ ] GitHub Actions workflow: build unsigned .ipa artifact
- [ ] Verify sideloading the empty app onto iPad from Linux (Sideloader)

### Phase 2 — Link Integration
- [ ] Initialize ABLLink with default tempo
- [ ] Enable Link + start/stop sync
- [ ] Read beat, phase, tempo, isPlaying, numPeers
- [ ] Implement callbacks: tempo change, start/stop, peer count

### Phase 3 — WebSocket Server
- [ ] NWListener on port 20809, all interfaces
- [ ] Accept connections, track connected clients
- [ ] Send `hello` on connect with full state
- [ ] Periodic `state` broadcast at configured Hz
- [ ] Parse incoming JSON, dispatch by `type`

### Phase 4 — Client Commands
- [ ] `set-tempo` — validate, set on Link, broadcast `tempo`
- [ ] `play` / `stop` — set on Link
- [ ] `request-quantized-start` — requestBeatAtStartPlayingTime + play
- [ ] `force-beat-at-time` — validate all 3 fields
- [ ] `relay` — forward to all except sender
- [ ] `loop-beat` — store per-client, include in broadcasts

### Phase 5 — Background & Polish
- [ ] Silent audio playback for background execution
- [ ] Minimal UI showing connection status (peers, clients, tempo)
- [ ] Reconnection-friendly: clients should handle dropped connections

---

## 10. Reference: Message Type Summary

### Server → Client

| Type      | When                        | Key Fields                                  |
|-----------|-----------------------------|---------------------------------------------|
| `hello`   | On connect (once)           | Full state + `numClients` + optional `jmxBeat` |
| `state`   | Every 1/stateHz seconds     | Full state + `ts` + optional `jmxBeat`      |
| `tempo`   | Tempo changes               | `tempo`, `beat`, `phase`, `quantum`         |
| `playing` | Transport state changes     | `isPlaying`                                 |
| `peers`   | Link peer count changes     | `numPeers`                                  |
| `relay`   | Client sent a relay message | `payload` (arbitrary object)                |

### Client → Server

| Type                      | Effect                                     | Required Fields          |
|---------------------------|--------------------------------------------|--------------------------|
| `set-tempo`               | Change Link tempo                          | `tempo` (float > 0)      |
| `play`                    | Start transport                            | (none)                   |
| `stop`                    | Stop transport                             | (none)                   |
| `request-quantized-start` | Start aligned to bar boundary              | optional `quantum`       |
| `force-beat-at-time`      | Force beat alignment                       | `beat`, `time`, `quantum`|
| `relay`                   | Forward to other clients                   | `payload` (object)       |
| `loop-beat`               | Report loop position                       | `beat` (float)           |
