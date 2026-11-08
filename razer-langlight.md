---
name: razer-langlight
description: In-progress project making the Razer PT Ergo BLE keyboard change color by Hebrew/English input source (~/razer-work/langlight)
metadata:
  node_type: memory
  type: project
  originSessionId: e3f142ac-0d0b-4581-836f-d59a004dd0d0
  modified: 2026-10-19T12:37:02.210Z
---

User wants their Razer PT Ergo keyboard (Bluetooth LE, full RGB, 19 zones) to show a different color for Hebrew vs English input. Helper: `~/razer-work/langlight/langlight` (Swift, CoreBluetooth); modes `set RRGGBB`, `watch [--en][--he]`, `raw CLASS ID SUB1 SUB2 DATA...`; `LL_DEBUG=1` logs notifications.

Protocol findings (2026-10-19): service 52401523-f97c-7f90-0e7f-6c6f4e36db1c, write ...1524, notify ...1525; 8-byte header [txid, len 3B LE, class, cmd, sub1, sub2], payload in 20-byte chunks. Static: `10 03 01 00` + `01 00 00 01 R G B`. Works, but firmware fades ~3-4 s (save flag and speed byte don't help). Custom mode `10 03 00 00 08...` is accepted (goes dark), but frame cmd unknown (`10 04` -> target not supported). Gets: 10 80/81/82/83/85 exist.

**Why:** User wants a fast color switch; the fade was the remaining complaint.
**How to apply:** Next step: user applies a per-zone Chroma Studio effect, then grep Synapse logs (`~/Library/Application Support/Razer/RazerAppEngine/User Data/Logs`, "BLEProtocol30 ... write:") for the frame command. Not yet installed as a login item.
