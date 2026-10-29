# Garmin7-Connector log record codes

This reference documents the compact watch-log format and event mappings used by **Garmin7-Connector**. The machine-readable mapping is maintained in [tools/log_codes.json](../tools/log_codes.json); the decoder is [tools/decode_watch_log.ps1](../tools/decode_watch_log.ps1).

Each compact record is `<milliseconds since previous line><two-character code><value1>:<value2>:...`. A log begins with `@<watch timer> <HHMMSS>`; an uploaded capture may use `@<first timer> <HHMMSS at upload> <timer at upload>`. The decoder restores approximate wall-clock timestamps and labels fields according to the code table.

## Event mapping

| Code | Event | Field variants |
|---|---|---|
| `AA` | `AUTO_CONNECT_ABORT` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|p\\|r\\|o\\|f\\|i\\|l\\|e\\|-\\|r\\|e\\|g\\|i\\|s\\|t\\|r\\|a\\|t\\|i\\|o\\|n\\|-\\|s\\|t\\|a\\|t\\|u\\|s\\|"\\|, \\|r\\|e\\|t\\|r\\|y\\|S\\|e\\|c\\|=\\|"\\|2\\|4\\|0\\|"\\|<br>\\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|p\\|r\\|o\\|f\\|i\\|l\\|e\\|-\\|r\\|e\\|g\\|i\\|s\\|t\\|r\\|a\\|t\\|i\\|o\\|n\\|-\\|t\\|i\\|m\\|e\\|o\\|u\\|t\\|"\\|, \\|r\\|e\\|t\\|r\\|y\\|S\\|e\\|c\\|=\\|"\\|2\\|4\\|0\\|"\\| |
| `AB` | `KEKS_ROUND_TIMING` | \\|s\\|t\\|a\\|g\\|e\\|, \\|r\\|o\\|u\\|n\\|d\\|, \\|e\\|l\\|a\\|p\\|s\\|e\\|d\\|M\\|s\\| |
| `AR` | `AUTO_CONNECT_RESUME` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|p\\|r\\|o\\|f\\|i\\|l\\|e\\|s\\|-\\|r\\|e\\|a\\|d\\|y\\|"\\| |
| `AS` | `AUTH_STATUS` | \\|a\\|u\\|t\\|h\\|e\\|n\\|t\\|i\\|c\\|a\\|t\\|e\\|d\\|, \\|b\\|o\\|n\\|d\\|e\\|d\\|, \\|b\\|o\\|n\\|d\\|e\\|d\\|R\\|a\\|w\\|, \\|n\\|e\\|e\\|d\\|s\\|R\\|e\\|f\\|r\\|e\\|s\\|h\\|, \\|n\\|o\\|t\\|e\\|=\\|"\\|w\\|i\\|r\\|e\\|-\\|s\\|t\\|a\\|t\\|u\\|s\\|-\\|o\\|n\\|l\\|y\\|"\\| |
| `BA` | `BOND_ABORT` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|n\\|o\\|t\\|-\\|c\\|o\\|n\\|n\\|e\\|c\\|t\\|e\\|d\\|"\\|<br>\\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|a\\|l\\|r\\|e\\|a\\|d\\|y\\|-\\|a\\|t\\|t\\|e\\|m\\|p\\|t\\|e\\|d\\|"\\| |
| `BL` | `BACKLIGHT_ERROR` | \\|e\\|r\\|r\\|o\\|r\\| |
| `BQ` | `BOND_STATE_QUERY_EXCEPTION` | \\|e\\|r\\|r\\|o\\|r\\| |
| `BR` | `BLE_BOND_REQUEST` | \\|t\\|r\\|i\\|g\\|g\\|e\\|r\\|=\\|"\\|p\\|o\\|s\\|t\\|-\\|k\\|e\\|k\\|s\\|-\\|p\\|r\\|o\\|t\\|o\\|c\\|o\\|l\\|-\\|s\\|i\\|g\\|n\\|a\\|l\\|"\\| |
| `BV` | `BUILD` | \\|v\\|e\\|r\\|s\\|i\\|o\\|n\\| |
| `BX` | `BOND_EXCEPTION` | \\|e\\|r\\|r\\|o\\|r\\| |
| `CA` | `CONNECT_ABORT` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|s\\|e\\|n\\|s\\|o\\|r\\|-\\|r\\|e\\|p\\|o\\|r\\|t\\|e\\|d\\|-\\|t\\|e\\|r\\|m\\|i\\|n\\|a\\|l\\|-\\|s\\|t\\|a\\|t\\|e\\|"\\|, \\|s\\|t\\|a\\|t\\|e\\|<br>\\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|n\\|o\\|-\\|p\\|a\\|i\\|r\\|i\\|n\\|g\\|-\\|c\\|o\\|d\\|e\\|"\\|<br>\\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|t\\|a\\|r\\|g\\|e\\|t\\|-\\|n\\|o\\|t\\|-\\|s\\|e\\|e\\|n\\|"\\|, \\|t\\|a\\|r\\|g\\|e\\|t\\|<br>\\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|p\\|r\\|o\\|f\\|i\\|l\\|e\\|-\\|r\\|e\\|g\\|i\\|s\\|t\\|r\\|a\\|t\\|i\\|o\\|n\\|-\\|f\\|a\\|i\\|l\\|e\\|d\\|"\\|, \\|r\\|e\\|t\\|r\\|y\\|S\\|e\\|c\\|=\\|"\\|2\\|4\\|0\\|"\\| |
| `CB` | `COLLECTION_BLOCKED` | \\|r\\|e\\|a\\|s\\|o\\|n\\|, \\|t\\|r\\|i\\|g\\|g\\|e\\|r\\| |
| `CC` | `CONNECT_CONFIRMED` | \\|s\\|o\\|u\\|r\\|c\\|e\\|, \\|n\\|a\\|m\\|e\\|, \\|a\\|t\\|t\\|e\\|m\\|p\\|t\\| |
| `CD` | `CONNECT_DEFERRED` | \\|p\\|r\\|o\\|f\\|i\\|l\\|e\\|s\\|R\\|e\\|a\\|d\\|y\\|=\\|"\\|f\\|a\\|l\\|s\\|e\\|"\\|, \\|r\\|e\\|t\\|r\\|y\\|=\\|"\\|o\\|n\\|-\\|p\\|r\\|o\\|f\\|i\\|l\\|e\\|-\\|c\\|a\\|l\\|l\\|b\\|a\\|c\\|k\\|"\\| |
| `CF` | `CONNECT_FAILED` | \\|r\\|e\\|a\\|s\\|o\\|n\\|, \\|a\\|t\\|t\\|e\\|m\\|p\\|t\\|s\\|, \\|r\\|e\\|t\\|r\\|y\\|M\\|s\\| |
| `CN` | `CONNECT_RETURN` | \\|n\\|u\\|l\\|l\\|=\\|"\\|t\\|r\\|u\\|e\\|"\\|, \\|a\\|t\\|t\\|e\\|m\\|p\\|t\\|<br>\\|n\\|u\\|l\\|l\\|=\\|"\\|f\\|a\\|l\\|s\\|e\\|"\\|, \\|c\\|o\\|n\\|n\\|e\\|c\\|t\\|e\\|d\\|, \\|a\\|t\\|t\\|e\\|m\\|p\\|t\\|, \\|n\\|o\\|t\\|e\\|=\\|"\\|c\\|o\\|n\\|n\\|e\\|c\\|t\\|e\\|d\\|-\\|f\\|a\\|l\\|s\\|e\\|-\\|i\\|s\\|-\\|p\\|e\\|n\\|d\\|i\\|n\\|g\\|-\\|u\\|n\\|t\\|i\\|l\\|-\\|c\\|a\\|l\\|l\\|b\\|a\\|c\\|k\\|"\\| |
| `CO` | `G7_CONTROL_OPCODE` | \\|o\\|p\\|c\\|o\\|d\\|e\\|, \\|d\\|a\\|t\\|a\\| |
| `CQ` | `CONNECT_REQUEST` | \\|n\\|a\\|m\\|e\\|, \\|a\\|t\\|t\\|e\\|m\\|p\\|t\\|, \\|r\\|s\\|s\\|i\\|, \\|s\\|t\\|r\\|a\\|t\\|e\\|g\\|y\\|=\\|"\\|D\\|"\\| |
| `CS` | `CONNECT_SKIPPED` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|a\\|t\\|t\\|e\\|m\\|p\\|t\\|-\\|a\\|l\\|r\\|e\\|a\\|d\\|y\\|-\\|m\\|a\\|d\\|e\\|"\\|, \\|i\\|n\\|F\\|l\\|i\\|g\\|h\\|t\\| |
| `CT` | `CRYPTO_SELFTEST` | \\|s\\|h\\|a\\|2\\|5\\|6\\|, \\|a\\|e\\|s\\|1\\|2\\|8\\|, \\|n\\|a\\|t\\|i\\|v\\|e\\|E\\|c\\|, \\|e\\|l\\|a\\|p\\|s\\|e\\|d\\|M\\|s\\|, \\|t\\|i\\|c\\|k\\|B\\|u\\|d\\|g\\|e\\|t\\|K\\|, \\|p\\|a\\|r\\|t\\| |
| `CX` | `CONNECT_EXCEPTION` | \\|a\\|t\\|t\\|e\\|m\\|p\\|t\\|, \\|e\\|r\\|r\\|o\\|r\\| |
| `DA` | `G7_CANDIDATE_PASSED_OVER` | \\|n\\|a\\|m\\|e\\|, \\|w\\|a\\|i\\|t\\|M\\|s\\| |
| `DB` | `G7_DEVICE_BINDING` | \\|n\\|a\\|m\\|e\\|, \\|c\\|o\\|d\\|e\\|, \\|s\\|t\\|o\\|r\\|e\\|d\\| |
| `DC` | `G7_DEVICE_CANDIDATE` | \\|n\\|a\\|m\\|e\\|, \\|r\\|s\\|s\\|i\\|, \\|s\\|e\\|e\\|n\\| |
| `DD` | `G7_DEVICE_BOUND` | \\|n\\|a\\|m\\|e\\|, \\|c\\|o\\|d\\|e\\|, \\|s\\|o\\|u\\|r\\|c\\|e\\| |
| `DF` | `G7_DEVICE_FORGOTTEN` | \\|u\\|n\\|p\\|a\\|i\\|r\\|e\\|d\\| |
| `DK` | `G7_CANDIDATE_NOT_KEY_SENSOR` | \\|n\\|a\\|m\\|e\\|, \\|k\\|e\\|y\\|S\\|e\\|n\\|s\\|o\\|r\\| |
| `DN` | `G7_WRONG_NAME` | \\|n\\|a\\|m\\|e\\|, \\|c\\|o\\|d\\|e\\|, \\|c\\|o\\|u\\|n\\|t\\| |
| `DR` | `CONNECTION_DROPPED` | \\|r\\|e\\|a\\|d\\|i\\|n\\|g\\| |
| `DU` | `G7_DEVICE_UNPAIR_FAILED` | \\|e\\|r\\|r\\|o\\|r\\| |
| `DW` | `G7_WRONG_NAME_SKIPPED` | \\|n\\|a\\|m\\|e\\| |
| `DX` | `G7_DEVICE_CANDIDATE_FAILED` | \\|n\\|a\\|m\\|e\\|, \\|s\\|e\\|e\\|n\\|, \\|u\\|n\\|p\\|a\\|i\\|r\\|e\\|d\\| |
| `EC` | `NATIVE_EC_CALIBRATION_START` |  |
| `EN` | `BLE_ENCRYPTION_STATUS` | \\|s\\|t\\|a\\|t\\|u\\|s\\|, \\|c\\|o\\|n\\|n\\|e\\|c\\|t\\|e\\|d\\|, \\|b\\|o\\|n\\|d\\|e\\|d\\|, \\|n\\|o\\|t\\|e\\|=\\|"\\|B\\|L\\|E\\|_\\|L\\|I\\|N\\|K\\|_\\|S\\|E\\|C\\|U\\|R\\|I\\|T\\|Y\\|_\\|N\\|O\\|T\\|_\\|G\\|7\\|_\\|A\\|P\\|P\\|_\\|A\\|U\\|T\\|H\\|"\\| |
| `GA` | `GATT_AUTH_INDICATION` | \\|o\\|p\\|c\\|o\\|d\\|e\\|, \\|b\\|y\\|t\\|e\\|s\\| |
| `GD` | `GATT_DESCRIPTOR_EXCEPTION` | \\|c\\|h\\|a\\|r\\|a\\|c\\|t\\|e\\|r\\|i\\|s\\|t\\|i\\|c\\|, \\|e\\|r\\|r\\|o\\|r\\| |
| `GE` | `GATT_ENUMERATION_DONE` | \\|s\\|e\\|r\\|v\\|i\\|c\\|e\\|s\\|, \\|l\\|a\\|y\\|o\\|u\\|t\\| |
| `GF` | `GATT_WRITE_FAILED` | \\|p\\|u\\|r\\|p\\|o\\|s\\|e\\|, \\|r\\|e\\|a\\|s\\|o\\|n\\| |
| `GI` | `GATT_INDICATION` | \\|c\\|h\\|a\\|n\\|n\\|e\\|l\\|=\\|"\\|C\\|O\\|N\\|T\\|R\\|O\\|L\\|"\\|, \\|d\\|a\\|t\\|a\\| |
| `GL` | `G7_GLUCOSE` | \\|s\\|e\\|q\\|, \\|s\\|e\\|n\\|s\\|o\\|r\\|C\\|l\\|o\\|c\\|k\\|, \\|a\\|g\\|e\\|S\\|e\\|c\\|, \\|g\\|l\\|u\\|c\\|o\\|s\\|e\\|R\\|a\\|w\\|, \\|g\\|l\\|u\\|c\\|o\\|s\\|e\\|M\\|g\\|D\\|l\\|, \\|r\\|e\\|l\\|i\\|a\\|b\\|l\\|e\\|, \\|d\\|i\\|s\\|p\\|l\\|a\\|y\\|O\\|n\\|l\\|y\\|, \\|a\\|l\\|g\\|o\\|r\\|i\\|t\\|h\\|m\\|S\\|t\\|a\\|t\\|e\\|, \\|t\\|r\\|e\\|n\\|d\\|T\\|e\\|n\\|t\\|h\\|s\\|, \\|p\\|r\\|e\\|d\\|i\\|c\\|t\\|e\\|d\\|R\\|a\\|w\\|, \\|c\\|a\\|l\\|i\\|b\\|r\\|a\\|t\\|i\\|o\\|n\\| |
| `GQ` | `GLUCOSE_REQUEST` | \\|o\\|p\\|c\\|o\\|d\\|e\\|=\\|"\\|4\\|E\\|"\\| |
| `GR` | `G7_GLUCOSE_REJECT` | \\|l\\|e\\|n\\|g\\|t\\|h\\|, \\|m\\|a\\|r\\|k\\|e\\|r\\| |
| `GS` | `GLUCOSE_REQUEST_SKIPPED` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|w\\|r\\|i\\|t\\|e\\|-\\|q\\|u\\|e\\|u\\|e\\|-\\|f\\|u\\|l\\|l\\|"\\| |
| `GW` | `GATT_CHARACTERISTIC_WRITE` | \\|u\\|u\\|i\\|d\\|, \\|s\\|t\\|a\\|t\\|u\\|s\\| |
| `GX` | `GATT_ENUMERATION_EXCEPTION` | \\|e\\|r\\|r\\|o\\|r\\| |
| `K0` | `KEKS_SETTLE_PING` | \\|s\\|t\\|a\\|t\\|u\\|s\\|, \\|c\\|a\\|l\\|l\\|b\\|a\\|c\\|k\\|M\\|s\\| |
| `K1` | `KEKS_ROUND_RX_FIRST` | \\|s\\|t\\|a\\|t\\|e\\|, \\|b\\|y\\|t\\|e\\|s\\| |
| `K2` | `KEKS_CHALLENGE_RX` | \\|p\\|r\\|o\\|o\\|f\\|B\\|y\\|t\\|e\\|s\\|=\\|"\\|8\\|"\\|, \\|c\\|h\\|a\\|l\\|l\\|e\\|n\\|g\\|e\\|B\\|y\\|t\\|e\\|s\\|=\\|"\\|8\\|"\\|, \\|o\\|f\\|f\\|s\\|e\\|t\\|=\\|"\\|9\\|"\\| |
| `K3` | `KEKS_CHALLENGE_REJECT` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|s\\|h\\|o\\|r\\|t\\|"\\|, \\|b\\|y\\|t\\|e\\|s\\| |
| `K4` | `KEKS_CHALLENGE_RESPONSE_TX` | \\|o\\|p\\|c\\|o\\|d\\|e\\|=\\|"\\|0\\|4\\|"\\|, \\|p\\|a\\|y\\|l\\|o\\|a\\|d\\|B\\|y\\|t\\|e\\|s\\|=\\|"\\|8\\|"\\|, \\|k\\|e\\|y\\|S\\|o\\|u\\|r\\|c\\|e\\|=\\|"\\|s\\|a\\|v\\|e\\|d\\|-\\|p\\|e\\|r\\|s\\|i\\|s\\|t\\|e\\|n\\|c\\|e\\|-\\|k\\|e\\|y\\|"\\| |
| `K5` | `KEKS_CHALLENGE_RESPONSE_EXCEPTION` | \\|e\\|r\\|r\\|o\\|r\\| |
| `K6` | `KEKS_CHALLENGE_RESPONSE_ABORT` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|w\\|r\\|i\\|t\\|e\\|-\\|q\\|u\\|e\\|u\\|e\\|-\\|f\\|u\\|l\\|l\\|"\\| |
| `K7` | `KEKS_CHALLENGE_ENCRYPT_FAILED` |  |
| `K8` | `KEKS_BOND_WAIT` | \\|i\\|n\\|d\\|i\\|c\\|a\\|t\\|i\\|o\\|n\\|B\\|y\\|t\\|e\\|s\\|, \\|a\\|u\\|t\\|h\\|e\\|n\\|t\\|i\\|c\\|a\\|t\\|e\\|d\\| |
| `K9` | `KEKS_BOND_TRIGGER_WAIT` | \\|b\\|y\\|t\\|e\\|s\\| |
| `KA` | `KEKS_ABORT` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|e\\|x\\|t\\|r\\|a\\|-\\|c\\|c\\|c\\|d\\|-\\|w\\|r\\|i\\|t\\|e\\|-\\|f\\|a\\|i\\|l\\|e\\|d\\|"\\|, \\|s\\|t\\|a\\|t\\|u\\|s\\|<br>\\|r\\|e\\|a\\|s\\|o\\|n\\|, \\|s\\|t\\|a\\|t\\|e\\|, \\|r\\|x\\|B\\|y\\|t\\|e\\|s\\|, \\|c\\|o\\|n\\|n\\|e\\|c\\|t\\|M\\|s\\| |
| `KB` | `KEKS_FRESH_BEGIN` | \\|c\\|o\\|d\\|e\\|, \\|s\\|l\\|o\\|t\\|, \\|c\\|h\\|u\\|n\\|k\\|s\\|W\\|i\\|t\\|h\\|R\\|e\\|s\\|p\\|o\\|n\\|s\\|e\\|, \\|s\\|e\\|t\\|t\\|l\\|e\\|M\\|o\\|d\\|e\\| |
| `KC` | `KEKS_COMMAND_TX` | \\|p\\|u\\|r\\|p\\|o\\|s\\|e\\|, \\|b\\|y\\|t\\|e\\|s\\|, \\|a\\|c\\|k\\|, \\|a\\|c\\|k\\|M\\|s\\|, \\|g\\|a\\|p\\|M\\|s\\| |
| `KD` | `KEKS_CHUNK_ACK` | \\|c\\|h\\|u\\|n\\|k\\|, \\|c\\|a\\|l\\|l\\|b\\|a\\|c\\|k\\|M\\|s\\| |
| `KE` | `KEKS_REMOTE_CERT_RX` | \\|c\\|o\\|m\\|p\\|l\\|e\\|t\\|e\\|=\\|"\\|t\\|r\\|u\\|e\\|"\\|, \\|b\\|y\\|t\\|e\\|s\\| |
| `KF` | `KEKS_CHUNK_RESPONSE_REFUSED` | \\|s\\|t\\|a\\|t\\|u\\|s\\|, \\|p\\|u\\|r\\|p\\|o\\|s\\|e\\|, \\|o\\|f\\|f\\|s\\|e\\|t\\| |
| `KG` | `KEKS_CERT_FLOW_BEGIN` | \\|a\\|u\\|t\\|h\\|e\\|n\\|t\\|i\\|c\\|a\\|t\\|e\\|d\\|=\\|"\\|t\\|r\\|u\\|e\\|"\\|, \\|b\\|o\\|n\\|d\\|e\\|d\\|=\\|"\\|f\\|a\\|l\\|s\\|e\\|"\\|, \\|m\\|a\\|t\\|e\\|r\\|i\\|a\\|l\\|=\\|"\\|v\\|a\\|l\\|i\\|d\\|a\\|t\\|e\\|d\\|"\\| |
| `KH` | `KEKS_AUTH_PROOF_OK` | \\|d\\|i\\|s\\|p\\|l\\|a\\|y\\|T\\|y\\|p\\|e\\| |
| `KI` | `KEKS_AUTH_INDICATION` | \\|o\\|p\\|c\\|o\\|d\\|e\\|, \\|b\\|y\\|t\\|e\\|s\\|, \\|s\\|t\\|a\\|t\\|e\\| |
| `KJ` | `KEKS_SAVED_KEY_UNAVAILABLE` | \\|r\\|o\\|u\\|n\\|d\\|s\\|R\\|e\\|q\\|u\\|i\\|r\\|e\\|d\\|=\\|"\\|t\\|r\\|u\\|e\\|"\\| |
| `KK` | `KEKS_SAVED_KEY_INVALID` |  |
| `KL` | `KEKS_LOCAL_ROUND_PENDING` | \\|r\\|o\\|u\\|n\\|d\\| |
| `KM` | `KEKS_MATH_DONE` | \\|a\\|c\\|t\\|i\\|o\\|n\\|, \\|o\\|k\\|, \\|d\\|u\\|r\\|a\\|t\\|i\\|o\\|n\\|M\\|s\\|, \\|t\\|i\\|c\\|k\\|s\\|, \\|m\\|a\\|x\\|T\\|i\\|c\\|k\\|K\\| |
| `KN` | `KEKS_NOT_STARTED` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|n\\|o\\|-\\|p\\|a\\|i\\|r\\|i\\|n\\|g\\|-\\|c\\|o\\|d\\|e\\|"\\|<br>\\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|s\\|u\\|b\\|s\\|c\\|r\\|i\\|p\\|t\\|i\\|o\\|n\\|s\\|-\\|n\\|o\\|t\\|-\\|r\\|e\\|a\\|d\\|y\\|"\\|<br>\\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|p\\|a\\|i\\|r\\|i\\|n\\|g\\|-\\|c\\|o\\|d\\|e\\|-\\|f\\|o\\|r\\|m\\|a\\|t\\|"\\|<br>\\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|n\\|a\\|t\\|i\\|v\\|e\\|-\\|e\\|c\\|-\\|c\\|a\\|l\\|i\\|b\\|r\\|a\\|t\\|i\\|o\\|n\\|-\\|f\\|a\\|i\\|l\\|e\\|d\\|"\\|<br>\\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|s\\|e\\|t\\|u\\|p\\|-\\|q\\|r\\|-\\|m\\|a\\|t\\|e\\|r\\|i\\|a\\|l\\|-\\|m\\|i\\|s\\|s\\|i\\|n\\|g\\|-\\|o\\|r\\|-\\|i\\|n\\|v\\|a\\|l\\|i\\|d\\|"\\|<br>\\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|s\\|c\\|a\\|l\\|a\\|r\\|-\\|s\\|e\\|t\\|u\\|p\\|"\\| |
| `KO` | `KEKS_COMPLETE` | \\|a\\|u\\|t\\|h\\|e\\|n\\|t\\|i\\|c\\|a\\|t\\|e\\|d\\|, \\|b\\|o\\|n\\|d\\|e\\|d\\|, \\|k\\|e\\|y\\|P\\|e\\|r\\|s\\|i\\|s\\|t\\|e\\|d\\|, \\|d\\|i\\|s\\|p\\|l\\|a\\|y\\|T\\|y\\|p\\|e\\|, \\|s\\|o\\|u\\|r\\|c\\|e\\| |
| `KP` | `KEKS_PAYLOAD_TX` | \\|p\\|u\\|r\\|p\\|o\\|s\\|e\\|, \\|b\\|y\\|t\\|e\\|s\\|, \\|c\\|a\\|l\\|l\\|b\\|a\\|c\\|k\\|s\\|M\\|i\\|s\\|s\\|e\\|d\\|, \\|b\\|u\\|s\\|y\\|R\\|e\\|t\\|r\\|i\\|e\\|s\\|, \\|s\\|e\\|n\\|d\\|M\\|s\\|, \\|w\\|i\\|t\\|h\\|R\\|e\\|s\\|p\\|o\\|n\\|s\\|e\\|, \\|t\\|h\\|e\\|n\\|=\\|"\\|c\\|o\\|m\\|m\\|a\\|n\\|d\\|"\\|<br>\\|p\\|u\\|r\\|p\\|o\\|s\\|e\\|, \\|b\\|y\\|t\\|e\\|s\\|, \\|c\\|a\\|l\\|l\\|b\\|a\\|c\\|k\\|s\\|M\\|i\\|s\\|s\\|e\\|d\\|, \\|s\\|e\\|n\\|d\\|M\\|s\\|, \\|w\\|i\\|t\\|h\\|R\\|e\\|s\\|p\\|o\\|n\\|s\\|e\\| |
| `KQ` | `KEKS_AUTH_REQUEST` | \\|t\\|o\\|k\\|e\\|n\\|B\\|y\\|t\\|e\\|s\\|=\\|"\\|8\\|"\\|, \\|d\\|i\\|s\\|p\\|l\\|a\\|y\\|T\\|y\\|p\\|e\\| |
| `KR` | `KEKS_ROUND_ACK` | \\|m\\|a\\|t\\|c\\|h\\|e\\|d\\|, \\|b\\|y\\|t\\|e\\|s\\|, \\|s\\|t\\|a\\|t\\|u\\|s\\|, \\|r\\|o\\|u\\|n\\|d\\|, \\|e\\|x\\|p\\|e\\|c\\|t\\|e\\|d\\|R\\|o\\|u\\|n\\|d\\|, \\|r\\|x\\|B\\|y\\|t\\|e\\|s\\|, \\|s\\|t\\|a\\|t\\|e\\| |
| `KS` | `KEKS_AUTH_STATUS` | \\|a\\|u\\|t\\|h\\|e\\|n\\|t\\|i\\|c\\|a\\|t\\|e\\|d\\|, \\|b\\|o\\|n\\|d\\|e\\|d\\|, \\|b\\|o\\|n\\|d\\|e\\|d\\|R\\|a\\|w\\|, \\|d\\|i\\|s\\|p\\|l\\|a\\|y\\|T\\|y\\|p\\|e\\| |
| `KT` | `KEKS_PAIRING_CODE_TRIGGER` | \\|s\\|o\\|u\\|r\\|c\\|e\\| |
| `KU` | `KEKS_AUTH_REPLY_BUFFERED` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|s\\|h\\|a\\|r\\|e\\|d\\|-\\|k\\|e\\|y\\|-\\|p\\|e\\|n\\|d\\|i\\|n\\|g\\|"\\| |
| `KV` | `KEKS_AUTH_REPLY_UNHANDLED` | \\|o\\|p\\|c\\|o\\|d\\|e\\|, \\|b\\|y\\|t\\|e\\|s\\| |
| `KW` | `KEKS_WAIT` | \\|s\\|t\\|a\\|t\\|e\\|, \\|t\\|i\\|m\\|e\\|o\\|u\\|t\\|M\\|s\\|, \\|p\\|u\\|r\\|p\\|o\\|s\\|e\\| |
| `KX` | `KEKS_CHUNK_LOST` | \\|c\\|h\\|u\\|n\\|k\\|, \\|w\\|a\\|i\\|t\\|e\\|d\\|M\\|s\\|, \\|r\\|e\\|s\\|e\\|n\\|d\\| |
| `KY` | `KEKS_ROUND_TRAILING_BYTES` | \\|i\\|g\\|n\\|o\\|r\\|e\\|d\\| |
| `KZ` | `KEKS_EXTRADATA_IGNORED` | \\|s\\|t\\|a\\|t\\|e\\|, \\|b\\|y\\|t\\|e\\|s\\| |
| `LS` | `BLE_CONNECTION_STATE` | \\|n\\|a\\|m\\|e\\|, \\|s\\|t\\|a\\|t\\|e\\|, \\|c\\|o\\|n\\|n\\|e\\|c\\|t\\|e\\|d\\| |
| `MI` | `G7_MESSAGE_IGNORED` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|s\\|e\\|s\\|s\\|i\\|o\\|n\\|-\\|t\\|e\\|r\\|m\\|i\\|n\\|a\\|l\\|"\\|, \\|s\\|t\\|a\\|t\\|e\\|<br>\\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|n\\|o\\|t\\|-\\|a\\|u\\|t\\|h\\|e\\|n\\|t\\|i\\|c\\|a\\|t\\|e\\|d\\|-\\|a\\|n\\|d\\|-\\|b\\|o\\|n\\|d\\|e\\|d\\|"\\| |
| `MR` | `G7_MESSAGE_REJECT` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|e\\|m\\|p\\|t\\|y\\|"\\| |
| `NW` | `SCAN_NEW_DEVICE` | \\|d\\|e\\|v\\|i\\|c\\|e\\|I\\|n\\|d\\|e\\|x\\|, \\|n\\|a\\|m\\|e\\|, \\|r\\|s\\|s\\|i\\| |
| `OB` | `SCAN_DEVICE_SEEN` | \\|n\\|a\\|m\\|e\\|, \\|r\\|s\\|s\\|i\\|, \\|h\\|i\\|t\\|s\\|<br>\\|n\\|a\\|m\\|e\\|, \\|r\\|s\\|s\\|i\\|, \\|h\\|i\\|t\\|s\\|, \\|s\\|e\\|r\\|v\\|i\\|c\\|e\\|U\\|u\\|i\\|d\\|s\\| |
| `PC` | `PAIRING_CODE_SET` | \\|c\\|o\\|d\\|e\\|, \\|p\\|r\\|e\\|v\\|i\\|o\\|u\\|s\\|, \\|c\\|h\\|a\\|n\\|g\\|e\\|d\\|, \\|s\\|a\\|v\\|e\\|d\\|K\\|e\\|y\\|C\\|l\\|e\\|a\\|r\\|e\\|d\\|, \\|p\\|a\\|i\\|r\\|i\\|n\\|g\\|E\\|n\\|a\\|b\\|l\\|e\\|d\\| |
| `PD` | `GATT_PROFILE_REGISTERED` | \\|u\\|u\\|i\\|d\\|, \\|s\\|t\\|a\\|t\\|u\\|s\\|, \\|c\\|o\\|u\\|n\\|t\\|, \\|r\\|e\\|a\\|d\\|y\\| |
| `PE` | `PAIRING_CODE_SAVE_FAILED` | \\|e\\|r\\|r\\|o\\|r\\| |
| `PQ` | `GATT_PROFILE_REGISTER` | \\|r\\|e\\|q\\|u\\|e\\|s\\|t\\|s\\|=\\|"\\|2\\|"\\| |
| `PS` | `GATT_PROFILE_REGISTER_START` | \\|e\\|x\\|p\\|e\\|c\\|t\\|e\\|d\\|=\\|"\\|2\\|"\\|, \\|t\\|i\\|m\\|e\\|o\\|u\\|t\\|M\\|s\\|=\\|"\\|1\\|0\\|0\\|0\\|0\\|"\\| |
| `PT` | `GATT_PROFILE_REGISTER_TIMEOUT` | \\|c\\|o\\|u\\|n\\|t\\|, \\|e\\|x\\|p\\|e\\|c\\|t\\|e\\|d\\|=\\|"\\|2\\|"\\|, \\|t\\|a\\|r\\|g\\|e\\|t\\|Q\\|u\\|e\\|u\\|e\\|d\\| |
| `PX` | `GATT_PROFILE_REGISTER_EXCEPTION` | \\|e\\|r\\|r\\|o\\|r\\| |
| `PZ` | `GATT_PROFILE_LATE_CALLBACK` | \\|u\\|u\\|i\\|d\\|, \\|s\\|t\\|a\\|t\\|u\\|s\\|, \\|i\\|g\\|n\\|o\\|r\\|e\\|d\\|=\\|"\\|t\\|r\\|u\\|e\\|"\\|, \\|r\\|e\\|a\\|s\\|o\\|n\\| |
| `SA` | `SS_ABORT` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|a\\|l\\|r\\|e\\|a\\|d\\|y\\|-\\|c\\|o\\|n\\|n\\|e\\|c\\|t\\|e\\|d\\|"\\|<br>\\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|n\\|o\\|-\\|p\\|a\\|i\\|r\\|i\\|n\\|g\\|-\\|c\\|o\\|d\\|e\\|"\\|, \\|t\\|r\\|i\\|g\\|g\\|e\\|r\\| |
| `SB` | `SCAN_ABORT` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|s\\|e\\|n\\|s\\|o\\|r\\|-\\|r\\|e\\|p\\|o\\|r\\|t\\|e\\|d\\|-\\|t\\|e\\|r\\|m\\|i\\|n\\|a\\|l\\|-\\|s\\|t\\|a\\|t\\|e\\|"\\|, \\|s\\|t\\|a\\|t\\|e\\| |
| `SC` | `BLE scan` | \\|s\\|t\\|a\\|t\\|e\\|, \\|s\\|t\\|a\\|t\\|u\\|s\\| |
| `SE` | `SCAN_G7_SEEN` | \\|n\\|a\\|m\\|e\\|, \\|r\\|s\\|s\\|i\\|, \\|h\\|i\\|t\\|s\\|, \\|m\\|a\\|t\\|c\\|h\\|e\\|d\\|B\\|y\\|, \\|d\\|e\\|x\\|c\\|o\\|m\\|S\\|e\\|r\\|v\\|i\\|c\\|e\\|, \\|a\\|d\\|v\\|e\\|r\\|t\\|i\\|s\\|e\\|m\\|e\\|n\\|t\\|<br>\\|n\\|a\\|m\\|e\\|, \\|r\\|s\\|s\\|i\\|, \\|a\\|d\\|v\\|e\\|r\\|t\\|i\\|s\\|e\\|m\\|e\\|n\\|t\\| |
| `SF` | `SAVED_KEY_CERTIFICATES` | \\|c\\|o\\|n\\|n\\|e\\|c\\|t\\|M\\|s\\| |
| `SG` | `G7_SLOT_POLICY_CHANGE` | \\|p\\|o\\|l\\|i\\|c\\|y\\|, \\|d\\|i\\|s\\|p\\|l\\|a\\|y\\|T\\|y\\|p\\|e\\|, \\|r\\|e\\|a\\|s\\|o\\|n\\| |
| `SK` | `SAVED_KEY_AUTH_BEGIN` | \\|o\\|p\\|c\\|o\\|d\\|e\\|=\\|"\\|0\\|2\\|"\\|, \\|t\\|o\\|k\\|e\\|n\\|B\\|y\\|t\\|e\\|s\\|=\\|"\\|8\\|"\\|, \\|s\\|l\\|o\\|t\\|, \\|c\\|o\\|n\\|n\\|e\\|c\\|t\\|M\\|s\\| |
| `SM` | `SAVED_KEY_PROOF` | \\|m\\|a\\|t\\|c\\|h\\| |
| `SN` | `SAVED_KEY_AUTH_NOT_BONDED` | \\|b\\|o\\|n\\|d\\|e\\|d\\|R\\|a\\|w\\|, \\|c\\|o\\|n\\|n\\|e\\|c\\|t\\|M\\|s\\| |
| `SO` | `G7_SLOT_CHOICE` | \\|c\\|h\\|o\\|i\\|c\\|e\\|, \\|d\\|i\\|s\\|p\\|l\\|a\\|y\\|T\\|y\\|p\\|e\\|<br>\\|c\\|h\\|o\\|i\\|c\\|e\\|, \\|d\\|i\\|s\\|p\\|l\\|a\\|y\\|T\\|y\\|p\\|e\\|, \\|r\\|e\\|a\\|s\\|o\\|n\\| |
| `SP` | `G7_SLOT_POLICY` | \\|p\\|o\\|l\\|i\\|c\\|y\\|, \\|d\\|i\\|s\\|p\\|l\\|a\\|y\\|T\\|y\\|p\\|e\\| |
| `SS` | `SCAN_START` | \\|r\\|e\\|a\\|s\\|o\\|n\\|, \\|r\\|e\\|t\\|r\\|y\\|, \\|d\\|u\\|r\\|a\\|t\\|i\\|o\\|n\\|=\\|"\\|u\\|n\\|t\\|i\\|l\\|-\\|t\\|a\\|r\\|g\\|e\\|t\\|"\\| |
| `ST` | `SAVED_KEY_AUTH_TIMEOUT` | \\|w\\|a\\|i\\|t\\|M\\|s\\|, \\|c\\|o\\|n\\|n\\|e\\|c\\|t\\|M\\|s\\| |
| `SV` | `SAVED_KEY_AUTH_ABORT` | \\|r\\|e\\|a\\|s\\|o\\|n\\|=\\|"\\|w\\|r\\|i\\|t\\|e\\|-\\|q\\|u\\|e\\|u\\|e\\|-\\|f\\|u\\|l\\|l\\|"\\| |
| `SX` | `SAVED_KEY_REFUSED_FOR_WATCH` | \\|k\\|e\\|y\\|P\\|r\\|i\\|n\\|t\\| |
| `SY` | `SCAN_START_EXCEPTION` | \\|e\\|r\\|r\\|o\\|r\\|, \\|r\\|e\\|t\\|r\\|y\\|M\\|s\\| |
| `SZ` | `SCAN_STATE_ERROR` | \\|s\\|t\\|a\\|t\\|u\\|s\\|, \\|r\\|e\\|t\\|r\\|y\\|M\\|s\\| |
| `TM` | `G7_SESSION_TERMINAL` | \\|s\\|t\\|a\\|t\\|e\\|, \\|s\\|e\\|q\\|, \\|a\\|c\\|t\\|i\\|o\\|n\\|=\\|"\\|m\\|a\\|r\\|k\\|-\\|i\\|n\\|a\\|c\\|t\\|i\\|v\\|e\\|-\\|n\\|o\\|-\\|r\\|e\\|s\\|t\\|a\\|r\\|t\\|-\\|n\\|o\\|-\\|r\\|e\\|c\\|o\\|n\\|n\\|e\\|c\\|t\\|"\\| |
| `TS` | `TARGET_SELECTED` | \\|n\\|a\\|m\\|e\\|, \\|r\\|s\\|s\\|i\\|, \\|a\\|c\\|t\\|i\\|o\\|n\\|=\\|"\\|A\\|C\\|"\\| |
| `VH` | `VIEW_HIDDEN` | \\|s\\|c\\|a\\|n\\|n\\|i\\|n\\|g\\|, \\|c\\|o\\|n\\|n\\|e\\|c\\|t\\|e\\|d\\| |
| `VS` | `VIEW_SHOWN` | \\|s\\|c\\|a\\|n\\|n\\|i\\|n\\|g\\|, \\|c\\|o\\|n\\|n\\|e\\|c\\|t\\|e\\|d\\|, \\|r\\|e\\|t\\|r\\|y\\| |
| `WC` | `CCCD_CHARACTERISTIC_MISSING` | \\|c\\|h\\|a\\|n\\|n\\|e\\|l\\|, \\|u\\|u\\|i\\|d\\| |
| `WL` | `G7_WAKE_LOST` | \\|m\\|i\\|s\\|s\\|e\\|d\\|, \\|n\\|e\\|x\\|t\\|=\\|"\\|s\\|c\\|a\\|n\\|-\\|u\\|n\\|t\\|i\\|l\\|-\\|s\\|e\\|e\\|n\\|"\\| |
| `WM` | `CCCD_MISSING` | \\|c\\|h\\|a\\|n\\|n\\|e\\|l\\|, \\|u\\|u\\|i\\|d\\| |
| `WQ` | `CCCD_WRITE_REQUEST` | \\|c\\|h\\|a\\|n\\|n\\|e\\|l\\|, \\|e\\|r\\|r\\|o\\|r\\| |
| `WR` | `CCCD_WRITE_RESULT` | \\|c\\|h\\|a\\|n\\|n\\|e\\|l\\|, \\|s\\|t\\|a\\|t\\|u\\|s\\| |
| `WW` | `G7_WAKE_WAIT` | \\|s\\|c\\|a\\|n\\|I\\|n\\|M\\|s\\|, \\|s\\|i\\|n\\|c\\|e\\|W\\|a\\|k\\|e\\|M\\|s\\|, \\|m\\|i\\|s\\|s\\|e\\|d\\| |
| `WX` | `CCCD_WRITE_EXCEPTION` | \\|c\\|h\\|a\\|n\\|n\\|e\\|l\\|, \\|e\\|r\\|r\\|o\\|r\\| |
| `XA` | `CRYPTO_AES_EXCEPTION` | \\|e\\|r\\|r\\|o\\|r\\| |
| `XI` | `G7_EXTRADATA_INDICATION` | \\|b\\|y\\|t\\|e\\|s\\|, \\|s\\|t\\|a\\|t\\|e\\| |
| `XS` | `CRYPTO_SHA_EXCEPTION` | \\|e\\|r\\|r\\|o\\|r\\| |

## Notes

- The table must match the build that produced the log. Use the versioned table from that commit when decoding older captures.
- Constants written as `name="value"` identify fixed values; bare quoted values are literal text. The decoder preserves lines it cannot interpret.
- Logs can contain device names, advertisement bytes, glucose readings, and other identifying or sensitive details. Inspect and sanitize them before sharing.
