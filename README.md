# langlight

Colors a Razer PT Ergo (Bluetooth LE) keyboard by the active macOS input language.

| Case | Color |
|---|---|
| Hebrew | Green `00FF00` |
| English | Magenta `FF0080` |
| English + Caps Lock | Blue `0000FF` |
| Other / unknown / failure | Red `FF0000` |

Hebrew with Caps Lock stays green. Red is also used when the input-source query fails; if Bluetooth is down it is applied when the link returns.

## Requirements
- macOS 13+, Xcode command-line tools (Swift 5.9+).
- The keyboard paired with and connected to this Mac over Bluetooth (not another host, not the dongle).
- No Razer Synapse needed, and no Input Monitoring permission (Caps Lock is polled, not tapped).

## Build and install
```sh
scripts/build.sh        # release build, Info.plist embedded, ad-hoc signed -> .build/release/langlight
scripts/install.sh      # build + copy to ~/.local/bin + install LaunchAgent (starts now and at login)
```
Pass color overrides through the installer, e.g. `scripts/install.sh --he FFAA00 --caps 0000AA`.

On first run macOS asks for Bluetooth access for `langlight`; allow it. Rebuilding changes the code signature, so the prompt may reappear. If no prompt appears, check System Settings > Privacy & Security > Bluetooth.

Uninstall: `langlight uninstall` (removes the LaunchAgent; delete `~/.local/bin/langlight` yourself).

## What it reacts to
Input-source changes, Caps Lock (polled 5 Hz), BLE (re)connect, wake from sleep, screen unlock and session activation. The color is re-sent after each of those because the keyboard forgets it when it sleeps. Writes happen only when the target color changes.

## CLI
```
langlight watch [--he RRGGBB] [--en RRGGBB] [--caps RRGGBB] [--other RRGGBB]
langlight set RRGGBB
langlight get [CLASS ID SUB1 SUB2]      # no args: probes getters 10 80..85
langlight raw CLASS ID SUB1 SUB2 [DATA...]   # hex bytes; prints status, header, payload
langlight install [watch options] | uninstall
```
`LL_DEBUG=1` logs Bluetooth events.

## Troubleshooting
- **Log:** `~/Library/Logs/langlight.log`. "Razer BLE keyboard not connected to this Mac; waiting" means the keyboard is on another host or asleep.
- **Slow change:** the firmware fades a static color over about 3-4 s. A faster path needs the unknown custom-mode frame command (see `docs/protocol.md`).
- **Status:** `launchctl print gui/$(id -u)/local.langlight`.
- **Building from a sandboxed shell:** use `--disable-sandbox` (the scripts already do).

## Layout
`Sources/RazerBLE` is the driver (framing, request queue, CoreBluetooth transport); `Sources/langlight` is the app (policy, monitors, launchd). Protocol notes: `docs/protocol.md`. Plan: `docs/plans/`.

## Tests
`swift test --disable-sandbox` runs the hardware-free unit tests. Manual hardware checklist:
1. `langlight set FF0000` turns the keyboard red (after the fade).
2. `langlight get` prints five `ok` replies.
3. `langlight watch`: switch Hebrew/English and toggle Caps Lock; colors follow.
4. Sleep and wake the Mac: color is re-applied.
5. After `install`, log out and in: the agent runs and the color is right.
