$ErrorActionPreference = "Stop"
$env:PATH = "C:\Xilinx\Vivado\2022.2\bin;$env:PATH"
Set-Location $PSScriptRoot

$SIM = "freeze_stress_sim"

Write-Host "[1/3] xvlog ..." -ForegroundColor Cyan
Remove-Item -Recurse -Force xsim.dir -ErrorAction SilentlyContinue
xvlog --sv -nolog -f freeze_stress.f
if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

Write-Host "[2/3] xelab ..." -ForegroundColor Cyan
xelab tb_freeze_buffer_stress -s $SIM
if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

Write-Host "[3/3] xsim ..." -ForegroundColor Cyan
xsim $SIM -runall
if ($LASTEXITCODE -ne 0) { throw "simulation failed" }
