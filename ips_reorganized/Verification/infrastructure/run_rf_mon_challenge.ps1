# =============================================================================
# RISCFORGE 1TOPS — Run Empirical Challenge Suite (Vivado XSim 2022.2)
# Runs in private isolated directory chall_run to prevent agent directory collisions
# =============================================================================
$ErrorActionPreference = "Stop"
$env:PATH = "C:\Xilinx\Vivado\2022.2\bin;$env:PATH"

$CHALL_DIR = Join-Path $PSScriptRoot "chall_run"
if (-not (Test-Path $CHALL_DIR)) { New-Item -ItemType Directory -Path $CHALL_DIR | Out-Null }
Set-Location $CHALL_DIR

$SIM = "rf_mon_challenge_sim"

Write-Host "[1/3] xvlog (Empirical Challenge)..." -ForegroundColor Cyan
Remove-Item -Recurse -Force xsim.dir -ErrorAction SilentlyContinue
xvlog --sv -nolog -i .. -f rf_mon_challenge.f
if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

Write-Host "[2/3] xelab (Snapshot Linking)..." -ForegroundColor Cyan
xelab rf_mon_empirical_challenge_tb -s $SIM -v 1
if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

Write-Host "[3/3] xsim (Execution & Verification)..." -ForegroundColor Cyan
xsim $SIM -runall
if ($LASTEXITCODE -ne 0) { throw "simulation failed" }

Write-Host "`n[CHALLENGE HARNESS FINISHED SUCCESSFULLY]" -ForegroundColor Green
