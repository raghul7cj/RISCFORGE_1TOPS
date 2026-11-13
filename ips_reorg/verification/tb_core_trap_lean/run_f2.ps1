param(
    [ValidateSet('all', 'illegal', 'ebreak', 'load', 'store', 'negative-mtval')]
    [string]$Case = 'all',
    [switch]$Final,
    [switch]$NoThrow
)
. "$env:USERPROFILE/.t3/tools/vlsi/Vlsi.ps1"
. "$PSScriptRoot/../../../scripts/vlsi/VlsiRun.ps1"
$cases = if ($Case -eq 'all') { @('illegal', 'ebreak', 'load', 'store') } else { @($Case) }
$runResults = foreach ($selectedCase in $cases) {
    Invoke-VlsiRun -Manifest "$PSScriptRoot/core-trap-f2-$selectedCase.json" -Final:$Final -NoThrow
}
$runResults
if (-not $NoThrow -and @($runResults | Where-Object { -not $_.success }).Count -gt 0) {
    throw 'F2 includes a failed or incomplete case; all results were retained.'
}
