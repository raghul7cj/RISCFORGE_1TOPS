# =============================================================================
# RISCFORGE 1TOPS — Dual-Runner SoC Regression Script (run_regression.ps1)
# =============================================================================
# Supports:
#   - Local Windows Flow: AMD Vivado XSim (xvlog / xelab / xsim)
#   - Remote EDA Server : Synopsys VCS via plink/pscp
#
# VACUITY POLICY
#   A stage counts as PASSED only if ALL of the following hold:
#     1. the firmware ELF was actually produced by the compiler;
#     2. the simulator was actually launched (not merely "prepared");
#     3. the simulator exited with code 0;
#     4. the log contains the positive-activity evidence line
#        "[MAILBOX PASS]" or "[STAGE2 PASS]";
#     5. the log contains NO vacuity violation, fatal, or mailbox-fail line.
#   A stage that cannot be compiled or simulated is reported as BLOCKED and
#   fails the regression. It is never counted as a pass, and it is never
#   silently skipped.
# =============================================================================

param(
    [string]$Target = "local",       # "local" (Vivado XSim) or "remote" (VCS)
    [string]$Suite  = "all",         # "all" or specific test e.g. "stage1_hello"
    [string]$BootMode = "WARM",      # "WARM" or "COLD"
    [int]$Timeout = 1000000,         # TB watchdog limit in cycles
    [string]$XsimRoot = "C:\Xilinx\Vivado\2022.2\bin"
)

$ErrorActionPreference = "Stop"
$RootDir  = Resolve-Path "$PSScriptRoot\..\.."
$VerifDir = "$RootDir\Verification"
$TestsDir = "$VerifDir\tests\suites"
$BuildDir = "$VerifDir\build"
$InfraDir = "$VerifDir\infrastructure"
$ToolDir  = "$VerifDir\regression"

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

# Resolve a real CPython. `python` on this host resolves to the Microsoft Store
# alias stub (C:\Users\cj\AppData\Local\Microsoft\WindowsApps\python.exe), which
# exits 9009 without running anything -- so an unqualified `python` made the hex
# conversion step fail for reasons that had nothing to do with the DUT.
$PyExe = $null
foreach ($cand in @(
    (Get-Command py       -ErrorAction SilentlyContinue).Source,
    (Get-Command python   -ErrorAction SilentlyContinue).Source,
    "C:\Users\cj\AppData\Local\Programs\Python\Python312\python.exe",
    "C:\Users\cj\AppData\Local\Programs\Python\Python313\python.exe"
)) {
    if ($cand -and (Test-Path -LiteralPath $cand)) {
        $probe = & $cand -c "import sys;print(sys.version_info[0])" 2>$null
        if ($LASTEXITCODE -eq 0 -and $probe) { $PyExe = $cand; break }
    }
}
if (-not $PyExe) {
    Write-Host "  [FATAL] no working Python interpreter found (py / python / Python312)" -ForegroundColor Red
    exit 2
}
Write-Host "  Python : $PyExe"

$testList = @(
    "stage1_hello",
    "stage2_watchdog",
    "stage3_monitor_count",
    "stage4_fault_inject",
    "stage5_reg_sweep",
    "stage6_polled_periph",
    "stage7_nested_irq"
)
if ($Suite -ne "all") { $testList = @($Suite) }

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "               RISCFORGE SoC Verification Regression Runner                     " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  Target Simulator : $Target"
Write-Host "  Boot Mode        : $BootMode"
Write-Host "  Tests            : $($testList -join ', ')"
Write-Host "================================================================================`n"

$results = @{}

