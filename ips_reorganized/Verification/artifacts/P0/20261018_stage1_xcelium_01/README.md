# Stage 1 Xcelium run — 2026-10-18

Verdict: BLOCKED / INCOMPLETE. Firmware built, but RTL compilation failed. Simulation never started. No Stage 1 PASS or P0 closure is claimed.

## Results

| Step | Result |
|---|---|
| Remote connection through saved PuTTY cadence_server proxy | PASS |
| Xcelium executable | 24.09-s001, 64-bit |
| RISC-V GCC | 16.1.0 (g6afcc4f6d) |
| Artifact write/read probe | PASS |
| Canonical filelist path preflight | PASS |
| Firmware link, with existing proof_activity.c included | PASS |
| ELF conversion | PASS: 1213 ISRAM words, 215 DSRAM words |
| RTL/TB compile and elaboration | BLOCKED: core top.v forward reference |
| Simulation / mailbox verdict / hardware counters | NOT RUN / unavailable |
| Full G0 and G1 | NOT SATISFIED |

## Blocking diagnostic

results/logs/elaborate_console.log records:

    xmvlog: *E,UNDIDN (.../riscv_core/rtl/top.v,236|42):
    'trap_commit_cause': undeclared identifier

The part-select `.wb_trap_cause_i (trap_commit_cause[4:0])` occurs at line 236; `wire [30:0] trap_commit_cause;` is declared at line 247. Xcelium rejects this ordering. Compiler language-option retries did not resolve it. A proposed RTL correction for the design owner to review is moving the existing declaration before its first use, without changing its width or connections. No RTL change was made during this run.

## Small verification changes

- Added an isolated run_stage1.py adapter in this evidence directory; shared run_vcs.sh and gen_filelists.py were not changed.
- Included the existing BSP proof_activity.c in the firmware build; initial link failure proved it was needed.
- Adapted only the generated run-local filelist: removed invalid $$define top metadata (top explicitly passed via -top), and FSDB define (no Verdi PLI/waveform integration).
- Moved cur_cycle and cur_rel_cycle declarations ahead of methods in Verification/infrastructure/monitors/rf_monitors.sv. Xcelium had reported undeclared identifiers. No monitor checks were disabled.
- Supplied the documented stock 16-word boot-ROM image in results/mem_files, so ../mem_files/riscforge_bootrom.hex resolves from results/work.
- No RTL design files or existing firmware drivers were edited. Hash comparison of all staged design sources is in checks/rtl_unchanged.txt; only the monitor differs from the initial snapshot.

## Attempts retained

| Directory | Outcome |
|---|---|
| attempt01_firmware_link_failure | Existing build recipe omitted proof_activity.c |
| attempt02_filelist_failure | Generated $$define metadata rejected |
| attempt03_adapter_failure | Literal metadata filter in the new adapter needed correction |
| attempt04_monitor_compile_failure | Class fields referenced before declaration; core error also present |
| attempt05_verilog_forward_reference | Monitor compile errors resolved; core forward reference remains |
| attempt06_language_option | First language-option retry, same core blocker |
| results | Final explicit extension-map retry, same core blocker |

Each attempt includes commands.json with argv, working directory, timeout, and exit code, plus logs and manifest.json. No failed attempt was overwritten. Simulator work databases were excluded from the downloaded evidence.

## Reproduction and identity

- Remote host: vlsi.iiita.ac.in, user iiita.
- Remote directory: /home/iiita/Documents/raghulcj/p0_runs/20261018_stage1_xcelium_01
- Scenario: stage1_hello; intended boot mode WARM; seed 1; watchdog 1,000,000 cycles; 100 MHz TB clock.
- Intended simulation arguments: +BOOT_MODE=WARM +IMEM_HEX=<absolute stage1_imem.hex> +DMEM_HEX=<absolute stage1_dmem.hex> +TIMEOUT=1000000. They were NOT executed because compilation failed.
- Environment: LM_LICENSE_FILE=5280@14.139.1.126, CDS_LIC_FILE=5280@14.139.1.126, CDS_AUTO_64BIT=ALL.
- inputs/source_snapshot.tar.gz is the frozen initial input tree; inputs/source_hashes.json records SHA-256 per file, including included headers and firmware support files.
- inputs/rf_monitors_xcelium.sv is the sole source overlay applied after the initial snapshot. The runner versions for earlier attempts are retained in inputs/runner_attempt*.py.
- results/manifest.json includes tool version, effective filelist SHA-256, ELF/image hashes, timestamps, and verdict.
- results/inputs/generated_original.f and xcelium.f retain original and effective generated lists. They contain the original absolute server paths; rerunning the generator adapts paths to a new directory.
- SHA-256(source_snapshot.tar.gz): ff04a54fe7b6baa11ba48666541350ce8899ad6c019c8713a3d98f2a5228f6d2
- SHA-256(evidence.tar.gz): 68df01b46549bdd478004b9492e2d086f3f54c98cf8b988e73e522ec859f7665
- These are snapshot and per-file identities, not a claim that the complete Rev B Table 21.10 identity procedure has been implemented.

Run REPRODUCE.sh in a NEW writable directory on the same Cadence host after copying this run folder there. It reconstructs the frozen input tree, applies the single monitor overlay, and invokes the retained runner. Do not run it over retained results. Exact original commands are in each attempt's commands.json. Authentication uses the existing PuTTY session; credentials are deliberately absent from run records.

## Follow-up after the compile blocker

1. Have the design owner review the declaration-order issue in top.v. Keep this blocked record intact and use a new run ID for corrected RTL.
2. Correct the testbench WARM sequence before claiming a warm boot result. Current TB asserts both resets and releases them together, while bootloader initializes warm_boot_q=0 on hard reset. It needs a distinct soft-reset interval long enough to be observed by the bootloader synchronizer, and preload after any initial clear writes. This issue was identified by reading code; it was not exercised or fixed in this blocked attempt.
3. Observe actual attestation writes and complete the reviewed canonical module comparison before claiming P0 exit. Current attestation value checks alone do not satisfy the explicit write-count goal.

No DUT activity counts are inferred from successful firmware compilation. No synthesis, timing, coverage, CDC/RDC, or broader functional sign-off is claimed.