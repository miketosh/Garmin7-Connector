# Garmin7-Connector log record codes

This reference documents the compact watch-log format and event mappings used by **Garmin7-Connector**. The machine-readable mapping is maintained in [tools/log_codes.json](../tools/log_codes.json); the decoder is [tools/decode_watch_log.ps1](../tools/decode_watch_log.ps1).

Each compact record is `<milliseconds since previous line><two-character code><value1>:<value2>:...`. A log begins with `@<watch timer> <HHMMSS>`; an uploaded capture may use `@<first timer> <HHMMSS at upload> <timer at upload>`. The decoder restores approximate wall-clock timestamps and labels fields according to the code table.

> **Known limitation (2026-11-01):** Connector intentionally emits privacy-reduced records, but some variants in `tools/log_codes.json` still describe the longer Scout records. The generated table below therefore does not accurately label every Connector record. See **Known source-vs-mapping mismatches** at the end; for those codes, preserve and interpret raw positional values rather than trusting the decoder's field names. This note documents the limitation only; it does not change decoder behavior.

## Event mapping

| Code | Event | Field variants |
|---|---|---|
| `AA` | `AUTO_CONNECT_ABORT` | reason="profile-registration-status", retrySec="240"<br>reason="profile-registration-timeout", retrySec="240" |
| `AB` | `KEKS_ROUND_TIMING` | stage, round, elapsedMs |
| `AR` | `AUTO_CONNECT_RESUME` | reason="profiles-ready" |
| `AS` | `AUTH_STATUS` | authenticated, bonded, bondedRaw, needsRefresh, note="wire-status-only" |
| `BA` | `BOND_ABORT` | reason="not-connected"<br>reason="already-attempted" |
| `BL` | `BACKLIGHT_ERROR` | error |
| `BQ` | `BOND_STATE_QUERY_EXCEPTION` | error |
| `BR` | `BLE_BOND_REQUEST` | trigger="post-keks-protocol-signal" |
| `BV` | `BUILD` | version |
| `BX` | `BOND_EXCEPTION` | error |
| `CA` | `CONNECT_ABORT` | reason="sensor-reported-terminal-state", state<br>reason="no-pairing-code"<br>reason="target-not-seen", target<br>reason="profile-registration-failed", retrySec="240" |
| `CB` | `COLLECTION_BLOCKED` | reason, trigger |
| `CC` | `CONNECT_CONFIRMED` | source, name, attempt |
| `CD` | `CONNECT_DEFERRED` | profilesReady="false", retry="on-profile-callback" |
| `CF` | `CONNECT_FAILED` | reason, attempts, retryMs |
| `CL` | `COLLECTOR` | collector, source, changedAt |
| `CN` | `CONNECT_RETURN` | null="true", attempt<br>null="false", connected, attempt, note="connected-false-is-pending-until-callback" |
| `CO` | `G7_CONTROL_OPCODE` | opcode, data |
| `CQ` | `CONNECT_REQUEST` | name, attempt, rssi, strategy="D" |
| `CS` | `CONNECT_SKIPPED` | reason="attempt-already-made", inFlight |
| `CT` | `CRYPTO_SELFTEST` | sha256, aes128, nativeEc, elapsedMs, tickBudgetK, part |
| `CX` | `CONNECT_EXCEPTION` | attempt, error |
| `DA` | `G7_CANDIDATE_PASSED_OVER` | name, waitMs |
| `DB` | `G7_DEVICE_BINDING` | name, code, stored |
| `DC` | `G7_DEVICE_CANDIDATE` | name, rssi, seen |
| `DD` | `G7_DEVICE_BOUND` | name, code, source |
| `DF` | `G7_DEVICE_FORGOTTEN` | unpaired |
| `DK` | `G7_CANDIDATE_NOT_KEY_SENSOR` | name, keySensor |
| `DN` | `G7_WRONG_NAME` | name, code, count |
| `DR` | `CONNECTION_DROPPED` | reading |
| `DU` | `G7_DEVICE_UNPAIR_FAILED` | error |
| `DW` | `G7_WRONG_NAME_SKIPPED` | name |
| `DX` | `G7_DEVICE_CANDIDATE_FAILED` | name, seen, unpaired |
| `EC` | `NATIVE_EC_CALIBRATION_START` | (none) |
| `EN` | `BLE_ENCRYPTION_STATUS` | status, connected, bonded, note="BLE_LINK_SECURITY_NOT_G7_APP_AUTH" |
| `GA` | `GATT_AUTH_INDICATION` | opcode, bytes |
| `GD` | `GATT_DESCRIPTOR_EXCEPTION` | characteristic, error |
| `GE` | `GATT_ENUMERATION_DONE` | services, layout |
| `GF` | `GATT_WRITE_FAILED` | purpose, reason |
| `GI` | `GATT_INDICATION` | channel="CONTROL", data |
| `GL` | `G7_GLUCOSE` | seq, sensorClock, ageSec, glucoseRaw, glucoseMgDl, reliable, displayOnly, algorithmState, trendTenths, predictedRaw, calibration |
| `GQ` | `GLUCOSE_REQUEST` | opcode="4E" |
| `GR` | `G7_GLUCOSE_REJECT` | length, marker |
| `GS` | `GLUCOSE_REQUEST_SKIPPED` | reason="write-queue-full" |
| `GW` | `GATT_CHARACTERISTIC_WRITE` | uuid, status |
| `GX` | `GATT_ENUMERATION_EXCEPTION` | error |
| `K0` | `KEKS_SETTLE_PING` | status, callbackMs |
| `K1` | `KEKS_ROUND_RX_FIRST` | state, bytes |
| `K2` | `KEKS_CHALLENGE_RX` | proofBytes="8", challengeBytes="8", offset="9" |
| `K3` | `KEKS_CHALLENGE_REJECT` | reason="short", bytes |
| `K4` | `KEKS_CHALLENGE_RESPONSE_TX` | opcode="04", payloadBytes="8", keySource="saved-persistence-key" |
| `K5` | `KEKS_CHALLENGE_RESPONSE_EXCEPTION` | error |
| `K6` | `KEKS_CHALLENGE_RESPONSE_ABORT` | reason="write-queue-full" |
| `K7` | `KEKS_CHALLENGE_ENCRYPT_FAILED` | (none) |
| `K8` | `KEKS_BOND_WAIT` | indicationBytes, authenticated |
| `K9` | `KEKS_BOND_TRIGGER_WAIT` | bytes |
| `KA` | `KEKS_ABORT` | reason="extra-cccd-write-failed", status<br>reason, state, rxBytes, connectMs |
| `KB` | `KEKS_FRESH_BEGIN` | code, slot, chunksWithResponse, settleMode |
| `KC` | `KEKS_COMMAND_TX` | purpose, bytes, ack, ackMs, gapMs |
| `KD` | `KEKS_CHUNK_ACK` | chunk, callbackMs |
| `KE` | `KEKS_REMOTE_CERT_RX` | complete="true", bytes |
| `KF` | `KEKS_CHUNK_RESPONSE_REFUSED` | status, purpose, offset |
| `KG` | `KEKS_CERT_FLOW_BEGIN` | authenticated="true", bonded="false", material="validated" |
| `KH` | `KEKS_AUTH_PROOF_OK` | displayType |
| `KI` | `KEKS_AUTH_INDICATION` | opcode, bytes, state |
| `KJ` | `KEKS_SAVED_KEY_UNAVAILABLE` | roundsRequired="true" |
| `KK` | `KEKS_SAVED_KEY_INVALID` | (none) |
| `KL` | `KEKS_LOCAL_ROUND_PENDING` | round |
| `KM` | `KEKS_MATH_DONE` | action, ok, durationMs, ticks, maxTickK |
| `KN` | `KEKS_NOT_STARTED` | reason="no-pairing-code"<br>reason="subscriptions-not-ready"<br>reason="pairing-code-format"<br>reason="native-ec-calibration-failed"<br>reason="setup-qr-material-missing-or-invalid"<br>reason="scalar-setup" |
| `KO` | `KEKS_COMPLETE` | authenticated, bonded, keyPersisted, displayType, source |
| `KP` | `KEKS_PAYLOAD_TX` | purpose, bytes, callbacksMissed, busyRetries, sendMs, withResponse, then="command"<br>purpose, bytes, callbacksMissed, sendMs, withResponse |
| `KQ` | `KEKS_AUTH_REQUEST` | tokenBytes="8", displayType |
| `KR` | `KEKS_ROUND_ACK` | matched, bytes, status, round, expectedRound, rxBytes, state |
| `KS` | `KEKS_AUTH_STATUS` | authenticated, bonded, bondedRaw, displayType |
| `KT` | `KEKS_PAIRING_CODE_TRIGGER` | source |
| `KU` | `KEKS_AUTH_REPLY_BUFFERED` | reason="shared-key-pending" |
| `KV` | `KEKS_AUTH_REPLY_UNHANDLED` | opcode, bytes |
| `KW` | `KEKS_WAIT` | state, timeoutMs, purpose |
| `KX` | `KEKS_CHUNK_LOST` | chunk, waitedMs, resend |
| `KY` | `KEKS_ROUND_TRAILING_BYTES` | ignored |
| `KZ` | `KEKS_EXTRADATA_IGNORED` | state, bytes |
| `LS` | `BLE_CONNECTION_STATE` | name, state, connected |
| `MI` | `G7_MESSAGE_IGNORED` | reason="session-terminal", state<br>reason="not-authenticated-and-bonded" |
| `MR` | `G7_MESSAGE_REJECT` | reason="empty" |
| `NW` | `SCAN_NEW_DEVICE` | deviceIndex, name, rssi |
| `OB` | `SCAN_DEVICE_SEEN` | name, rssi, hits<br>name, rssi, hits, serviceUuids |
| `P1` | `PHONE_CAPABILITIES` | event |
| `PC` | `PAIRING_CODE_SET` | code, previous, changed, savedKeyCleared, pairingEnabled |
| `PD` | `GATT_PROFILE_REGISTERED` | uuid, status, count, ready |
| `PE` | `PAIRING_CODE_SAVE_FAILED` | error |
| `PF` | `PHONE_LINK_REGISTER_FAILED` | error |
| `PG` | `PHONE_GLUCOSE_SENT` | sequence, result |
| `PJ` | `PHONE_KEY_REJECTED` | reason="format"<br>reason="storage", error |
| `PK` | `PHONE_KEY_STORED` | keyBytes="16", keySensorKnown |
| `PL` | `PHONE_LINK_REGISTERED` | (none) |
| `PM` | `PHONE_MSG` | type, fields |
| `PQ` | `GATT_PROFILE_REGISTER` | requests="2" |
| `PS` | `GATT_PROFILE_REGISTER_START` | expected="2", timeoutMs="10000" |
| `PT` | `GATT_PROFILE_REGISTER_TIMEOUT` | count, expected="2", targetQueued |
| `PX` | `GATT_PROFILE_REGISTER_EXCEPTION` | error |
| `PZ` | `GATT_PROFILE_LATE_CALLBACK` | uuid, status, ignored="true", reason |
| `RK` | `KEKS_ROUND_PACE` | purpose, keepAliveReads, maxReadMs, chainBroken, commandSinceFrameMs |
| `RP` | `KEKS_PREPARE` | stage, reason, elapsedMs |
| `SA` | `SS_ABORT` | reason="already-connected"<br>reason="no-pairing-code", trigger |
| `SB` | `SCAN_ABORT` | reason="sensor-reported-terminal-state", state |
| `SC` | `BLE scan` | state, status |
| `SE` | `SCAN_G7_SEEN` | name, rssi, hits, matchedBy, dexcomService, advertisement<br>name, rssi, advertisement |
| `SF` | `SAVED_KEY_CERTIFICATES` | connectMs |
| `SG` | `G7_SLOT_POLICY_CHANGE` | policy, displayType, reason |
| `SK` | `SAVED_KEY_AUTH_BEGIN` | opcode="02", tokenBytes="8", slot, connectMs |
| `SM` | `SAVED_KEY_PROOF` | match |
| `SN` | `SAVED_KEY_AUTH_NOT_BONDED` | bondedRaw, connectMs |
| `SO` | `G7_SLOT_CHOICE` | choice, displayType<br>choice, displayType, reason |
| `SP` | `G7_SLOT_POLICY` | policy, displayType |
| `SS` | `SCAN_START` | reason, retry, duration="until-target" |
| `ST` | `SAVED_KEY_AUTH_TIMEOUT` | waitMs, connectMs |
| `SV` | `SAVED_KEY_AUTH_ABORT` | reason="write-queue-full" |
| `SX` | `SAVED_KEY_REFUSED_FOR_WATCH` | keyPrint |
| `SY` | `SCAN_START_EXCEPTION` | error, retryMs |
| `SZ` | `SCAN_STATE_ERROR` | status, retryMs |
| `TM` | `G7_SESSION_TERMINAL` | state, seq, action="mark-inactive-no-restart-no-reconnect" |
| `TS` | `TARGET_SELECTED` | name, rssi, action="AC" |
| `VH` | `VIEW_HIDDEN` | scanning, connected |
| `VS` | `VIEW_SHOWN` | scanning, connected, retry |
| `WC` | `CCCD_CHARACTERISTIC_MISSING` | channel, uuid |
| `WL` | `G7_WAKE_LOST` | missed, next="scan-until-seen" |
| `WM` | `CCCD_MISSING` | channel, uuid |
| `WQ` | `CCCD_WRITE_REQUEST` | channel, error |
| `WR` | `CCCD_WRITE_RESULT` | channel, status |
| `WW` | `G7_WAKE_WAIT` | scanInMs, sinceWakeMs, missed |
| `WX` | `CCCD_WRITE_EXCEPTION` | channel, error |
| `XA` | `CRYPTO_AES_EXCEPTION` | error |
| `XI` | `G7_EXTRADATA_INDICATION` | bytes, state |
| `XS` | `CRYPTO_SHA_EXCEPTION` | error |

