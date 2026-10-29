# Garmin7-Connector

Experimental direct Bluetooth Low Energy (BLE) connection research for Dexcom G7 sensors on compatible Garmin Connect IQ watches. The manifest now lists a broad set of newer Forerunner, Fenix 7/8/9, Epix, Enduro, Instinct, Venu, and vívoactive targets; model-by-model compilation and physical validation remain necessary.

This is a **community testing project**, not a medical device. It is not validated for treatment decisions. Do not use it as a replacement for your prescribed CGM display, alerts, or medical advice.

## Current status

- Fresh KEKS pairing and authentication are experimental.
- Automated tests and simulator sessions do not prove successful pairing with a real sensor.
- Physical-watch testing is required. Please report exact watch model, app commit/build, and sanitized diagnostic details when asking for help.
- Direct watch-to-sensor testing should not require xDrip.
- This public repository is separate from the author's private development repository. It excludes personal watch logs, private defaults, and automatic log uploading.

## Before testing

1. Confirm your watch model is listed in `manifest.xml`. The project is intended to support compatible BLE-capable Connect IQ watches, including Fenix models, but each model still needs compile and physical-device validation.
2. Build the app using the Garmin Connect IQ SDK and your own developer signing key.
3. Install it using Garmin's supported developer workflow.
4. Open the app and enter **your own sensor's four-digit pairing code** in the pairing-code menu. The default is `----`, which disables pairing until you enter a code.
5. Keep your normal CGM and pump workflows available. This experiment is not a reliable glucose source.
6. Capture the watch's Connect IQ log locally if a test fails. Review it before sharing; remove personal identifiers, any glucose values you do not want to disclose, and credentials or pairing material.

## Build and test

The project uses Monkey C and the Garmin Connect IQ SDK. Host-side tests are in `tools/`; simulator code is under `sim/` and `test/`. Start with:

```sh
python -m unittest discover -s tools -p 'test_*.py'
python tools/test_no_stop_session.py
```

A passing host test suite or compile is not proof that the sensor accepted the handshake. The public CI workflow will validate host-side code; a signed watch build requires maintainer-controlled signing credentials.

## Reporting a test

Open a GitHub issue with:
- Watch model (255 or 255 Music) and firmware version
- App commit or build identifier
- Whether this was fresh pairing or a saved-key reconnect
- Approximate attempt time and result
- A reviewed, sanitized log excerpt

Never attach an unreviewed full log, a developer signing key, GitHub token, or personal credentials.

## Contributing

Pull requests are welcome. Keep changes focused and include tests for protocol-state, BLE callback ordering, timeouts, and malformed input where relevant. Do not add personal logs, hard-coded pairing defaults, generated authentication material, or secrets. Describe physical-device validation separately from simulator/test results.

## Safety and scope

The app must not issue sensor session-start, session-stop, or reset commands. A missing or stale reading must not be presented as current. The project is experimental and may fail to pair, disconnect, or display no reading.
