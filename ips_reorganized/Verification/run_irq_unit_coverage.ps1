param(
    [string]$VivadoBin = 'C:\Xilinx\Vivado\2022.2\bin'
)
$ErrorActionPreference = 'Stop'
$verificationDir = $PSScriptRoot
$ipsDir = Split-Path $verificationDir -Parent
$runDir = Join-Path $verificationDir ('artifacts\irq_unit_coverage_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $runDir | Out-Null
Write-Host "Evidence: $runDir"
$sources = @(
    (Join-Path $verificationDir 'tb_irq_restructure.sv'),
    (Join-Path $ipsDir 'riscv_core\rtl\irq_gateway.v'),
    (Join-Path $ipsDir 'riscv_core\rtl\irq_arbiter.v'),
    (Join-Path $ipsDir 'riscv_core\rtl\csr_regfile.v'),
    (Join-Path $ipsDir 'riscv_core\rtl\wb_trap_mret_commit_controller.v')
)
Push-Location $runDir
try {
    & (Join-Path $VivadoBin 'xvlog.bat') -sv @sources -log compile.log
    if ($LASTEXITCODE -ne 0) { throw 'xvlog compilation failed' }
    & (Join-Path $VivadoBin 'xelab.bat') tb_irq_restructure -s irq_unit_sim -cov_db_name irq_unit -cc_type sbct -cc_db irq_unit -log elaborate.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab elaboration failed' }
    & (Join-Path $VivadoBin 'xsim.bat') irq_unit_sim -runall -log simulation.log
    if ($LASTEXITCODE -ne 0 -or -not (Select-String -Quiet -Path simulation.log -Pattern 'PASS: 196608 arbitration snapshots')) {
        throw 'Simulation failed or did not reach the PASS marker; inspect simulation.log'
    }
    & (Join-Path $VivadoBin 'xcrg.bat') -dir . -db_name irq_unit -report_dir functional_report -report_format all -log functional_report.log
    if ($LASTEXITCODE -ne 0) { throw 'Functional coverage report generation failed' }
    & (Join-Path $VivadoBin 'xcrg.bat') -cc_db irq_unit -cc_dir . -cc_report code_report -log code_report.log
    if ($LASTEXITCODE -ne 0) { throw 'Code coverage report generation failed; functional data and code database are retained' }
} finally {
    Pop-Location
}
