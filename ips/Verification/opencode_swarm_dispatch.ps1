# =============================================================================
# RISCFORGE SoC Verification — OpenCode Swarm Delegation Script
# =============================================================================
# Transfers the /teamwork-preview multi-agent workflow to the local OpenCode
# web server (http://127.0.0.1:4096) utilizing dynamically discovered free-tier models.
# =============================================================================

$ErrorActionPreference = "Stop"
$ServerUrl = "http://127.0.0.1:4096"

Write-Host "=== RISCFORGE SoC Verification: OpenCode Swarm Dispatch ===" -ForegroundColor Cyan
Write-Host "Connecting to OpenCode server at: $ServerUrl"

# 1. Inspect active free models
try {
    $provData = Invoke-RestMethod -Uri "$ServerUrl/provider" -ErrorAction Stop
} catch {
    Write-Error "Failed to connect to OpenCode server at $ServerUrl. Make sure 'opencode web' is running."
    exit 1
}

$conn = $provData.connected
$freeChatModels = @()

foreach ($p in $provData.all) {
    if ($conn -contains $p.id) {
        foreach ($prop in $p.models.PSObject.Properties) {
            $m = $prop.Value
            $hasTextOut = ($null -eq $m.capabilities) -or ($m.capabilities.output.text -eq $true)
            $isFree = ($m.id -like "*-free") -or ($m.cost.input -eq 0 -and $m.cost.output -eq 0)
            $isEmbedding = ($m.id -like "*embed*") -or ($m.id -like "*rerank*") -or ($m.id -like "*whisper*") -or ($m.id -like "*flux*") -or ($m.id -like "*bge*") -or ($m.id -like "*esm*") -or ($m.id -like "*tts*") -or ($m.id -like "*detector*") -or ($m.id -like "*voice*")
            
            if ($isFree -and $hasTextOut -and (-not $isEmbedding)) {
                $freeChatModels += [PSCustomObject]@{
                    ProviderID = $p.id
                    ModelID    = $m.id
                    Name       = $m.name
                }
            }
        }
    }
}

Write-Host "Discovered $($freeChatModels.Count) active free model(s)." -ForegroundColor Green
$selected = $freeChatModels | Where-Object { $_.ModelID -in @("space-bunny-free", "nemotron-3.5-lightning-free", "mimo-v2.6-flash-free") } | Select-Object -First 1
if (-not $selected) { $selected = $freeChatModels[0] }

Write-Host "Selected Model for Swarm: $($selected.Name) [$($selected.ModelID)] (Provider: $($selected.ProviderID))`n" -ForegroundColor Yellow

# 2. Define the Teamwork Swarm Roles & Tasks
$ContextPrefix = @"
[RISCFORGE SoC-Level Verification Infrastructure Context]
Repository Root: c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips
Target Architecture: RISC-V RV32IM_Zicsr 5-Stage Core in riscforge_soc_subsystem.sv
Integration Guide: Verification/SoC Verification Infrastructure_ Integration Guide.html
Architecture Guide: documentation/RISCFORGE SoC Architecture.html
Interrupt Architecture: documentation/RISCFORGE IRQ Architecture.html
Master Project Tracking: .agents/teamwork/orchestrator_1/PROJECT.md

Status of Implemented Infrastructure:
1. Peripheral Drivers (Verification/tests/drivers/): uart_driver, timer_driver, gpio_driver, i2c_driver, spi_driver with state recovery.
2. Peripheral BFMs (Verification/infrastructure/vip/): gpio_pin_vip.sv, spi_flash_s25fs512s.sv, i2c_eeprom_at24c02.sv, uart_pin_vip.sv.
3. Passive Monitors (Verification/infrastructure/monitors/): rf_monitors.sv (1,166 lines) implementing Fetch, Retire (RVFI), LSU, AXI4-Lite, APB 6-Slot, IRQ, Pin monitors with 256-entry circular freeze ring buffers.
4. Top & Probe Interface (Verification/infrastructure/tb/): tb_pkg.sv, rf_monitor_if.sv, rf_mon_probe.sv, soc_tb_top.sv.
5. Checkers & Reference Models (Verification/infrastructure/checkers/):
   - mmio_path_scoreboard.sv (End-to-end LSU -> AXI -> APB routing reference model)
   - register_predictor.sv (Independent shadow mirror for all 6 APB IPs: RW reset states, W1C status, atomic SET/CLEAR/TOGGLE, UART DLAB banking)
   - irq_predictor.sv (Independent 2-level priority arbiter Class 2 > Class 1 > Class 0, gateway pulse capture, 2-deep shadow stack)
   - failure_reporter.sv (7-layer hierarchical first-fatal blame engine and freeze broadcast)
