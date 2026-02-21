# CLAUDE.md

## Project

iOS app that bridges Ableton Link to browser clients over WebSocket.
Generic — not tied to any specific web app.

- `SPEC.md` — Full protocol specification (message types, fields, behavior)
- `PLAN.md` — Incremental build plan (6 steps, each independently buildable)

## Build

This project builds via GitHub Actions on macOS runners. There is no local macOS machine.
The .ipa is exported unsigned and sideloaded onto iPad via Sideloader on Linux.

**Do not assume local builds are possible.** Every change gets tested via CI.

## Constraints

- Swift, targeting iOS 16+
- Use `Network.framework` (`NWListener` + `NWProtocolWebSocket`) for the WebSocket server — no external dependencies
- LinkKit from https://github.com/Ableton/LinkKit for Ableton Link (added in Step 4, not before)
- Keep it minimal — no SwiftUI previews, no unit test target initially
- Each commit should build independently on GitHub Actions
- Prefer fewer files over many small ones
