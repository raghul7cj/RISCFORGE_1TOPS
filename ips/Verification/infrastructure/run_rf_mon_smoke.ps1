# =============================================================================
# RISCFORGE 1TOPS - Monitor layer self-test (Vivado XSim 2022.2)
# =============================================================================
#   .\run_rf_mon_smoke.ps1
#
# Elaborates and runs tb/rf_mon_smoke_tb.sv against tb/rf_mon_stub_dut.sv, then
# asserts the monitor layer is non-vacuous and that the shared cycle counter,
# the cyclic ring buffers and the LSU -> AXI -> APB join all work. Run this
# after ANY change to tb_pkg.sv / rf_monitor_if.sv / rf_monitors.sv /
# rf_monitor_env.sv / rf_mon_probe.sv.
#
# Remote equivalents (VCS on 172.16.33.48, Xcelium on 172.16.33.51):
#   vcs   -sverilog -full64 -timescale=1ns/1ps -f rf_mon_smoke.f -top rf_mon_smoke_tb
#   xrun  -sv -timescale 1ns/1ps -f rf_mon_smoke.f -top rf_mon_smoke_tb
# =============================================================================

$ErrorActionPreference = "Stop"
$env:PATH = "C:\Xilinx\Vivado\2022.2\bin;$env:PATH"
Set-Location $PSScriptRoot

$SIM = "rf_mon_smoke_sim"

Write-Host "[1/3] xvlog ..."  -ForegroundColor Cyan
Remove-Item -Recurse -Force xsim.dir -ErrorAction SilentlyContinue
xvlog --sv -nolog -f rf_mon_smoke.f
if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

Write-Host "[2/3] xelab ..." -ForegroundColor Cyan
xelab rf_mon_smoke_tb -s $SIM
if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

Write-Host "[3/3] xsim ..."  -ForegroundColor Cyan
xsim $SIM -runall
if ($LASTEXITCODE -ne 0) { throw "simulation failed" }

if (Test-Path "monitor_postmortem.txt") {
    Write-Host "`n--- monitor_postmortem.txt (first 40 lines) ---" -ForegroundColor Yellow
    Get-Content "monitor_postmortem.txt" -TotalCount 40
}