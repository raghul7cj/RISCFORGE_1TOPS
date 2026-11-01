# =============================================================================
# RISCFORGE SoC Verification — Master Orchestrator Swarm Dispatch
# =============================================================================
# Launches the Master Orchestrator on the local OpenCode server (port 4096)
# using space-bunny-free with maximum analytical reasoning effort (xhigh).
# =============================================================================

$ErrorActionPreference = "Stop"
$ServerUrl = "http://127.0.0.1:4096"

Write-Host "=== Dispatching Master Orchestrator to OpenCode (space-bunny-free xhigh) ===" -ForegroundColor Cyan

# 1. Verify OpenCode server
try {
    $provData = Invoke-RestMethod -Uri "$ServerUrl/provider" -ErrorAction Stop
} catch {
    Write-Error "OpenCode server not running at $ServerUrl"
    exit 1
}

$ModelId = "space-bunny-free"
$ProviderId = "opencode"

# 2. Read optimized prompt draft
$PromptText = Get-Content -LiteralPath "C:\Users\cj\.gemini\antigravity\brain\ffc7042e-04ee-40f9-843f-6a8490147673\prompt_draft.md" -Raw

$FullPrompt = @"
[SYSTEM DIRECTIVE: REASONING EFFORT: XHIGH / MAXIMUM CHAIN-OF-THOUGHT DEPTH]
You are the Master Verification Orchestrator for the RISCFORGE SoC project.
All previously missing peripheral and register interface sources are now confirmed fixed.
Your mission is to perform end-to-end verification, apply the forensic audit recommendations, and execute the full 7-stage bare-metal proof regression.

$PromptText

### IMMEDIATE ACTIONS REQUIRED:
1. Verify the newly fixed file tree in RTL_SOC/soc_subsystem.f and Verification/infrastructure/soc_verification.prj.
2. Incorporate the M2 decoupled mailbox fix into step4_hub.sv and step4_reporter.sv to resolve forwarder race conditions.
3. Validate that the newly implemented register_predictor.sv and irq_predictor.sv elaborate cleanly with soc_tb_top.sv.
4. Execute run_regression.ps1 in AMD Vivado XSim and report exact pass/fail verdicts for stages 1 through 7 with zero vacuous passes.
"@

# 3. Create Session and Dispatch
$sesBody = @{ title = "Master-Orchestrator-Signoff" } | ConvertTo-Json
$ses = Invoke-RestMethod -Uri "$ServerUrl/session" -Method Post -Body $sesBody -ContentType 'application/json'

$promptBody = @{
    model = @{
        providerID = $ProviderId
        modelID    = $ModelId
    }
    tools = @{
        question = $false
    }
    parts = @(
        @{
            type = "text"
            text = $FullPrompt
        }
    )
} | ConvertTo-Json -Depth 5

$null = Invoke-RestMethod -Uri "$ServerUrl/session/$($ses.id)/prompt_async" -Method Post -Body $promptBody -ContentType 'application/json'

Write-Host "Master Orchestrator successfully launched!" -ForegroundColor Green
Write-Host "Session ID: $($ses.id)" -ForegroundColor Yellow

# Record session
$rec = [PSCustomObject]@{
    Name       = "Master-Orchestrator-Signoff"
    SessionId  = $ses.id
    LaunchedAt = (Get-Date).ToString("o")
    Model      = $ModelId
    Effort     = "xhigh"
}
$rec | Export-Clixml -Path "Verification/master_orchestrator_session.xml"
