# Contributing to Garmin7-Connector

Thanks for helping test direct G7 BLE pairing on Garmin watches.

## Scope
This is an experimental research project. Changes should improve direct watch-to-sensor connection, pairing, diagnostics, portability across Connect IQ devices, or repeatable tests.

## Before opening a pull request
- Run host-side Python tests.
- Explain whether validation was source-level, simulated, or performed on physical hardware.
- For hardware tests, include watch model/firmware, app commit/build, fresh pairing vs saved-key reconnect, and approximate attempt time.
- Review all logs and screenshots before attaching them.

## Do not commit
- Raw watch or phone logs, sensor identifiers, personal glucose data, pairing codes, saved authentication keys, private QR/key material, signing keys, tokens, or credentials.
- Generated PRG/IQ artifacts unless a maintainer explicitly asks for one.
- Personal-specific defaults or test assumptions.

## Protocol changes
Avoid changing BLE write mode, timing, callback ordering, cryptographic order, or session lifecycle without evidence. Add a focused regression test when changing handshake state, response ordering, timeout handling, or parsing. Never send session start/stop/reset commands to a sensor.

## Device support
Manifest entries should be based on valid Connect IQ product IDs and compile/runtime compatibility. Simulator success is not physical-device validation. Report unsupported APIs, screen-layout issues, memory limits, and execution-limit failures with model-specific evidence.