# --- One-time local compile + elaborate (shared snapshot for all stages) -----
# The elaborated snapshot is stage-independent (firmware arrives via hex files
# at run time), so compiling once instead of per stage is both faster and more
# robust. $compileOk gates every local stage below.
$compileOk = $true
if ($Target -eq "local") {
    if (-not (Test-Path $XsimRoot)) {
        Write-Host "  [BLOCKED] XSim not found at $XsimRoot" -ForegroundColor Red
        $compileOk = $false
    } else {
        $env:PATH = "$XsimRoot;$env:PATH"
        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "  [XSIM] one-time compile + elaborate (shared snapshot for all stages)"
        Write-Host "--------------------------------------------------------------------------------"
        Push-Location $InfraDir
        try {
            # (notes 1-3: see the per-stage block history) `-sv` is a command
            # line switch; the list must be the GENERATED xsim dialect; both
            # steps use the same list.
            #
            # (note 4) Capture tool output into a VARIABLE, then filter. Piping
            # a Vivado .bat wrapper directly into Select-String/ForEach-Object
            # loses its exit code ($LASTEXITCODE reads 1 even on success).
            #
            # (notes 5-6) A stale snapshot's obj dir, and the transient
            # indexer/AV lock on xelab's freshly written obj files ("Could not
            # remove the obj directory ... used by another process" AFTER
            # "Built simulation snapshot"), both flip xelab's exit code despite
            # a good build. Drop the stale snapshot, let the filesystem settle
            # after the fresh compile, and retry elaboration with backoff.
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue xsim.dir/soc_sim_snap
            $xvlogOut = & xvlog --sv -f soc_verification.xsim.f --nolog 2>&1
            $xvlogExit = $LASTEXITCODE
            $xvlogOut | Select-String -Pattern "ERROR|error:" |
                ForEach-Object { Write-Host "      $_" }

            if ($xvlogExit -ne 0) {
                Write-Host "  [BLOCKED] xvlog failed (exit $xvlogExit)" -ForegroundColor Red
                $compileOk = $false
            } else {
                Write-Host "  [XSIM] compile ok; letting the filesystem settle before elaboration ..."
                Start-Sleep -Seconds 3
                $xelabExit = 1
                $xelabOut = @()
                for ($attempt = 1; $attempt -le 4 -and $xelabExit -ne 0; $attempt++) {
                    if ($attempt -gt 1) {
                        Write-Host "  [XSIM] elaborate retry $attempt/4 ..." -ForegroundColor Yellow
                        Start-Sleep -Seconds 3
                        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue xsim.dir/soc_sim_snap
                    }
                    $elabT0 = Get-Date
                    $xelabOut = & xelab soc_tb_top -s soc_sim_snap --timescale 1ns/1ps --nolog 2>&1
                    $xelabExit = $LASTEXITCODE
                    # xelab prints "Built simulation snapshot" and then can STILL
                    # exit 1 when its post-build obj cleanup races a file
                    # indexer/AV scan ("Could not remove the obj directory").
                    # The snapshot itself (xsimk.exe) is complete in that case,
                    # so judge by artifact freshness, not the exit code alone.
                    $snapExe = "xsim.dir/soc_sim_snap/xsimk.exe"
                    if (($xelabOut -match "Built simulation snapshot") -and
                        (Test-Path $snapExe) -and
                        ((Get-Item $snapExe).LastWriteTime -ge $elabT0.AddSeconds(-5))) {
                        if ($xelabExit -ne 0) {
                            Write-Host "  [XSIM] snapshot built; ignoring post-build obj-cleanup exit code" -ForegroundColor Yellow
                        }
                        $xelabExit = 0
                    }
                }
                $xelabOut | Select-String -Pattern "ERROR|error:" |
                    ForEach-Object { Write-Host "      $_" }
                if ($xelabExit -ne 0) {
                    Write-Host "  [BLOCKED] elaborate failed after 4 attempts" -ForegroundColor Red
                    $dbgPath = "$BuildDir\elab_debug.log"
                    $xvlogOut | Out-File -FilePath $dbgPath -Encoding ASCII
                    "===== XELAB =====" | Out-File -FilePath $dbgPath -Encoding ASCII -Append
                    $xelabOut | Out-File -FilePath $dbgPath -Encoding ASCII -Append
                    Write-Host "  [DEBUG] full tool output in $dbgPath" -ForegroundColor Yellow
                    $compileOk = $false
                } else {
                    Write-Host "  [XSIM] elaborate ok -- snapshot soc_sim_snap ready" -ForegroundColor Green
                }
            }
        } finally {
            Pop-Location
        }
    }
}

