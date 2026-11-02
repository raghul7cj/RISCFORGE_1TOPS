# Malay SoC integration into verification_infra — implementation candidate

**Working branch:** `integration/malay-soc-vinfra-irq-20261102`
**Reference commits:** verification_infra `2fedb8320c3b010bbba8dddc56e4ecdf8b7fb031`; malay `42752af75a5e6bb7579f578e354e589f1c320d2a`.
**Authority:** verification_infra CPU, 13-source gateway/arbiter, mintprio CSR, trap/MRET and multicycle abort/restart; malay SoC reset filtering, instruction memory and timer enable-qualified interrupts.

## Changes made in this candidate

1. `RTL_SOC/riscforge_soc_subsystem.sv`: malay hardware revision with synchronized, filtered soft reset (default 16 qualifying cycles); restore verification_infra's correct interrupt-priority documentation and keep all 13 source connections untouched.
2. `apb_timer-master/rtl/timer.sv`: malay enable qualification for overflow/compare IRQs. Disabled timers must not interrupt or auto-clear on a matching value.
3. `instr_module/Instruction_Memory.v`: malay registered-address/read-array implementation. Timing, read/write collision behavior and FPGA resource inference need checking.
4. Add a focused timer regression and filelist; this is test source, not a recorded PASS.

**Explicitly unchanged**: `riscv_core/rtl/top.v`, `csr_regfile.v`, `irq_gateway.v`, `irq_arbiter.v`, `execute_cycle.v`, `rv32m_div.v`, `rv32m_unit.v`, `hazard_unit.v`, `memory_cycle.v`, `wb_trap_mret_commit_controller.v`. Their current behavior must not be overwritten by malay's older encoder/CSR/divider control.

## Acceptance before merging into verification_infra

- Run `Verification/filelists/validate_filelists.py` and the current canonical P0 manifest checks.
- Compile/elaborate `Verification/filelists/tier3_soc/soc_verification.f` with the chosen simulator, zero unresolved modules and duplicate packages.
- Run `Verification/filelists/tier1_unit/tb_timer_enable_guard.f` and existing timer suite; retain logs.
- Run warm and cold boot. **Potential reset sequencing regression**: the new filter initially resets high and takes time to recognize a held-low soft reset after hard reset release. Check the warm-boot preloading handshake and SRAM preservation explicitly.
- Run instruction SRAM directed read/write, first-instruction-after-reset, one-cycle fetch, read-during-write, and memory-mapped firmware tests.
- Exercise all 13 actual SoC IRQ sources with core gateway/arbiter, including masks, threshold, event capture, and commit-only RR advancement.
- Run an interrupt during DIV/DIVU/REM/REMU and MUL: confirm exactly one committed trap, no partial write, mepc equals interrupted instruction PC, MRET replays instruction and matches uninterrupted result. Verify FlushM/stallMUL interaction before treating preemption as correct.
- Update obsolete monitor/predictor assumptions (6-bit gateway, hardware shadow stack) and firmware nested frame/acknowledgement before claiming full end-to-end verification.
- Recreate new source SHA and run manifests; **never** rewrite the frozen historical P0 SHA/evidence to imply prior PASS for new sources.

## Status

**Code integrated for first three RTL deltas; no simulation, formal equivalence, or synthesis executed by this change.** The release remains a **draft** until the verification gates above are completed.
