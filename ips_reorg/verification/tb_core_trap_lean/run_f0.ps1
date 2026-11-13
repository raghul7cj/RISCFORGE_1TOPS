. "$env:USERPROFILE/.t3/tools/vlsi/Vlsi.ps1"
. "$PSScriptRoot/../../../scripts/vlsi/VlsiRun.ps1"
Invoke-VlsiRun -Manifest "$PSScriptRoot/core-trap-f0.json"
