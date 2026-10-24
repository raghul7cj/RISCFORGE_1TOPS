$ErrorActionPreference = "Stop"

$VivadoBin = "C:\Xilinx\Vivado\2022.2\bin"
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim  = Join-Path $VivadoBin "xsim.bat"

Write-Host "=== Compiling RISCFORGE Draft IRQ with xvlog ===" -ForegroundColor Cyan
& $xvlog -sv -f tb_smoke.f
if ($LASTEXITCODE -ne 0) {
    Write-Error "xvlog compilation failed!"
    exit $LASTEXITCODE
}

Write-Host "=== Elaborating Design with xelab ===" -ForegroundColor Cyan
& $xelab tb_smoke_irq -s sim_smoke -timescale 1ns/1ps -debug typical
if ($LASTEXITCODE -ne 0) {
    Write-Error "xelab elaboration failed!"
    exit $LASTEXITCODE
}

Write-Host "=== Running Simulation with xsim ===" -ForegroundColor Cyan
& $xsim sim_smoke -R
if ($LASTEXITCODE -ne 0) {
    Write-Error "xsim simulation failed!"
    exit $LASTEXITCODE
}
