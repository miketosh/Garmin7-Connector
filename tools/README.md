# Tools: watch-log decoding

This directory contains a local decoder for compact Garmin7-Connector watch logs.

## Decode one TXT log

Requirements: Windows PowerShell 5.1 or PowerShell 7. The decoder reads the adjacent `log_codes.json` file and does not require Python, upload the log, or contact a remote service.

Run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\decode_watch_log.ps1 -Path .\path\to\watch-log.txt
```

To save a decoded copy rather than print it to the console:

```powershell
pwsh -NoProfile -File tools\decode_watch_log.ps1 -Path .\path\to\watch-log.txt -OutFile .\watch-log.decoded.txt
```

The original input is not modified. The script expands known two-character event codes into readable event names and named fields, renders known boolean values as `true`/`false`, and reconstructs clock timestamps from timer deltas when the log includes a time anchor. Older long-format lines, separators, notes, and unknown codes are preserved. For an older build, use the code table from the commit that generated that build where possible; mappings may change as the project evolves.

## Tests and event reference

From the repository root, run:

```powershell
python -m unittest discover -s tools -p 'test_*.py'
```

See [the event-code reference](../docs/LOG_CODES.md) and [the project README](../README.md). The decoder is a local text transformation, not a diagnostic upload service. Logs may contain device names, raw advertisement bytes, and glucose values. Inspect and sanitize both raw and decoded files before sharing them in a public issue.
