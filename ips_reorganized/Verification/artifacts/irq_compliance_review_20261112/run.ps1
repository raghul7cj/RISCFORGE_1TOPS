$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
Push-Location $projectRoot
try {
    $compileOutput = & wsl --exec iverilog -g2012 -s tb_irq_compliance -o ips/Verification/artifacts/irq_compliance_review_20261112/sim.vvp ips/riscv_core/rtl/irq_gateway.v ips/riscv_core/rtl/irq_arbiter.v ips/riscv_core/rtl/csr_regfile.v ips/Verification/artifacts/irq_compliance_review_20261112/tb_irq_compliance.sv 2>&1
    $compileExit = $LASTEXITCODE
    [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'compile.log'), ($compileOutput -join "`n"))
    if ($compileExit -ne 0) { throw "Reproducer compilation failed: $compileExit" }
    $simulationOutput = & wsl --exec vvp ips/Verification/artifacts/irq_compliance_review_20261112/sim.vvp 2>&1
    $simulationExit = $LASTEXITCODE
    [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'simulation.log'), ($simulationOutput -join "`n"))
    [ordered]@{
        utc = [DateTime]::UtcNow.ToString('o')
        simulator = 'WSL Icarus Verilog 12.0 / vvp'
        scope = 'Real blocks, top-equivalent IRQ wiring; not full core or SoC execution'
        compile_exit = $compileExit
        simulation_exit = $simulationExit
        failing_checks = @($simulationOutput | Where-Object { "$_" -match '^\[FAIL\]' }).Count
        passing_checks = @($simulationOutput | Where-Object { "$_" -match '^\[PASS\]' }).Count
        verdict = 'FAIL: retained negative compliance evidence; no fix applied'
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'result.json') -Encoding utf8
    $simulationOutput
    if ($simulationExit -ne 0) { throw "Negative compliance result retained: simulator exit $simulationExit" }
} finally {
    Pop-Location
}

