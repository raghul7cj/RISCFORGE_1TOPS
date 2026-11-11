# G0: recorded work and missing evidence

Review date: 2026-11-02. Entries describe inspected local assets; no new tool runs. Workbook blank means insufficient established evidence, not a claim that work was never performed. Done denotes completion of the exact item criterion only; coach approval and gate closure remain separate.

## 0.1 — Front-end tools installed and licensed

- Criterion: VCS, Verdi, SpyGlass, DC/Fusion Compiler and Tessent all launch and run a hello-world case
- Required tool: Synopsys / Siemens/ Cadence
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No retained complete approved front-end launch/license/hello-world bundle for all named tools.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 0.2 — Back-end tools installed and licensed

- Criterion: Innovus, PrimeTime, Conformal LEC, Calibre and Voltus all launch
- Required tool: Cadence / Synopsys / Siemens
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No retained complete approved backend launch/license bundle for all named tools.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 0.3 — RISC-V GNU toolchain installed

- Criterion: riscv32-*-elf-gcc compiles and links a bare-metal hello-world
- Required tool: riscv-gnu-toolchain
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No identified current compile-and-link toolchain demonstration; firmware/source presence alone does not establish this criterion.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 0.4 — Spike ISS built for your ISA

- Criterion: Spike runs an rv32ui test and produces an execution log
- Required tool: Spike ISS
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No retained Spike rv32ui execution-log demonstration identified; legacy RISCOF selects Sail.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 0.5 — 28 nm PDK, standard cells, SRAM macros and IO library received

- Criterion: Library files open in DC and Innovus without errors
- Required tool: DC / Innovus
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No identified accepted 28 nm PDK/cells/SRAM/IO load evidence in DC and Innovus.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 0.6 — Version control in place

- Criterion: All RTL, TB, scripts, constraints and docs in one repo; tagged at every gate
- Required tool: Git
- Workbook status: In Progress
- Recorded work: Repository audit and source layout exist.
- Evidence: [ips/Verification/signoff/README.md](../../../../ips/Verification/signoff/README.md)
- Missing evidence / remaining action: Verify all required assets tracked, current branch/commit/dirty state, and gate tags.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 0.7 — Regression runnable by one command

- Criterion: 'make regress' or equivalent runs the full sim suite and prints a pass/fail summary
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: Regression entry point exists.
- Evidence: [ips/Verification/regression/run_regression.ps1](../../../../ips/Verification/regression/run_regression.ps1)
- Missing evidence / remaining action: Retain one accepted-tool full-suite invocation, reliable failures and final summary on the selected RTL.
- Owner, closure date and item-specific coach approval: not established; left blank.