6. Smoke Self-Test Status: Verification/infrastructure/run_rf_mon_smoke.ps1 executed and PASSED 38/38 checks in AMD Vivado XSim 2022.2.

Remaining Work Scope:
- Milestone 2: Hardening fault injection matrix in Verification/step4_checkers/ (decoupling forwarder and fixing bridge model).
- Milestone 4: Dual simulator regression scripts (XSim local Windows & VCS remote server).
- Milestone 5: Bare-metal 7-stage proof suites (stage1_hello to stage7_nested_irq) with zero vacuous passes.
"@

$SwarmTasks = @(
    @{
        Name = "Swarm-Orchestrator"
        Prompt = "$ContextPrefix`n`nROLE: Swarm Project Orchestrator`nTASK: Review the project architecture in .agents/teamwork/orchestrator_1/PROJECT.md and synthesize an execution plan to coordinate the completion of Milestones 2, 4, and 5 across the swarm. Specify clear inputs, outputs, and verification exit criteria for each worker."
    },
    @{
        Name = "M2-Checker-Worker"
        Prompt = "$ContextPrefix`n`nROLE: Milestone 2 Checker & SVA Engineer`nTASK: Inspect Verification/step4_checkers/step4_axi_sva.sv, step4_apb_sva.sv, step4_path_scoreboard.sv, and step4_hub.sv. Formulate the exact fix for the ev_q forwarder to eliminate multi-driver races on hub.evt_w and ensure every fault injection case in step4_smoke_tb.sv names the correct check ID."
    },
    @{
        Name = "M4-Regression-Harness-Worker"
        Prompt = "$ContextPrefix`n`nROLE: Milestone 4 Dual-Simulator Build Engineer`nTASK: Inspect Verification/infrastructure/soc_verification.prj and RTL_SOC/soc_subsystem.f. Resolve the include file paths for local AMD Vivado XSim on Windows vs remote VCS on Linux so that both run_regression.ps1 and run_vcs.sh elaborate the entire SoC subsystem cleanly."
    },
    @{
        Name = "M5-Proof-Suite-Worker"
        Prompt = "$ContextPrefix`n`nROLE: Milestone 5 Bare-Metal Proof Suite Engineer`nTASK: Inspect Verification/tests/suites/ stages 1 through 7. Provide detailed bare-metal C test implementations ensuring that each proof stage asserts positive hardware activity (total_retired_instr > 0 and bus beats > 0) to prevent any vacuous pass."
    },
    @{
        Name = "Swarm-Forensic-Auditor"
        Prompt = "$ContextPrefix`n`nROLE: Independent Forensic Auditor`nTASK: Cross-examine the current verification infrastructure against 'Verification/SoC Verification Infrastructure_ Integration Guide.html'. Audit the 7 layers of blame absorption, ring buffer freezing, and reference model coverage to identify any remaining compliance gaps."
    }
)

# 3. Dispatch to OpenCode Server
Write-Host "Dispatching $($SwarmTasks.Count) parallel agents to OpenCode..." -ForegroundColor Cyan

$DispatchedSessions = @()

foreach ($task in $SwarmTasks) {
    $sesBody = @{ title = $task.Name } | ConvertTo-Json
    $ses = Invoke-RestMethod -Uri "$ServerUrl/session" -Method Post -Body $sesBody -ContentType 'application/json'
    
    $promptBody = @{
        model = @{
            providerID = $selected.ProviderID
            modelID    = $selected.ModelID
        }
        tools = @{
            question = $false
        }
        parts = @(
            @{
                type = "text"
                text = $task.Prompt
            }
        )
    } | ConvertTo-Json -Depth 5
    
    $null = Invoke-RestMethod -Uri "$ServerUrl/session/$($ses.id)/prompt_async" -Method Post -Body $promptBody -ContentType 'application/json'
    Write-Host "  -> [DISPATCHED] $($task.Name) (Session ID: $($ses.id))" -ForegroundColor Green
    
    $DispatchedSessions += [PSCustomObject]@{
        Name      = $task.Name
        SessionId = $ses.id
    }
}

$DispatchedSessions | Export-Clixml -Path "Verification/opencode_swarm_sessions.xml"
Write-Host "`nAll agents successfully dispatched in parallel to OpenCode Web Server!" -ForegroundColor Cyan
Write-Host "Active session records saved to Verification/opencode_swarm_sessions.xml"
