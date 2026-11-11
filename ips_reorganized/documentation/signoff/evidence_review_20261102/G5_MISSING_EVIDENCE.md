# G5: recorded work and missing evidence

Review date: 2026-11-02. Entries describe inspected local assets; no new tool runs. Workbook blank means insufficient established evidence, not a claim that work was never performed. Done denotes completion of the exact item criterion only; coach approval and gate closure remain separate.

## 5.1 — ISS comparison flow working

- Criterion: Core log and Spike log compared automatically; a mismatch prints a clear fail
- Required tool: Spike / VCS
- Workbook status: In Progress
- Recorded work: Legacy architectural signature comparison selects Sail.
- Evidence: [verification/riscof/config.ini](../../../../verification/riscof/config.ini)
- Missing evidence / remaining action: Current automated Spike execution-log comparison and mismatch-fail demonstration are required by the unchanged criterion. Sail alone is not this deliverable.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 5.2 — Official RISC-V ISA tests pass

- Criterion: 100% pass on rv32ui, plus rv32um if M and rv32uc if C are supported
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: Legacy architecture-test report retained; one failure recorded.
- Evidence: [verification/riscof/report.html](../../../../verification/riscof/report.html)
- Missing evidence / remaining action: 100% applicable official ISA pass on the current candidate using the accepted simulator, with revision/run identity.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 5.3 — Privileged / trap tests pass

- Criterion: Minimal machine-mode trap and interrupt tests pass
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: Legacy privilege/Zicsr/misalignment test selection exists.
- Evidence: [verification/riscof/run_compliance.bat](../../../../verification/riscof/run_compliance.bat)
- Missing evidence / remaining action: Current machine-mode trap and interrupt tests with valid reference outputs and retained passing evidence.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 5.4 — riscv-dv integrated

- Criterion: Random instruction streams generate, compile and run against the core
- Required tool: riscv-dv / VCS
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No qualified current-core riscv-dv generate/compile/run evidence identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 5.5 — riscv-dv regression stable

- Criterion: N seeds run with a stable pass rate; N agreed with coach (typical 1k-10k)
- Required tool: riscv-dv / VCS
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No coach-agreed N and retained stable seeded current-core riscv-dv campaign identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 5.6 — Memory latency randomisation run

- Criterion: Random grant and response delays; flush and backpressure stress passes
- Required tool: VCS
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No qualified current-core randomized memory grant/response/flush/backpressure campaign identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 5.7 — Benchmarks run

- Criterion: Dhrystone and/or CoreMark complete with correct results; score recorded
- Required tool: VCS
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No qualified correct-result Dhrystone/CoreMark run with recorded score identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 5.8 — Functional coverage closed at core level

- Criterion: Instruction, hazard and protocol delay-bucket coverage goals all met
- Required tool: VCS / Verdi
- Workbook status: In Progress
- Recorded work: Scoped IRQ arbiter functional coverage exists.
- Evidence: [ips/Verification/IRQ_UNIT_COVERAGE_PLAN.md](../../../../ips/Verification/IRQ_UNIT_COVERAGE_PLAN.md)
- Missing evidence / remaining action: Whole-core instruction, hazard and protocol-delay-bin closure; unit IRQ coverage is insufficient.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 5.9 — Code coverage >= 95% on core

- Criterion: Statement, branch and toggle; every exclusion has a written waiver
- Required tool: VCS / Verdi
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No current whole-core statement/branch/toggle >=95% report with justified exclusions identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 5.10 — Core bug list closed

- Criterion: All P0/P1 bugs fixed and re-verified; open P2/P3 listed with justification
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Defect/status register exists, including fixed-unverified findings.
- Evidence: [ips/Verification/status/PHASE_STATUS.md](../../../../ips/Verification/status/PHASE_STATUS.md)
- Missing evidence / remaining action: Reverify all P0/P1 fixes on final RTL; list and justify open P2/P3 defects.
- Owner, closure date and item-specific coach approval: not established; left blank.

