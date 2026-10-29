<#
.SYNOPSIS
Turns compact Garmin7-Connector watch logs into readable lines.

.DESCRIPTION
Each compact record is "<ms since the previous line><2-char code><v1>:<v2>:...".
The public code table tools/log_codes.json gives event names and field order for this repository. Anchor lines
"@<watch timer> <HHMMSS>" (watch log file) or "@<timer of first line> <HHMMSS>
<timer now>" (upload) turn the deltas into wall-clock times. Lines in the old
long format, "=====" markers and "(...)" notes pass through unchanged.

Runs in Windows PowerShell 5.1 and PowerShell 7 (Windows, Linux, macOS).

.EXAMPLE
powershell -ExecutionPolicy Bypass -File tools\decode_watch_log.ps1 -Path logs\garmin7-scout-fr255.txt
pwsh tools/decode_watch_log.ps1 -Path watch/2026-10-25/091500-run-277-abc1234-abort.txt -OutFile decoded.txt
#>
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Codes,
    [string]$OutFile
)
$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 leaves $PSScriptRoot empty in parameter defaults.
if (-not $Codes) { $Codes = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "log_codes.json" }

$table = @{}
$json = Get-Content -LiteralPath $Codes -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($p in $json.PSObject.Properties) { $table[$p.Name] = $p.Value }

# Fields that hold booleans: uploads carry them as 1/0.
$booleans = @{}
foreach ($n in @("matched", "ok", "connected", "retry", "scanning", "stored", "reliable", "displayOnly",
        "withResponse", "chunksWithResponse", "authenticated", "bonded", "null", "ready", "reading",
        "needsRefresh", "sha256", "aes128", "targetQueued", "inFlight", "profilesReady", "restart",
        "changed", "savedKeyCleared", "pairingEnabled", "keyPersisted", "complete", "unpaired", "covered", "resend", "match")) { $booleans[$n] = $true }

function Get-FieldName([string]$field) {
    # 'name="const"' -> name; '"text"' -> text; name -> name
    if ($field.StartsWith('"')) { return $null }
    $eq = $field.IndexOf('=')
    if ($eq -gt 0) { return $field.Substring(0, $eq) }
    return $field
}

function Format-Record([string]$code, [string]$rest) {
    $entry = $table[$code]
    if ($null -eq $entry) { return "?$code $rest" }
    $values = @()
    if ($rest.Length -gt 0) { $values = $rest.Split(':') }
    $variants = @($entry.variants)
    $chosen = $variants[0]
    foreach ($v in $variants) {
        if (@($v).Count -eq $values.Count) { $chosen = $v; break }
    }
    $fields = @($chosen)
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add([string]$entry.event)
    for ($i = 0; $i -lt $values.Count; $i++) {
        $name = $null
        if ($i -lt $fields.Count) { $name = Get-FieldName ([string]$fields[$i]) }
        if ($i -ge $fields.Count) { $parts.Add("+" + $values[$i]) }
        elseif ($null -eq $name) { $parts.Add($values[$i]) }
        else {
            $v = $values[$i]
            if ($booleans.ContainsKey($name)) {
                if ($v -eq "1") { $v = "true" } elseif ($v -eq "0") { $v = "false" }
            }
            $parts.Add($name + "=" + $v)
        }
    }
    return ($parts -join " ")
}

$anchorTimer = $null
$anchorClock = $null
$timer = $null
$out = New-Object System.Collections.Generic.List[string]
foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
    if ($line -match '^@(\d+) (\d{6})(?: (\d+))?$') {
        $first = [int64]$Matches[1]
        $clock = [TimeSpan]::new([int]$Matches[2].Substring(0, 2), [int]$Matches[2].Substring(2, 2), [int]$Matches[2].Substring(4, 2))
        if ($Matches[3]) {
            # upload: the clock was read at the later timer
            $clock = $clock - [TimeSpan]::FromMilliseconds([int64]$Matches[3] - $first)
        }
        $anchorTimer = $first
        $anchorClock = $clock
        $timer = $first
        $out.Add("# anchor watch timer $first")
        continue
    }
    if ($line -match '^(\d+)([A-Z][A-Z0-9])(.*)$') {
        $delta = [int64]$Matches[1]
        $text = Format-Record $Matches[2] $Matches[3]
        if ($null -ne $timer) {
            $timer += $delta
            $wall = $anchorClock + [TimeSpan]::FromMilliseconds($timer - $anchorTimer)
            $wall = [TimeSpan]::FromMilliseconds(($wall.TotalMilliseconds % 86400000 + 86400000) % 86400000)
            $out.Add(("[G7] {0:hh\:mm\:ss\.fff}+{1} {2}" -f $wall, $timer, $text))
        } else {
            $out.Add(("[G7] +{0}ms {1}" -f $delta, $text))
        }
        continue
    }
    $out.Add($line)
}

if ($OutFile) {
    [System.IO.File]::WriteAllLines($OutFile, $out, (New-Object System.Text.UTF8Encoding($false)))
} else {
    $out
}
