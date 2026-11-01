# =============================================================================
# RISCFORGE 1TOPS — Sandbox Regression Runner (PowerShell Entry Point)
# =============================================================================
# Forwards execution cleanly to Verification/regression/run_regression.py

param(
    [string]$Test          = "tb_irq_arbiter",
    [string]$Tier          = "all",
    [string]$Simulator     = "xsim",
    [int]$TimeoutCycles    = 1000000,
    [int]$WallClockTimeout = 180
)

$PSScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunnerPy    = Join-Path $PSScriptDir "run_regression.py"

py -3 $RunnerPy --test $Test --tier $Tier --simulator $Simulator --timeout-cycles $TimeoutCycles --wall-timeout $WallClockTimeout
exit $LASTEXITCODE
