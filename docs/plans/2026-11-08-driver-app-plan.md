# langlight: BSP driver, application, macOS integration, tests

Status: proposed (2026-11-08). Nothing in this plan has been executed yet.

## Assumptions to confirm
- **"MACOS hooks"** means launchd and system events: a LaunchAgent at login, plus reactions to wake from sleep, screen unlock and Bluetooth reconnect. It doesn't mean Claude Code hooks.
- **Caps Lock on Hebrew** gives yellow, because rule C only covers English. Caps Lock only changes the color on an English layout.
- **Red (D)** covers any of these cases: the input source is unrecognized, the input-source query fails, or the BLE link or write fails. If BLE is down, red can't show, so it's applied as soon as the link comes back.

## Color rules
| Case | Color | Hex |
|---|---|---|
| A. Hebrew | Yellow | `FFFF00` |
| B. English | Magenta | `FF00FF` |
| C. English + Caps Lock | Blue | `0000FF` |
| D. Other / unknown / failure | Red | `FF0000` |

Hex values are overridable by flag.

## Target layout (SwiftPM, so tests are possible)
```
langlight/
  Package.swift
  Sources/RazerBLE/      BSP library
    Frame.swift          encode/decode: header, 20-byte chunking, response reassembly, status codes
    Transport.swift      protocol Transport (write, notify stream, connection events), so tests can fake it
    CoreBluetoothTransport.swift
    RazerDevice.swift    public API (below)
  Sources/langlight/     app
    Policy.swift         pure function: (source, capsLock, health) -> Color A/B/C/D
    InputSourceMonitor.swift, CapsLockMonitor.swift, SystemEvents.swift
    main.swift           CLI: set | get | raw | watch | install | uninstall
  Tests/RazerBLETests, Tests/langlightTests
  scripts/build.sh (builds, embeds Info.plist for the Bluetooth permission, codesigns), scripts/install.sh
  launchd/local.langlight.plist
  docs/protocol.md (the content of razer-langlight.md)
  docs/plans/
  README.md, .gitignore (watch.log, build outputs)
```

## Stage 1: git init (me, about 2 minutes)
1. Run `git init`. Add `.gitignore` for `watch.log` (18 MB), `.build/` and `_CodeSignature/`.
2. Make a baseline commit of the current working `langlight.swift`, `Info.plist` and the notes, before any refactor. That gives us a rollback point.

## Stage 2: finish the BSP, then commit
**Prep (me):** check that `swift build` works here and find out how the current binary was built and signed (Info.plist embedding). If SwiftPM doesn't work, fall back to `build.sh` with `swiftc`.

**Public API of `RazerDevice`:**
- `connect()` / `disconnect()`, with auto-reconnect on the existing 5-second poll.
- `write(cmd, data) async throws -> Response`. It tracks the txid, has a timeout, and maps status codes (busy, failure, not supported, and so on).
- `read(cmd) async throws -> [UInt8]`, a getter wrapper that returns the payload.
- `raw(class, id, sub1, sub2, data)`, the current `raw` mode.
- `setStaticColor(r, g, b)` and `getEffect()`.
- `register(_ handler)` for events: connection up or down, and unsolicited notifications.
- A serial request queue replaces today's single `pendingRaw` slot, which silently drops a command sent while another is in flight.

**Agents:**
| Agent | Task | Notes |
|---|---|---|
| Me (main) | Write Frame, Transport and RazerDevice, and refactor out of the single file | Owns `Sources/RazerBLE` |
| `general-purpose` agent "getter-prober" | Run the getters `10 80/81/82/83/85` on the real keyboard with `LL_DEBUG=1`, change state with `set`, and document each reply layout in `docs/protocol.md` | Runs one at a time, since there's one BLE link and it commands real hardware. It only reads state. |
| `Explore` agent | Look through the Synapse logs (`~/Library/Application Support/Razer/RazerAppEngine/User Data/Logs`) for the frame command (`BLEProtocol30 ... write:`) | Read-only and optional. It only helps if a per-zone effect has been applied in Synapse. |

The getter-prober's results shape `getEffect()`. Anything that can't be decoded stays exposed as raw bytes, and the commit message says so.

Commit: "BSP: framing, request/response, read, raw, events".

## Stage 3: the application
- `Policy` is a pure function implementing the color rules above.
- Input source comes from the existing TIS notification, with Hebrew detected by language code or source ID.
- Caps Lock state comes from `IOHIDGetModifierLockState`, polled about 5 times a second. That needs no Input Monitoring permission, unlike an event tap.
- The app only writes when the target color changes, and re-applies it on reconnect.

Commit: "App: policy + monitors + watch".

## Stage 4: commit
Folded into stages 2 and 3, one commit each, with stage 1's baseline commit before them.

## Stage 5: macOS hooks and README
- LaunchAgent `local.langlight` at `~/Library/LaunchAgents`, with `RunAtLoad` and `KeepAlive`, logging to `~/Library/Logs/langlight.log`. `langlight install` and `uninstall` handle it.
- `NSWorkspace` hooks re-apply the color on wake from sleep, screen unlock and session activation, because the keyboard forgets its state when it sleeps.
- `README.md` covers requirements, build and sign, the Bluetooth permission prompt, install and uninstall, color table, CLI reference, troubleshooting (keyboard on another host, the 3-4 s fade, log locations) and a protocol summary.
- Agent: one `general-purpose` agent drafts the README and plist while I do the hooks. They touch different files.

Commit: "macOS integration + README".

## Stage 6: tests
- **Unit tests without hardware:** frame encode/decode golden bytes, chunking at 20 bytes, response reassembly, status mapping, `Policy` over every input combination (including Hebrew with Caps Lock), and `RazerDevice` against a fake `Transport` (timeout, busy, disconnect mid-request, queueing).
- **Manual hardware checklist** in the README for the BLE and launchd parts.
- Agent: a `general-purpose` agent writes `Tests/` against the finished API, then I run `swift test` and fix what fails.

Commit: "Tests".

## Risks
- The fade of about 3-4 s remains until the frame command is found. The app will work but switches slowly.
- Getter decoding depends on what the keyboard returns. The result might be partial.
- Rebuilding changes the binary's code signature, so macOS may ask for the Bluetooth permission again.
