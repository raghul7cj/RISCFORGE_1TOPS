<#
    run_step4.ps1 -- build and run the Step 4 checker package (Vivado xsim)

    Usage (from this directory):
        .\run_step4.ps1
        .\run_step4.ps1 -Coverage          # also write a code-coverage report
        .\run_step4.ps1 -HaltOnFirstFatal  # pass +step4_halt=1 through

    Order matters in step4_sim.f: xsim does not make SystemVerilog packages
    visible across files in one invocation, so step4_pkg.sv has to precede every
    file that imports it.

    What counts as a pass, all four:
      1. the disassembler self-test passed
      2. phase1_findings == 0       no check fires on clean traffic
      3. phase1_traffic_ok         the checkers actually saw traffic
      4. fi_fail == 0               every injected fault was named by the
                                    check ID it is supposed to name
    See STEP4_SPEC.md section 13.
#>
param(
  [switch]$Coverage,
  [switch]$HaltOnFirstFatal,
  [string]$Pcmap = ""
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)

$vivado = "C:\Xilinx\Vivado\2022.2\bin"
if (-not (Test-Path "$vivado\xvlog.bat")) { throw "Vivado not found at $vivado" }

function Step($name, $block) {
  Write-Host ""
  Write-Host ("=" * 74)
  Write-Host "  $name"
  Write-Host ("=" * 74)
  & $block
  # Only judge a step that ran an external command: a pure PowerShell block
  # leaves $LASTEXITCODE unset and "" -ne 0 is true, which fails every time.
  if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "$name failed (exit $LASTEXITCODE)"
  }
}

# ---------------------------------------------------------------- 0. clean ---
Step "0/5  Clean" {
  Remove-Item -Recurse -Force xsim.dir, xvlog.pb, xvlog.log -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force coverage      -ErrorAction SilentlyContinue
  Remove-Item -Force step4_report.txt       -ErrorAction SilentlyContinue
  Remove-Item -Force step4_run.tcl          -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------- 1. compile ---
Step "1/5  Compile (xvlog)" {
  $a = @("-sv", "-i", ".", "-f", "step4_sim.f")
  if ($Pcmap -ne "") { $a = @("-sv", "-i", ".", "+define+STEP4_PCMAP_FILE=`"$Pcmap`"", "-f", "step4_sim.f") }
  & "$vivado\xvlog.bat" @a
}

# ------------------------------------------------------------- helpers -------
# xsim writes through a console that inserts ANSI colour codes, so a pattern
# anchored at the start of a line never matches.  Strip them once and work on
# plain text.
function Get-Clean($out) { return ((($out | Out-String) -replace "`e\[[0-9;]*m", "")) }

# ------------------------------------------- 2. disassembler self-test -------
# Run first and on its own.  A disassembler that prints plausible-looking wrong
# output is worse than none: the reader trusts it and then debugs the wrong
# instruction.  Five such bugs were found writing it; this step is what keeps
# them fixed.
$script:disasmOk = $true
Step "2/5  Disassembler self-test" {
  & "$vivado\xelab.bat" step4_disasm_tb -s dec_tb
  $txt = Get-Clean (& "$vivado\xsim.bat" dec_tb -runall 2>&1)
  ($txt -split "`r?`n") | Select-String -Pattern "FAIL|passed,|RESULT" | ForEach-Object { $_.Line.Trim() }
  if ($txt -match "RESULT : FAIL") { $script:disasmOk = $false }
}

# ------------------------------------------------------- 3. checker proof ----
$script:fiFail = 1
$script:phase1 = $false
$script:traffic = $false
Step "3/5  Checker self-proof (xsim)" {
  & "$vivado\xelab.bat" step4_smoke_tb -s step4_sim --debug typical
  @"
  log_wave -r /step4_smoke_tb/u_br/*
  log_wave -r /step4_smoke_tb/u_sb/*
  run -all
  exit
"@ | Out-File -FilePath step4_run.tcl -Encoding ASCII

  $run = @("-runall")
  if ($HaltOnFirstFatal) { $run += "+step4_halt=1" }
  $txt = Get-Clean (& "$vivado\xsim.bat" step4_sim @run -tclbatch step4_run.tcl 2>&1)
  ($txt -split "`r?`n") | Select-String -Pattern "\[STEP4\]|SELF-PROOF|RESULT" | ForEach-Object { $_.Line.Trim() }
  if ($txt -match "PHASE 1 PASS")   { $script:phase1   = $true }
  if ($txt -match "PHASE 1 traffic") { $script:traffic = $true }
  if ($txt -match "fi_fail=0\b")     { $script:fiFail   = 0 }
}

# ------------------------------------------------------------ 4. verdict -----
Step "4/5  Verdict" {
  Write-Host ""
  Write-Host "  PASS requires all four:"
  Write-Host ("    1. disassembler self-test passed ............. {0}" -f $(if ($script:disasmOk) { "PASS" } else { "FAIL" }))
  Write-Host ("    2. no check fires on clean traffic ......... {0}" -f $(if ($script:phase1) { "PASS" } else { "FAIL" }))
  Write-Host ("    3. the checkers actually saw traffic ....... {0}" -f $(if ($script:traffic) { "PASS" } else { "FAIL (vacuous)" }))
  Write-Host ("    4. every injected fault named correctly ... {0}" -f $(if ($script:fiFail -eq 0) { "PASS" } else { "FAIL" }))
  if (Test-Path step4_report.txt) {
    Write-Host ""
    Write-Host "---------------- step4_report.txt (tail) ----------------"
    Get-Content step4_report.txt | Select-Object -Last 30
  }
  Write-Host ""
  Write-Host "A run with no findings but no traffic is NOT a pass. That is a vacuous"
  Write-Host "pass, and the reporter says so in as many words."
}

# -------------------------------------------------------- 5. coverage -------
if ($Coverage) {
  Step "5/5  Coverage" {
    @"
  run -all
  write_xsim_coverage
  exit
"@ | Out-File -FilePath step4_cov.tcl -Encoding ASCII
    & "$vivado\xsim.bat" step4_sim -runall --cov_db_dir . -cov_home_dir ./coverage -tclbatch step4_cov.tcl
    & "$vivado\xcrg.bat" -dir ./coverage -db_name work.step4_smoke_tb -report_dir ./coverage/report -report_format html
    Write-Host "coverage report: $((Resolve-Path ./coverage/report).Path)"
  }
}

if (-not ($script:disasmOk -and $script:phase1 -and $script:traffic -and ($script:fiFail -eq 0))) {
  Write-Host ""
  Write-Host "STEP 4 SELF-PROOF: NOT GREEN -- see STEP4_SPEC.md section 14."
  exit 1
}
Write-Host ""
Write-Host "STEP 4 SELF-PROOF: GREEN."