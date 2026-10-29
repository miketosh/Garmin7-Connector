# BLE pairing test protocol

This project is an experimental direct BLE client. The phone integration and log-upload path from the private development project have been disabled in this public build. The watch is the collector; no xDrip app is required for the direct connection attempt.

## Fresh-pairing test

1. Build for the exact watch product ID.
2. Install the app and open **Pairing code**.
3. Enter the four-digit code for the sensor being tested. The default `----` is intentionally unusable, so no scan/pair attempt starts until a tester enters their own code.
4. Keep the watch near the sensor and record the attempt start time.
5. Let the attempt complete or fail naturally. Avoid rapid repeated retries that could make the timing evidence ambiguous.
6. Record whether the result reached BLE connection, GATT discovery, authentication/KEKS, bonding, and valid glucose parsing. A successful BLE connection alone is not a successful sensor session.

## Saved-key reconnect

A saved key can only be used if this watch previously established or was explicitly provisioned with the matching key. A clean install and a fresh sensor pairing are the preferred initial test for new contributors.

## Useful diagnostic events

- `CF`: connection attempt failed; includes a generic failure reason and retry delay.
- `KR`: a KEKS round acknowledgement was observed and whether it matched the expected round.
- `ABsend-queued`: local round response was queued/issued.
- `ABack-queue`: time from the matched round-1 acknowledgement to queueing the response.
- `ABproof-done`: elapsed time for peer-proof verification.
- `GL`: parsed reading event metadata only; the public build intentionally does not write raw or displayed glucose values to the diagnostic line.

These events are timing aids, not proof of protocol correctness. Host-side source tests do not emulate Garmin's native BLE stack or a live sensor.

## Report a failure

Please include:
- Exact watch model, firmware, and Connect IQ SDK version used to build.
- Commit SHA and app build identifier.
- Whether this was fresh pairing or a saved-key reconnect.
- Whether xDrip was installed/running (for the direct test it should not be required).
- Approximate local time and which phase was last reached.
- Only a short, reviewed, sanitized diagnostic excerpt.

Before sharing a log, inspect it for pairing codes, sensor identifiers, glucose values, personal timestamps, authentication material, and any other personal information. Do not upload full raw logs by default. If a log appears to include a code or sensitive packet, do not attach it; summarize the event instead.

## Device compatibility

The manifest lists many current Connect IQ targets, but the UI and BLE lifecycle are not validated on every model. Include model-specific results. Differences in API availability, screen geometry, memory, execution limits, BLE callback timing, and battery behavior should be tracked separately rather than assumed to be sensor-protocol failures.
