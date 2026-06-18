# ==========================================================
# CSR Testbench Runner
# RISCFORGE CSR Verification
# ==========================================================

$ErrorActionPreference = "Stop"

# ----------------------------------------------------------
# Paths
# ----------------------------------------------------------

$VivadoBin = "C:\Xilinx\Vivado\2022.2\bin"

$TbDir  = "C:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\rv32im_zicsr_5stage_exc_nointr\verif\tb_csr"

$RtlDir = "C:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\rv32im_zicsr_5stage_exc_nointr"

Set-Location $TbDir

Write-Host ""
Write-Host "========================================="
Write-Host " CSR TESTBENCH RUNNER"
Write-Host "========================================="
Write-Host ""

# ----------------------------------------------------------
# Cleanup
# ----------------------------------------------------------

Write-Host "[1/4] Cleaning previous simulation files..."

$cleanupItems = @(
    "xsim.dir",
    "xsim.covdb",
    "coverage_report",
    "xvlog.log",
    "xelab.log",
    "xvlog.pb",
    "xelab.pb",
    "sim.log",
    "xsim.jou"
)

foreach ($item in $cleanupItems)
{
    if (Test-Path $item)
    {
        Remove-Item $item -Recurse -Force
    }
}

Write-Host "Cleanup complete."
Write-Host ""

# ----------------------------------------------------------
# Compile
# ----------------------------------------------------------

Write-Host "[2/4] Running XVLOG..."

& "$VivadoBin\xvlog.bat" `
    -sv `
    -i ../common `
    ../../csr_regfile.v `
    csr_tb_top.sv

if ($LASTEXITCODE -ne 0)
{
    Write-Host ""
    Write-Host "XVLOG FAILED"
    exit $LASTEXITCODE
}

Write-Host "XVLOG PASSED"
Write-Host ""

# ----------------------------------------------------------
# Elaborate
# ----------------------------------------------------------

Write-Host "[3/4] Running XELAB..."

& "$VivadoBin\xelab.bat" `
    -debug typical `
    -top csr_tb_top `
    -snapshot csr_sim_snap

if ($LASTEXITCODE -ne 0)
{
    Write-Host ""
    Write-Host "XELAB FAILED"
    exit $LASTEXITCODE
}

Write-Host "XELAB PASSED"
Write-Host ""

# ----------------------------------------------------------
# Simulate
# ----------------------------------------------------------

Write-Host "[4/4] Running XSIM..."

& "$VivadoBin\xsim.bat" `
    csr_sim_snap `
    -R `
    -log sim.log

if ($LASTEXITCODE -ne 0)
{
    Write-Host ""
    Write-Host "XSIM FAILED"
    exit $LASTEXITCODE
}

Write-Host "XSIM PASSED"
Write-Host ""

# ----------------------------------------------------------
# Coverage
# ----------------------------------------------------------

Write-Host "Generating coverage report..."

& "$VivadoBin\xcrg.bat" `
    -report_format html `
    -dir xsim.covdb `
    -report_dir coverage_report

Write-Host ""
Write-Host "========================================="
Write-Host " RUN COMPLETE"
Write-Host "========================================="
Write-Host ""