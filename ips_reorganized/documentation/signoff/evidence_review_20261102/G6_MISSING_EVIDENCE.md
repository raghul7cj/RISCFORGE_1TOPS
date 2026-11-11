# G6: recorded work and missing evidence

Review date: 2026-11-02. Entries describe inspected local assets; no new tool runs. Workbook blank means insufficient established evidence, not a claim that work was never performed. Done denotes completion of the exact item criterion only; coach approval and gate closure remain separate.

## 6.1 — UVM SoC testbench built

- Criterion: AXI master agent emulating CPU accesses, IRQ VIP, peripheral VIPs and coverage model
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: SV-based SoC verification infrastructure/plans exist; user reports SV-first approach.
- Evidence: [ips/Verification/soc_verification_plan.md](../../../../ips/Verification/soc_verification_plan.md)
- Missing evidence / remaining action: Complete required agents/VIPs/checkers/coverage. UVM was not recommended yet per user; no item-specific UVM waiver or recommendation is inferred.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.2 — Register tests pass

- Criterion: 100% of addressable registers read and written; RW/RO/W1C behaviour verified
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: SoC register-test source and infrastructure exist.
- Evidence: [ips/RTL_SOC/soc_regtest_tb.sv](../../../../ips/RTL_SOC/soc_regtest_tb.sv)
- Missing evidence / remaining action: Retain current all-register RW/RO/W1C results and complete register inventory; source presence is not 100% pass.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.3 — Register field coverage closed

- Criterion: Field-level functional coverage on enable and mode combinations met
- Required tool: VCS / Verdi
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No complete current SoC field-level enable/mode functional-coverage closure identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.4 — Per-IP use cases pass

- Criterion: TX and RX path exercised for each integrated peripheral against its VIP
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: Historical per-IP and staged datapath tests retained.
- Evidence: [ips/Verification/verification_matrix.csv](../../../../ips/Verification/verification_matrix.csv)
- Missing evidence / remaining action: Both TX/RX paths for each real integrated peripheral against its VIP/model, on current candidate.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.5 — Interrupt path verified end to end

- Criterion: Every source verified from peripheral event to controller input; masking and priority checked
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: Arbiter unit priority/masking/fairness evidence exists.
- Evidence: [ips/Verification/IRQ_UNIT_COVERAGE_PLAN.md](../../../../ips/Verification/IRQ_UNIT_COVERAGE_PLAN.md)
- Missing evidence / remaining action: Every real peripheral event through controller/core ISR path, with source/mask/priority mapping; unit snapshots do not close end-to-end verification.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.6 — Bus bridge protocol verified

- Criterion: AXI to AXI-Lite to APB: ordering, responses, alignment and byte enables correct
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: Standalone bridge/xbar and synthetic-aperture check results retained.
- Evidence: [ips/Verification/verification_matrix.csv](../../../../ips/Verification/verification_matrix.csv)
- Missing evidence / remaining action: Real current SoC path ordering/responses/alignment/byte enables and every mapped/unmapped range; resolve required bridge architecture difference.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.7 — Memory map decode verified

- Criterion: Every address range hit; unmapped access returns the defined error
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: Standalone bridge/xbar and synthetic-aperture check results retained.
- Evidence: [ips/Verification/verification_matrix.csv](../../../../ips/Verification/verification_matrix.csv)
- Missing evidence / remaining action: Real current SoC path ordering/responses/alignment/byte enables and every mapped/unmapped range; resolve required bridge architecture difference.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.8 — Traffic stress run

- Criterion: Long random peripheral traffic plus interrupts; no hangs, no protocol violations
- Required tool: VCS
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No qualified long random real-peripheral-plus-IRQ protocol/hang-free stress result identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.9 — Boot from internal ROM passes

- Criterion: Core fetches from ROM and reaches main()
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: ROM trampoline, SRAM loading and staged boot tests exist.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Retain full current SoC reaches-main evidence and applicable remap/continuation evidence; distinguish autonomous loading from strap-selected boot.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.10 — Boot from external SPI flash passes

- Criterion: Boot mode pin = 1: code fetched from the SPI flash model and executed
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: Flash loader component checks retained.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Full boot-mode-pin=1 flash-model fetch and execution or exact approved departure; component copy checks are insufficient.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.11 — SRAM load / ROM remap boot passes

- Criterion: If supported: SRAM loaded from flash, remap occurs and execution continues
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: ROM trampoline, SRAM loading and staged boot tests exist.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Retain full current SoC reaches-main evidence and applicable remap/continuation evidence; distinguish autonomous loading from strap-selected boot.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.12 — Bare-metal C test suite passes

- Criterion: Memory march and walking-ones, timer/SW/external interrupts, UART/SPI/GPIO loopbacks
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: Scoped C/ASM peripheral and timer datapath tests retained.
- Evidence: [ips/Verification/verification_matrix.csv](../../../../ips/Verification/verification_matrix.csv)
- Missing evidence / remaining action: Complete memory march/walking-ones, timer/software/external IRQ and UART/SPI/GPIO loopbacks on current full SoC.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.13 — Trap robustness under load passes

- Criterion: Interrupts during load/store/branch-dense code; nested interrupt policy exercised if supported
- Required tool: VCS
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No qualified current SoC interrupted-load/store/branch/trap/nesting robustness results identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.14 — SoC random and stress tests pass

- Criterion: Random arbitration, power-on reset sequences, interconnect backpressure and wait states
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: Stress runner exists.
- Evidence: [ips/Verification/infrastructure/run_freeze_stress.ps1](../../../../ips/Verification/infrastructure/run_freeze_stress.ps1)
- Missing evidence / remaining action: Retain qualified full-SoC arbitration/reset/backpressure/wait-state randomized results; a runner is not a clean stress result.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.15 — SoC functional coverage closed

- Criterion: Address map, interrupt sources and boot modes all covered
- Required tool: VCS / Verdi
- Workbook status: In Progress
- Recorded work: Component and scoped functional coverage evidence exists.
- Evidence: [ips/Verification/verification_matrix.csv](../../../../ips/Verification/verification_matrix.csv)
- Missing evidence / remaining action: Full-SoC address-map, every interrupt source and all approved boot modes coverage closure.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.16 — SoC code coverage >= 95%

- Criterion: Statement, branch and toggle with written waivers
- Required tool: VCS / Verdi
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No current full-SoC statement/branch/toggle >=95% report with written waivers identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.17 — Full regression clean

- Criterion: Directed, random and software suites: zero failures on the RTL handed to synthesis
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: Regression orchestration exists.
- Evidence: [ips/Verification/regression/run_regression.ps1](../../../../ips/Verification/regression/run_regression.ps1)
- Missing evidence / remaining action: Zero-failure directed/random/software full suite on the exact RTL delivered to synthesis, accepted tool and manifest identity.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.18 — No deadlocks in long runs

- Criterion: Long-run test completes; no unbounded stalls
- Required tool: VCS
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No qualified current-candidate long-run completion and bounded-stall evidence identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 6.19 — RTL frozen for synthesis

- Criterion: Repo tagged; later changes need coach approval and a full regression re-run
- Required tool: Git
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No demonstrated synthesis release tag with clean full regression and approved freeze/change procedure.
- Owner, closure date and item-specific coach approval: not established; left blank.

