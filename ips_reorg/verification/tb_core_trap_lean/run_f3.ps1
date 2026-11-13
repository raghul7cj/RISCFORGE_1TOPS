param(
    [ValidateSet('all', 'timer', 'timer-late', 'external', 'software', 'fast0', 'fast6', 'priority', 'negative-mepc')]
    [string]$Case = 'all',
    [switch]$Final,
    [switch]$NoThrow
)
. "$env:USERPROFILE/.t3/tools/vlsi/Vlsi.ps1"
. "$PSScriptRoot/../../../scripts/vlsi/VlsiRun.ps1"
$cases = if ($Case -eq 'all') { @('timer','timer-late','fast0','fast6','external','software','priority') } else { @($Case) }
$results = foreach ($selected in $cases) {
    Invoke-VlsiRun -Manifest "$PSScriptRoot/core-trap-f3-$selected.json" -Final:$Final -NoThrow
}
$results
if (-not $NoThrow -and @($results | Where-Object { -not $_.success }).Count -gt 0) {
    throw 'F3 requirements include failures; all case evidence was retained.'
}
