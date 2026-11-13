param(
    [ValidateSet('smoke', 'offset', 'adjacent-store', 'negative-mepc', 'negative-return')]
    [string]$Case = 'smoke',
    [switch]$Final,
    [switch]$NoThrow
)
. "$env:USERPROFILE/.t3/tools/vlsi/Vlsi.ps1"
. "$PSScriptRoot/../../../scripts/vlsi/VlsiRun.ps1"
$manifestName = if ($Case -eq 'smoke') { 'core-trap-f1.json' } else { "core-trap-f1-$Case.json" }
Invoke-VlsiRun -Manifest "$PSScriptRoot/$manifestName" -Final:$Final -NoThrow:$NoThrow
