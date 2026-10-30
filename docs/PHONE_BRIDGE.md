# Collector setting and optional phone bridge

The watch connects to the G7 directly; no phone app is needed for that. The **Collector** setting decides whether the watch connects at all and which of the sensor's Bluetooth slots it asks for. An optional phone bridge to a modified xDrip+ build can change the same setting from the phone, hand the watch a saved sensor key, and receive the watch's readings.

## Collector modes

The G7 serves one client per slot: slot `02` (the phone/app slot) and slot `03` (the watch slot). Two clients on the same slot would compete, so the mode fixes who uses which slot. In the watch menu, **Collector** moves to the next mode on each press.

| Mode | Watch | Phone (xDrip) | Slot the watch asks for |
|---|---|---|---|
| None | off | off | — |
| Phone as App | off | collects on `02` | — |
| Watch as App | collects on `02` | off | `02` |
| Watch as Watch (fresh-install default) | collects on `03` | off | `03` |
| Dual Collector | collects on `03` | collects on `02` | `03` |

- Pick **Watch as Watch** or **Dual Collector** when a phone app (Dexcom's or another) already holds slot `02`.
- Pick **Watch as App** only when nothing else uses slot `02`.
- The pairing code still gates everything: with `----` the watch never scans or connects, whatever the mode.
- The mode is stored on the watch and survives restarts. The Status screen shows the mode, the slot (the AuthRequest DisplayType) and the last send to the phone.

## Phone bridge (optional)

The bridge uses Garmin Connect IQ app messages, so it needs the Garmin Connect app on the phone and an xDrip+ build that carries the Garmin watch module (the `garmin-watch` branch of [miketosh/xDrip-Watch](https://github.com/miketosh/xDrip-Watch)). Stock xDrip+ does not send these messages. The manifest requests the `Communications` permission for this; without a bridge phone the watch ignores it.

Messages (Connect IQ dictionaries, version 1):

| Message | Direction | Content |
|---|---|---|
| `caps` | both | Field versions each side understands (`r=1` asks for a reply). A field newer than the peer advertises is not sent to it. |
| `collector` | both | `c`: the mode (`none`, `phone`, `watch02`, `watch03`, `dual`; field `collector.c` version 2), `ts`: epoch seconds of the change. The newer change wins; on a tie the phone's stands. An older peer gets `watch`, `phone` or `both`. |
| `key` | phone → watch | A 16-byte saved sensor key (hex) and, optionally, the sensor name it belongs to. The watch then logs in with it instead of running the full pairing; if the sensor does not accept it, the watch runs its own pairing and bond. Key bytes are never logged. |
| `glucose` | watch → phone | One message per new valid reading: sensor name, sequence, mg/dL, sensor time, trend; optional fields only to a phone that advertises them. |
| `ping` | phone → watch | Link test. |

The watch retries an undelivered collector change at start and after each reading it sends. A saved key belongs to the sensor's Bluetooth bond with the device that paired it; a watch using a phone's key may still need its own certificates and bond.

## What is not proven

- No part of this has been confirmed with a live sensor on every listed watch model; see [TESTING.md](TESTING.md).
- The bridge has been exercised between the private development build and the xDrip-Watch fork; this public build uses a different Connect IQ app ID, which the phone side must also address.
