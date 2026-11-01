# =============================================================================
# RISCFORGE — Run Core Interrupt Verification (tb1_interrupts) via Vivado XSim
# =============================================================================

$VIVADO_BIN = "C:\Xilinx\Vivado\2022.2\bin"
if (-not (Test-Path "$VIVADO_BIN\xvlog.bat")) {
    Write-Host "[WARN] Vivado 2022.2 not found at default path ($VIVADO_BIN). Using PATH environment."
    $XVLOG = "xvlog"
    $XELAB = "xelab"
    $XSIM  = "xsim"
} else {
    $XVLOG = "$VIVADO_BIN\xvlog.bat"
    $XELAB = "$VIVADO_BIN\xelab.bat"
    $XSIM  = "$VIVADO_BIN\xsim.bat"
}

# 1. Generate Hex Test Programs
Write-Host "`n[STEP 1] Generating Hex test files..." -ForegroundColor Cyan
py gen_tb1_hex.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Python hex generation failed!" -ForegroundColor Red
    exit 1
}

# 2. Compile SystemVerilog Files
Write-Host "`n[STEP 2] Compiling with xvlog..." -ForegroundColor Cyan
& $XVLOG -sv -f tb1_interrupts.f -log xvlog.log
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] xvlog compilation failed! Check xvlog.log" -ForegroundColor Red
    exit 1
}

# 3. Elaborate Snapshot
Write-Host "`n[STEP 3] Elaborating with xelab..." -ForegroundColor Cyan
& $XELAB core_interrupt_tb -s core_interrupt_tb_sim -debug all -log xelab.log
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] xelab elaboration failed! Check xelab.log" -ForegroundColor Red
    exit 1
}

# 4. Run Simulation
Write-Host "`n[STEP 4] Running Simulation with xsim..." -ForegroundColor Cyan
& $XSIM core_interrupt_tb_sim -R -log xsim.log

Write-Host "`n[DONE] Simulation finished. See xsim.log for full output." -ForegroundColor Green
