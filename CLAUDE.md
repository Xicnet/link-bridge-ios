# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

iOS app that bridges Ableton Link to browser clients over WebSocket.
Generic — not tied to any specific web app.

- `SPEC.md` — Full protocol specification (message types, fields, behavior)
- `PLAN.md` — Incremental build plan (6 steps, each independently buildable)

## Build

This project builds via GitHub Actions on macOS runners. There is no local macOS machine.
The .ipa is exported unsigned and sideloaded onto iPad via Sideloader on Linux.

**Do not assume local builds are possible.** Every change gets tested via CI.

Build command used in CI:
```
xcodebuild -project LinkBridge.xcodeproj \
  -scheme LinkBridge \
  -sdk iphoneos \
  -configuration Release \
  -archivePath build/LinkBridge.xcarchive \
  archive \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_ALLOWED=NO
```

## Constraints

- Swift, targeting iOS 16+
- Use `Network.framework` (`NWListener` + `NWProtocolWebSocket`) for the WebSocket server — no external dependencies
- LinkKit from https://github.com/Ableton/LinkKit for Ableton Link (added in Step 4, not before)
- Keep it minimal — no SwiftUI previews, no unit test target initially
- Each commit should build independently on GitHub Actions
- Prefer fewer files over many small ones

## Architecture

The app is a WebSocket server (port 20809) that bridges Ableton Link state to browser clients via JSON messages. Key components per SPEC.md §8.6:

- **AppDelegate** — App lifecycle, audio session for background execution
- **BridgeService** — Core orchestrator: connects Link + WebSocket, runs state broadcast timer (20Hz)
- **LinkManager** — Wraps LinkKit/ABLLink C API (tempo, beat, phase, transport, peer count)
- **WebSocketServer** — NWListener-based server, tracks connected clients, sends/receives JSON

The bridge sends `hello` on connect, periodic `state` at 20Hz, and event messages (`tempo`, `playing`, `peers`, `relay`). Clients send commands (`set-tempo`, `play`, `stop`, `relay`, `loop-beat`, etc.). All messages are JSON with a `type` field. See SPEC.md for full protocol.

## Implementation Progress

Follow PLAN.md steps in order. Each step is one commit. Check PLAN.md to see which steps are done before starting work.

- Step 1 — Empty iOS app + CI: **done** (commit pending push + CI verification)