foreach ($t in $testList) {
    Write-Host "--------------------------------------------------------------------------------"
    Write-Host "  $t" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------"

    $tDir = "$TestsDir\$t"
    if (-not (Test-Path "$tDir\main.c")) {
        Write-Host "  [BLOCKED] source not found: $tDir\main.c" -ForegroundColor Red
        $results[$t] = "BLOCKED"
        continue
    }

    $elfPath = "$BuildDir\$t.elf"
    $imemHex = "$BuildDir\${t}_imem.hex"
    $dmemHex = "$BuildDir\${t}_dmem.hex"
    $logPath = "$BuildDir\${t}_sim.log"

    # --- 1. Compile the firmware -------------------------------------------
    # The toolchain lives in WSL. WSL_FIRST is tried first because it is the
    # only place riscv64-unknown-elf-gcc is known to exist; a native Windows
    # toolchain is used as a fallback.
    $bsp = "$VerifDir\tests\bsp"
    $drv = "$VerifDir\tests\drivers"
    $srcs = @(
        "$bsp\crt0.s", "$bsp\trap_handler.s",
        "$bsp\isr_dispatch.c", "$bsp\proof_activity.c",
        "$drv\uart_driver.c", "$drv\timer_driver.c", "$drv\gpio_driver.c",
        "$drv\i2c_driver.c", "$drv\spi_driver.c",
        "$tDir\main.c"
    ) -join " "

    $gccArgs = @(
        "-march=rv32im_zicsr", "-mabi=ilp32", "-mcmodel=medlow", "-mno-relax",
        "-O2", "-g", "-ffreestanding", "-nostdlib",
        "-I`"$bsp`"", "-I`"$drv`"",
        "-T `"$bsp\link.ld`"", $srcs, "-o `"$elfPath`""
    ) -join " "

    # POSIX argument vector for the WSL invocation. Every path is RELATIVE to
    # $VerifDir, because `wsl --cd $VerifDir` already sets the working directory.
    # This is not cosmetic. Two separate quoting failures are being avoided:
    #   1. Windows backslashes are escape characters to bash, so the native form
    #      above collapses to `...RISCFORGE_1TOPS-mainrtlipsVerification...`.
    #   2. The absolute paths contain a SPACE ("1TOPS project"). wsl.exe re-parses
    #      its own command line using MSVCRT rules, which strips the embedded
    #      double quotes out of `-I"/mnt/c/.../1TOPS project/..."` and then splits
    #      on the space, so gcc sees a path truncated to `project/RISCFORGE...`.
    # Relative paths contain no spaces, need no quoting, and are immune to both.
    $srcsPosix = @("tests/bsp/crt0.s", "tests/bsp/trap_handler.s",
        "tests/bsp/isr_dispatch.c", "tests/bsp/proof_activity.c",
        "tests/drivers/uart_driver.c", "tests/drivers/timer_driver.c",
        "tests/drivers/gpio_driver.c", "tests/drivers/i2c_driver.c",
        "tests/drivers/spi_driver.c", "tests/suites/$t/main.c")
    $gccArgsPosix = ((@(
        "-march=rv32im_zicsr", "-mabi=ilp32", "-mcmodel=medlow", "-mno-relax",
        "-O2", "-g", "-ffreestanding", "-nostdlib",
        "-Itests/bsp", "-Itests/drivers",
        "-T tests/bsp/link.ld"
    ) + $srcsPosix) + @("-o build/$t.elf")) -join " "

    $built = $false
    if (Get-Command riscv64-unknown-elf-gcc -ErrorAction SilentlyContinue) {
        Write-Host "  [GCC] native toolchain"
        Remove-Item -Force -EA SilentlyContinue $elfPath
        & riscv64-unknown-elf-gcc $gccArgs 2>&1 | ForEach-Object { Write-Host "      $_" }
        $built = Test-Path $elfPath
    }
    if (-not $built) {
        $wslPath = ($VerifDir -replace '^([A-Za-z]):', '/mnt/$1') -replace '\\', '/'
        Write-Host "  [GCC] WSL toolchain fallback"
        # The previous form was:  wsl ... bash -lc "cd '$wslPath' && ..."
        # `$wslPath` contains a SPACE ("1TOPS project"), and `bash -lc` receives
        # the whole string as ONE argv element, so the inner single quotes are
        # literal characters, not shell quoting -- `cd` therefore failed with
        #   bash: line 1: cd: /mnt/C/.../1TOPS project/...: No such file or
        # directory
        # ...but the stale `build/<stage>.elf` committed to the repo was still
        # sitting there, so `Test-Path $elfPath` returned TRUE and the stage was
        # reported as having "compiled". That is a silent vacuity: the image
        # under test was never rebuilt from the current C sources.
        # Fix: let wsl.exe do the chdir itself with --cd (it translates the
        # Windows path itself and quotes correctly), remove any stale ELF from
        # the Windows side first, and require the ELF's mtime to advance.
        Remove-Item -Force -EA SilentlyContinue $elfPath
        $t0 = Get-Date
        & wsl -d Ubuntu --cd $VerifDir -- bash -lc "riscv64-unknown-elf-gcc $gccArgsPosix" 2>&1 |
            ForEach-Object { Write-Host "      $_" }
        $wslExit = $LASTEXITCODE
        if (Test-Path $elfPath) {
            $built = ((Get-Item $elfPath).LastWriteTime -ge $t0.AddSeconds(-2)) -and ($wslExit -eq 0)
            if (-not $built) {
                Write-Host "      [STALE] $elfPath was NOT rebuilt (wsl exit $wslExit) - refusing to count it" -ForegroundColor Red
            }
        }
    }

    if (-not $built) {
        Write-Host "  [BLOCKED] firmware did not compile" -ForegroundColor Red
        $results[$t] = "BLOCKED"
        continue
    }

    # --- 2. Convert ELF to $readmemh images --------------------------------
    & $PyExe "$ToolDir\elf_to_hex_clean.py" $elfPath $imemHex $dmemHex 2>&1 |
        ForEach-Object { Write-Host "  [HEX] $_" }
    if (-not (Test-Path $imemHex)) {
        Write-Host "  [BLOCKED] hex conversion produced no image" -ForegroundColor Red
        $results[$t] = "BLOCKED"
        continue
    }

    # --- 3. Run the simulation for real ------------------------------------
    if ($Target -eq "local") {
        if (-not $compileOk) {
            Write-Host "  [BLOCKED] shared snapshot unavailable -- compile/elaborate failed" -ForegroundColor Red
            $results[$t] = "BLOCKED"
            continue
        }
        Copy-Item -Force $imemHex "$InfraDir\imem.hex"
        Copy-Item -Force $dmemHex "$InfraDir\dmem.hex"

        Write-Host "  [XSIM] running shared snapshot"
        Push-Location $InfraDir
        try {
            $logPath = "$BuildDir\${t}_sim.log"
            # xsim.exe (2022.2) does not accept bare `+PLUSARG` tokens on its
            # command line ("Expected a switch but found +"); plus args must
            # ride `--testplusarg`, one switch per arg.
            # Output is captured to a variable first (see note 4 above) so the
            # simulator's real exit code survives.
            $xsimOut = & xsim soc_sim_snap -R -log $logPath 2>&1
            $simExit = $LASTEXITCODE
            $xsimOut | ForEach-Object { Write-Host "      $_" }
        } finally {
            Pop-Location
        }
    }
    else {
        Write-Host "  [VCS] remote execution via run_vcs.sh"
        & bash "$VerifDir\run_vcs.sh" $t $BootMode $Timeout 2>&1 |
            ForEach-Object { Write-Host "      $_" }
        $simExit = $LASTEXITCODE
        $logPath = "$BuildDir\${t}_sim.log"
    }

    # --- 4. Judge the log, not the exit code alone --------------------------
    $verdict = "FAILED"
    if ($simExit -eq 0 -and (Test-Path $logPath)) {
        $log = Get-Content $logPath -Raw
        $hasPass    = ($log -match "\[MAILBOX PASS\]") -or ($log -match "\[STAGE2 PASS\]")
        $hasVacuity = ($log -match "VACUITY VIOLATION") -or ($log -match "FATAL VACUOUS")
        $hasFail    = ($log -match "\[MAILBOX FAIL\]") -or ($log -match "FATAL TIMEOUT") -or
                      ($log -match "\[MAILBOX HALT\]") -or ($log -match "FAILURE REPORT")
        if ($hasPass -and -not $hasVacuity -and -not $hasFail) {
            $verdict = "PASSED"
        } else {
            Write-Host "  [VERDICT] rejected: pass=$hasPass vacuity=$hasVacuity fatal=$hasFail" -ForegroundColor Red
        }
    } else {
        Write-Host "  [VERDICT] simulator exit code $simExit (log present: $(Test-Path $logPath))" -ForegroundColor Red
    }

    $results[$t] = $verdict
    if ($verdict -eq "PASSED") {
        Write-Host "  -> $verdict" -ForegroundColor Green
    } else {
        Write-Host "  -> $verdict" -ForegroundColor Red
    }
}

# --- Summary --------------------------------------------------------------
$pass  = @($results.Values | Where-Object { $_ -eq "PASSED" }).Count
$fail  = @($results.Values | Where-Object { $_ -eq "FAILED" }).Count
$block = @($results.Values | Where-Object { $_ -eq "BLOCKED" }).Count

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "                         REGRESSION SUMMARY                                     " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
foreach ($k in ($results.Keys | Sort-Object)) {
    $colour = switch ($results[$k]) { "PASSED" { "Green" } "BLOCKED" { "Yellow" } default { "Red" } }
    Write-Host ("  {0,-22} {1}" -f $k, $results[$k]) -ForegroundColor $colour
}
Write-Host "--------------------------------------------------------------------------------"
Write-Host "  Total : $($results.Count)   Passed : $pass   Failed : $fail   Blocked : $block" -ForegroundColor White
Write-Host "================================================================================`n"

# Non-zero exit unless everything passed. A blocked stage is a failure of the
# regression, because "we could not check it" is not "it is fine".
if ($fail -gt 0 -or $block -gt 0) { exit 1 } else { exit 0 }
