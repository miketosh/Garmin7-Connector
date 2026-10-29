# Garmin7-Connector

Experimental direct Bluetooth Low Energy (BLE) connection research for Dexcom G7 sensors on compatible Garmin Connect IQ watches. The manifest lists a broad set of newer Forerunner, Fēnix 7/8/9, Epix, Enduro, Instinct, Venu, and vívoactive targets. The CI workflow exports a multi-product `.iq` package for the manifest and attempts a device-specific `.prg` for every product ID using the SDK image. Targets unavailable in that image are reported as warnings; physical validation remains necessary.

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

The project uses Monkey C and the Garmin Connect IQ SDK. GitHub Actions runs host-side regression tests, fetches and validates the public xDrip G7 KEKS setup-QR material, generates the required Monkey C source only in the temporary build workspace, exports a multi-product `.iq` package from the manifest, and attempts side-loadable `.prg` builds for all manifest product IDs supported by the SDK image. On a GitHub Release, the `.iq` package and successful PRGs are attached as downloadable release assets. Pull-request and branch builds publish them as a 30-day Actions artifact. The workflow uses a temporary signing key for testing; it is not a persistent Connect IQ Store signing identity. The QR identity is embedded in the resulting binary, so the binary contains the same protocol setup material sourced from xDrip's published QR. This is not proof the sensor still accepts that identity.

```sh
python -m unittest discover -s tools -p 'test_*.py'
python tools/test_no_stop_session.py
```

A passing host test suite or compile is not proof that the sensor accepted the handshake. Use the device-specific PRG matching your watch when one is available. The `.iq` package is the multi-product Connect IQ export; a `.prg` is a device-targeted sideloadable build. Review the workflow summary/log for target-specific failures before assuming every manifest product received a PRG.

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

## License status

No license has been selected yet. Please do not assume this repository grants broad permission to redistribute or reuse the code. The maintainer should choose a license before accepting outside contributions for ongoing distribution.

## Reading diagnostic logs

Compact watch logs can be expanded locally with the included PowerShell decoder. It replaces two-character event codes with readable event names, labels fields, expands boolean values, and reconstructs clock times from the log's timer deltas. It does not upload the log or contact a service.

From the repository root, run in Windows PowerShell 5.1 or PowerShell 7:

```powershell
powershell -ExecutionPolicy Bypass -File tools\\decode_watch_log.ps1 -Path .\\path\\to\\watch-log.txt
```

To save a decoded copy instead of printing it to the console:

```powershell
pwsh tools/decode_watch_log.ps1 -Path .\\path\\to\\watch-log.txt -OutFile .\\watch-log.decoded.txt
```

The original input is not modified. Older long-format log lines and unrecognized event codes are preserved rather than discarded. Review and sanitize decoded output before sharing: diagnostic logs may contain device names, raw advertisement bytes, and glucose values.
