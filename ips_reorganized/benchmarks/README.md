# RISCFORGE SoC benchmarks

A separate bare-metal benchmark environment for the current full SoC. It builds actual CoreMark and Dhrystone workloads, starts them through the SoC's real instruction/data paths, and retains raw measurements and validation results. It also provides a small smoke program and a counter diagnostic.

Start with [the architecture diagram](docs/architecture.html), [the implementation plan](docs/PLAN.md), and [the result contract](contract.json). The detailed firmware and harness guides are [FIRMWARE.md](docs/FIRMWARE.md) and [HARNESS.md](docs/HARNESS.md).

The [deliverable and evidence index](docs/DELIVERABLES.md) records the actual outcomes and retained artifacts. The [known failures](docs/KNOWN_FAILURES.md) give the failing checks, trap PCs and the remaining diagnosis boundary.

## Measurement status

The current RTL exposes `mcycle/mcycleh` and `minstret/minstreth`. Read these machine CSRs explicitly; the `cycle/instret` aliases are not implemented in its read mux.

**Retirement counts and CPI remain unqualified.** The current MEM/WB entry can remain valid during a memory stall, while `minstret` increments on WB validity. The benchmark environment records diagnostic overlap instead of treating that signal as an independent retirement oracle. The documented MDU completion-validity concern also requires workload validation. This infrastructure does not change design RTL.

An engineering run and a compliant published benchmark score have different requirements. Preserve the validation result even if the selected benchmark fails. A short CRC-valid CoreMark run still does not meet the minimum published duration. See [the feasibility assessment](../Verification/plans/BENCHMARK_FEASIBILITY_2026-11-04.md).

## Layout

```text
benchmarks/
  contract.json       Shared, versioned firmware/TB result ABI
  firmware/           Startup, traps, runtime and diagnostic programs
  ports/              Benchmark-specific platform and validation glue
  vendor/             Pinned upstream source, hashes and licenses
  tb/                 Dedicated full-SoC benchmark top
  filelists/          Benchmark manifest referencing the original design
  tools/              Fetch, build, file-list, simulation and analysis commands
  tests/              Host-side positive and negative checks
  docs/               Guides, architecture, review and evidence records
  build/              Generated firmware and simulator products (ignored)
  runs/               Per-run evidence and logs (ignored)
```

## Quick start on this workstation

Run these PowerShell commands from the workspace root. The wrapper builds with WSL Python/GCC and runs XSim with Windows Python. Supply `-ToolBin` if Vivado is installed elsewhere.

```powershell
# Verify the vendored source hashes without network access.
.\ips\benchmarks\benchmark.ps1 -Action CheckSources

# Build and run the diagnostic smoke image on the full SoC.
.\ips\benchmarks\benchmark.ps1 -Action All -Benchmark smoke

# The counter probe currently completes; arithmetic smoke currently fails validation.
.\ips\benchmarks\benchmark.ps1 -Action All -Benchmark counter_probe

# Check host-side preflight and result handling.
.\ips\benchmarks\benchmark.ps1 -Action Test

# A short benchmark run; this is not a published score.
.\ips\benchmarks\benchmark.ps1 -Action All -Benchmark coremark -Iterations 1 -TimeoutCycles 2000000
```

Use `-Action Build` to stop after firmware generation and `-Action Run` to run an already built image. `-Iterations` selects the firmware build count; an existing image keeps the iteration count in its build metadata. `-Waves` requests a waveform from the simulator runner. The wrapper returns an error when a build, simulation, or result check fails. Build and run evidence locations are printed by the underlying tools.

`-Action FetchSources` downloads the pinned source files and verifies them against the retained lock. It is intended for restoring missing vendor files; ordinary builds can use the offline source copies. See the individual tools' `--help` and the detailed guides for Linux VCS/Xcelium commands and direct Python use.

## Memory and execution

Instructions are linked at ISRAM `0x00010000` (32 KiB). Data SRAM begins at `0x00020000` (32 KiB), with the first 256 bytes reserved for the result block and the stack descending from `0x00028000`. Read-only constants belong in data SRAM because they are accessed through the data port.

The testbench preloads SRAM after warm-reset synchronization and then releases the core. The program executes through the actual SoC design. Bootstrap, initialization, console output and final validation remain outside the benchmark timing interval where required by the benchmark. The phase marker is a diagnostic window; it does not make separately executed CSR reads simultaneous.

The testbench owns a distinct completion protocol. It does not reuse or relax the existing SoC regression's peripheral-activity requirements. A firmware PASS must also have a consistent result header, zero validation errors, no unexpected trap, no watchdog expiry and no TB failure.

## Tools

The checked local setup has WSL GCC 13.2.0 with RV32IM/ILP32 support and Windows Vivado XSim 2022.2. The WSL compiler has matching `libgcc`, but a full C library was not established. The benchmark ports therefore supply minimal freestanding support.

Build flags select `-march=rv32im_zicsr -mabi=ilp32` explicitly. No compressed or floating-point ISA support is assumed. Dhrystone compilation and string-function policy must be recorded with its results. A separately selected RV32I/software-arithmetic configuration, if used, is a different measurement.

Do not compare host simulator wall time to target CPU cycles. The default simulated clock is 100 MHz; that frequency is a testbench setting, not achieved silicon Fmax.

## Evidence to keep

Keep the ELF, linker map, disassembly, SRAM images, input hashes, compiler/simulator identity, exact commands, console, raw result block, validation outcome and failure reason. Each run should use its own output directory. Missing or stale output must fail the run.

Static firmware size does not establish dynamic stack safety. Compilation does not establish execution. A completed simulation does not establish benchmark validation, counter qualification, gate closure, or a published score. The final deliverable record identifies the actual checks performed for this implementation.
