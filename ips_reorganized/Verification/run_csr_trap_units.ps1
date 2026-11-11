param(
    [string]$VivadoBin = 'C:\Xilinx\Vivado\2022.2\bin',
    [ValidateSet('csr_corner_unit', 'core_csr_trap', 'both')]
    [string]$Bench = 'both'
)
$ErrorActionPreference = 'Stop'

$verificationDir = $PSScriptRoot
$ipsDir = Split-Path $verificationDir -Parent
$runDir = Join-Path $verificationDir ('artifacts\csr_trap_units_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $runDir | Out-Null
Write-Host "Evidence: $runDir"

# Filelist -> list of source paths relative to rtl/ips (simulator options stripped).
function Get-FilelistSources {
    param([string]$Filelist)

    $sources = foreach ($line in Get-Content $Filelist) {
        $entry = ($line -split '//')[0].Trim()
        if ($entry -match '\.(sv|v)$') { $entry }
    }
    return $sources
}

function Invoke-Bench {
    param(
        [string]$Name,
        [string]$Filelist,
        [string]$Top,
        [string]$EvidenceDir,
        [string]$PassPattern,
        [string]$PassDescription
    )

    $workDir = Join-Path $EvidenceDir $Name
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    $sources = Get-FilelistSources -Filelist $Filelist
    if (-not $sources) { throw "$Name : no sources found in $Filelist" }
    Write-Host ("[{0}] {1} sources from {2}" -f $Name, $sources.Count, (Split-Path $Filelist -Leaf))

    $sourceList = Join-Path $workDir 'sources.f'
    $sources | ForEach-Object { '"' + (Join-Path $ipsDir $_).Replace('\', '/') + '"' } |
        Set-Content -Path $sourceList -Encoding ASCII

    Push-Location $workDir
    try {
        & (Join-Path $VivadoBin 'xvlog.bat') -sv -i (Join-Path $ipsDir 'riscv_core\rtl') -f $sourceList -log compile.log
        if ($LASTEXITCODE -ne 0) { throw "$Name : xvlog compilation failed; inspect compile.log" }

        & (Join-Path $VivadoBin 'xelab.bat') -debug typical -timescale 1ns/1ps -s $Name -log elaborate.log "work.$Top"
        if ($LASTEXITCODE -ne 0) { throw "$Name : xelab elaboration failed; inspect elaborate.log" }

        @('run all', 'quit') | Set-Content -Path run.tcl -Encoding ASCII
        & (Join-Path $VivadoBin 'xsim.bat') $Name -tclbatch run.tcl -onerror quit -onfinish quit -log simulation.log
        if ($LASTEXITCODE -ne 0) { throw "$Name : xsim returned $LASTEXITCODE; inspect simulation.log" }
        if (-not (Select-String -Quiet -Path simulation.log -Pattern $PassPattern)) {
            throw "$Name : $PassDescription marker '$PassPattern' missing; inspect simulation.log"
        }
    } finally {
        Pop-Location
    }

    $summary = Select-String -Path (Join-Path $workDir 'simulation.log') -Pattern 'UNIT_DONE|UNIT_CHECK_FAIL|OBSERVED_COVERAGE|SKELETON|Core corner environment' |
        ForEach-Object { $_.Line.Trim() }
    Write-Host "[$Name] $PassDescription"
    $summary | ForEach-Object { Write-Host "  $_" }
}

$benchmarks = @{
    csr_corner_unit = @{
        Filelist        = Join-Path $verificationDir 'filelists\tier1_unit\tb_csr_corner_unit.f'
        Top             = 'tb_csr_corner_unit'
        PassPattern     = 'UNIT_DONE\|checks=\d+\|failures=0\|'
        PassDescription = 'directed checks completed with zero failures'
    }
    core_csr_trap   = @{
        Filelist        = Join-Path $verificationDir 'filelists\tier1_unit\tb_core_csr_trap.f'
        Top             = 'tb_core_csr_trap'
        PassPattern     = 'Core corner environment:'
        PassDescription = 'skeleton lifecycle completed (reset-held, no stimulus yet)'
    }
}

$selected = if ($Bench -eq 'both') { @('csr_corner_unit', 'core_csr_trap') } else { @($Bench) }

foreach ($name in $selected) {
    $spec = $benchmarks[$name]
    Invoke-Bench -Name $name -Filelist $spec.Filelist -Top $spec.Top -EvidenceDir $runDir `
        -PassPattern $spec.PassPattern -PassDescription $spec.PassDescription
}

# Source hashes make it unambiguous which bench revision produced these logs.
$tracked = @(
    'Verification\infrastructure\tb\tb_csr_corner_unit.sv',
    'Verification\infrastructure\tb\tb_core_csr_trap.sv',
    'Verification\infrastructure\tb\csr_trap\csr_corner_if.sv',
    'Verification\infrastructure\tb\csr_trap\core_corner_if.sv',
    'Verification\infrastructure\tb\csr_trap\csr_trap_coverage_pkg.sv',
    'Verification\infrastructure\tb\csr_trap\csr_trap_types_pkg.sv',
    'Verification\infrastructure\tb\csr_trap\csr_trap_env_pkg.sv',
    'Verification\filelists\tier1_unit\tb_csr_corner_unit.f',
    'Verification\filelists\tier1_unit\tb_core_csr_trap.f',
    'riscv_core\rtl\csr_regfile.v'
)
$hashes = foreach ($relative in $tracked) {
    $path = Join-Path $ipsDir $relative
    if (Test-Path $path) {
        '{0}  {1}' -f (Get-FileHash $path -Algorithm SHA256).Hash.ToLower(), ($relative -replace '\\', '/')
    }
}
$hashes | Set-Content -Path (Join-Path $runDir 'source_sha256.txt') -Encoding ASCII

Write-Host "Logs and hashes: $runDir"
