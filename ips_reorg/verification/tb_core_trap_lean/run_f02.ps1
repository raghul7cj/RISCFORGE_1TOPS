param(
    [ValidateSet('zero', 'wait', 'wait-one', 'wb-wait', 'negative-hold', 'negative-flush')]
    [string]$Case = 'wait',
    [switch]$Final,
    [switch]$NoThrow
)
. "$env:USERPROFILE/.t3/tools/vlsi/Vlsi.ps1"
. "$PSScriptRoot/../../../scripts/vlsi/VlsiRun.ps1"
Invoke-VlsiRun -Manifest "$PSScriptRoot/core-trap-f02-$Case.json" -Final:$Final -NoThrow:$NoThrow