## Notes

- The table must match the build that produced the log. Use the versioned table from that commit when decoding older captures.
- Constants written as `name="value"` identify fixed values; bare quoted values are literal text. The decoder preserves lines it cannot interpret.
- Logs can contain device names, advertisement bytes, glucose readings, and other identifying or sensitive details. Inspect and sanitize them before sharing.


## Known source-vs-mapping mismatches (2026-11-01)

A source review of `source/ScoutApp.mc` and `source/ScoutPhoneLink.mc` found these differences between the privacy-reduced records currently emitted by Connector and the longer variants in `tools/log_codes.json`:

| Code | Current Connector record shape | Difference from the mapping |
|---|---|---|
| `LS` | `LS` (no fields) | Mapping lists `name,state,connected`. |
| `GL` | `GL<seq>:<ageSec>:<displayOnly>:<algorithmState>` | Four values are emitted; the mapping lists eleven. |
| `DK`, `DW`, `DC`, `DD` | Code only (no fields) | Mapping lists candidate/name/key/source fields that Connector does not emit. |
| `DA` | `DA:<waitMs>` | Connector emits the wait duration only, not a candidate name. |
| `DN` | `DN:<count>` | Connector emits the wrong-name count only, not the name or pairing code. |
| `CQ` | `CQ:<attempt>` | Connector emits the attempt number only, not name/RSSI/strategy. |
| `CO` | `CO<opcode>:<payloadLength>` | The second value is the payload length, not payload data. |
| `CA` | `CAsensor-reported-terminal-state:<state>`; `CAno-pairing-code`; `CAtarget-not-seen`; `CAprofile-registration-failed:240` | The `target-not-seen` variant has no target field in Connector. |
| `SE` | Candidate: `SE<name>:<rssi>:<hits>:<P-or-U>:<FEBC-or->:<rawAdvertisementHex>`; connection: `SE:<rssi>` | The connection variant contains only RSSI, not name and advertisement. |
| `PM` | `PM<type>:<fieldCount>` | The second value is the field count/size, not the field contents. |

These are schema/documentation findings, not a decoder fix. The mapping file is executable tooling data consumed by the local decoder; reconciling it and its tests requires a separate tooling change outside this documentation-only pass. Until then, do not treat decoded field names for these variants as authoritative.
