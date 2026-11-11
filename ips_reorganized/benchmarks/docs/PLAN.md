# Benchmark infrastructure plan

Date: 2026-11-04. Requested scope: plan, implement, review, and document a separate benchmark environment using Luna agents at xhigh. Design RTL fixes are outside this task.

## Architecture decisions

Use `ips/benchmarks/` as the only new infrastructure root. Firmware, ports, vendor sources, TB, generated file lists, tools, tests, and documentation have separate homes. Refer to the existing SoC design sources rather than keeping benchmark copies of the RTL.

Instantiate `riscforge_soc_subsystem` as the DUT. Preserve the BootROM, SRAM timing, core, memory router, fabric, peripheral blocks and reset synchronizers. Hold unused external inputs idle. Backdoor preload is setup only: firmware executes real instruction/data paths after synchronized warm reset release.

Use an explicit 256-byte result block at DSRAM base, reserved by the benchmark linker script. `contract.json` defines field order and terminal status. This environment has its own completion contract, so existing verification mailbox checks and required peripheral activity are unchanged. A terminal firmware PASS must also pass testbench and host checks.

Use raw 64-bit machine CSR snapshots. Capture cycles and instructions separately, declare the read order, and exclude output and validation from the measured workload. `minstret` and derived CPI remain unqualified because current WB validity can repeat during stalls. Testbench diagnostics report this overlap; they are not an independent architectural retirement oracle.

Keep upstream computational sources pinned and identify all platform adaptations. Compile explicit RV32IM_Zicsr/ILP32 with no compressed or floating-point extension. A small freestanding runtime avoids an unverified libc dependency. A software-arithmetic RV32I build, if provided, is a separate configuration and cannot stand in for RV32IM validation.

## Implementation sequence

1. Establish shared result ABI and identify local tools/design manifests.
2. Build firmware/runtime and both benchmark ports; separately implement the full SoC TB, design-reference file lists, result analyzer and runner.
3. Compile all firmware images and the full TB. Run smoke, counter diagnostic, and short benchmark cases. Preserve build, trap, validation and timeout failures. Do not alter RTL or expected results to obtain PASS.
4. Run host negative tests for incomplete/corrupt/failed evidence and source-file preflight. Obtain a separate Luna xhigh review of the implementation and evidence; fix infrastructure issues and rerun affected checks.
5. Finish README, firmware/harness guides, deliverable/evidence index, and self-contained HTML with the TB architecture diagram.

## Acceptance boundaries

- Firmware compilation establishes toolchain compatibility and static memory fit, not target execution.
- TB compilation/elaboration establishes hierarchy and interface compatibility, not benchmark correctness.
- Smoke completion establishes that the new transport and program path work for that firmware.
- CoreMark CRC / Dhrystone final-state validation establish only the corresponding workload result on that source/tool/configuration.
- Counter liveness does not establish unique retirement accounting or exact measurement boundaries.
- Short RTL runs produce engineering measurements. They cannot be reported as a compliant published CoreMark score.
- Existing qualified-tool and coach-approval requirements remain separate from this engineering setup.

## Review ownership

Initial architecture inspection, firmware implementation, harness implementation, and final independent review are separate T3 child tasks, all requested as `gpt-6-luna` with `reasoningEffort=xhigh`. The parent integrates the interfaces, runs final checks, and records decisions/evidence. Each review round uses a new delegated task and includes unresolved findings from prior rounds.
