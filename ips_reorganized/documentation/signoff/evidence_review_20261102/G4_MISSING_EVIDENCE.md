# G4: recorded work and missing evidence

Review date: 2026-11-02. Entries describe inspected local assets; no new tool runs. Workbook blank means insufficient established evidence, not a claim that work was never performed. Done denotes completion of the exact item criterion only; coach approval and gate closure remain separate.

## 4.1 — Unit TB for PC unit

- Criterion: All directed tests pass; code coverage reviewed
- Required tool: VCS / Verdi
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No qualified PC unit directed pass plus reviewed code-coverage evidence identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 4.2 — Unit TB for decoder / control

- Criterion: Directed test per opcode+funct combination passes; opcode x funct3 x funct7 cross coverage closed
- Required tool: VCS / Verdi
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No qualified complete opcode/funct decoder unit pass and cross-coverage closure identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 4.3 — Unit TB for register file

- Criterion: x0-write and same-cycle read/write tests pass
- Required tool: VCS / Verdi
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No qualified current register-file x0 and same-cycle read/write unit results identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 4.4 — Unit TB for ALU

- Criterion: Matches reference model; corners 0x8000_0000, 0x7FFF_FFFF, 0, -1 and shifts 0/1/31/>31 covered
- Required tool: VCS / Verdi
- Workbook status: In Progress
- Recorded work: Legacy ALU SV bench/checker assets exist.
- Evidence: [OLD files rtl-dv/verif/tb_alu](../../../../OLD%20files%20rtl-dv/verif/tb_alu)
- Missing evidence / remaining action: Port/review exact current ALU contract; run accepted-tool reference/corner checks and review measured code coverage.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 4.5 — Unit TB for branch unit

- Criterion: Full compare matrix passes; rs1<rs2, rs1=rs2, rs1>rs2 covered signed and unsigned
- Required tool: VCS / Verdi
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No qualified current branch-unit full signed/unsigned compare-matrix pass identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 4.6 — Unit TB for MDU

- Criterion: All M-extension funct3 ops covered including divide-by-zero; backpressure sequences pass
- Required tool: VCS / Verdi
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No qualified all-M-op/backpressure/divide-corner unit results identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 4.7 — Unit TB for MIU

- Criterion: All size x offset combinations and signed/unsigned loads covered
- Required tool: VCS / Verdi
- Workbook status: In Progress
- Recorded work: Legacy LSU bench/checkers and retained failure log exist.
- Evidence: [OLD files rtl-dv/verif/tb_lsu/README.md](../../../../OLD%20files%20rtl-dv/verif/tb_lsu/README.md)
- Missing evidence / remaining action: Resolve missing image/stall assertion history through current-contract investigation; demonstrate complete size/offset/sign coverage.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 4.8 — Unit TB for hazard logic

- Criterion: rs1, rs2 and both-operand hazards; ALU-to-use, LOAD-to-use and STORE-to-use sequences pass
- Required tool: VCS / Verdi
- Workbook status: In Progress
- Recorded work: Legacy hazard SV bench exists.
- Evidence: [OLD files rtl-dv/verif/tb_hazard/tb_hazard_top.sv](../../../../OLD%20files%20rtl-dv/verif/tb_hazard/tb_hazard_top.sv)
- Missing evidence / remaining action: Review/port current hazards and demonstrate all required sequences with retained accepted-tool results.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 4.9 — Unit regression 100% pass

- Criterion: Directed plus constrained random regression: zero failures on the final RTL
- Required tool: VCS
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No zero-failure final-RTL directed plus constrained-random unit regression identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 4.10 — Core sanity TB built

- Criterion: I-MEM and D-MEM models, IRQ stimulus and checker in place
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: Legacy memory/exception/checker harness exists.
- Evidence: [rv32im_zicsr_5stage_exc_nointr_old/verif/misalign_exception_parallel_test/tb_riscof_soc_dual.sv](../../../../rv32im_zicsr_5stage_exc_nointr_old/verif/misalign_exception_parallel_test/tb_riscof_soc_dual.sv)
- Missing evidence / remaining action: Junior port must establish current memories, boot/reset, IRQ stimulus and self-checking current-core testbench.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 4.11 — Core sanity tests pass

- Criterion: At least one self-checking test per class: arithmetic, branch, jump, load, store, M ops
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: Historical report records 46 passed and one failed test.
- Evidence: [verification/riscof/report.html](../../../../verification/riscof/report.html)
- Missing evidence / remaining action: Current-core accepted-tool self-checking tests for every required class; preserve historical failed JALR case and unknown revision.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 4.12 — Reset and interrupt entry verified

- Criterion: Fetch starts at RESET_PC; IRQ taken at a clean boundary; mtvec jump and mepc save correct
- Required tool: VCS
- Workbook status: In Progress
- Recorded work: Static trap model and legacy IRQ/exception checker concepts exist.
- Evidence: [ips/documentation/signoff/CSR_and_Trap_Model.md](../../../../ips/documentation/signoff/CSR_and_Trap_Model.md)
- Missing evidence / remaining action: Prove reset fetch and clean IRQ entry/mtvec/mepc on the current core; arbiter unit pass does not prove this.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 4.13 — Hazard tests pass at core level

- Criterion: RAW, WAR, WAW, control and structural hazard tests all pass
- Required tool: VCS
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No complete current core RAW/WAR/WAW/control/structural hazard pass evidence identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 4.14 — Core sanity coverage met

- Criterion: 100% opcode coverage for the base ISA; every M op hit once; all load/store sizes hit
- Required tool: VCS / Verdi
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No measured current whole-core base-opcode/M-op/load-store-size sanity coverage closure identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

