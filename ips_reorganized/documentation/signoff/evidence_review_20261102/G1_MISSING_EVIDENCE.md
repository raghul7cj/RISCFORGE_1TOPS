# G1: recorded work and missing evidence

Review date: 2026-11-02. Entries describe inspected local assets; no new tool runs. Workbook blank means insufficient established evidence, not a claim that work was never performed. Done denotes completion of the exact item criterion only; coach approval and gate closure remain separate.

## 1.1 — Core ISA frozen

- Criterion: One of RV32I / RV32IM / RV32IMC declared in writing
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Written ISA, five-stage pipeline and forwarding/stall policy exist.
- Evidence: [ips/documentation/signoff/Core_Microarchitecture.md](../../../../ips/documentation/signoff/Core_Microarchitecture.md)
- Missing evidence / remaining action: Record approved frozen choices and revision; resolve document caveats.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 1.2 — Pipeline depth frozen

- Criterion: 1 / 3 / 5-stage in-order declared, with hazard policy (stall-only vs forwarding) stated
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Written ISA, five-stage pipeline and forwarding/stall policy exist.
- Evidence: [ips/documentation/signoff/Core_Microarchitecture.md](../../../../ips/documentation/signoff/Core_Microarchitecture.md)
- Missing evidence / remaining action: Record approved frozen choices and revision; resolve document caveats.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 1.3 — Privilege modes frozen

- Criterion: Machine mode minimum; Supervisor + MMU only if targeting Linux
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Machine-mode, CSR reset/access table and trap/IRQ policy documented as implemented.
- Evidence: [ips/documentation/signoff/CSR_and_Trap_Model.md](../../../../ips/documentation/signoff/CSR_and_Trap_Model.md)
- Missing evidence / remaining action: Record frozen/approved specification and resolve static-trace ambiguities; implementation description is not approval.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 1.4 — CSR list frozen

- Criterion: Table of implemented CSRs with reset values and access type (RW/RO/WARL)
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Machine-mode, CSR reset/access table and trap/IRQ policy documented as implemented.
- Evidence: [ips/documentation/signoff/CSR_and_Trap_Model.md](../../../../ips/documentation/signoff/CSR_and_Trap_Model.md)
- Missing evidence / remaining action: Record frozen/approved specification and resolve static-trace ambiguities; implementation description is not approval.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 1.5 — Trap and interrupt model defined

- Criterion: mtvec mode, mepc/mcause behaviour, nested-interrupt policy and trap boundary written down
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Machine-mode, CSR reset/access table and trap/IRQ policy documented as implemented.
- Evidence: [ips/documentation/signoff/CSR_and_Trap_Model.md](../../../../ips/documentation/signoff/CSR_and_Trap_Model.md)
- Missing evidence / remaining action: Record frozen/approved specification and resolve static-trace ambiguities; implementation description is not approval.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 1.6 — Memory organisation frozen

- Criterion: Instruction SRAM, data SRAM and 4 KB boot ROM sizes fixed; prefetch buffer / I-cache sizes fixed if used
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: SoC blocks, maps, memories and boot behavior documented.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Resolve requirement differences, review exact implementation, and record approved frozen map/boot/controller policy.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 1.7 — SoC block diagram approved

- Criterion: Shows core, interconnect, every peripheral, memories, clock and reset sources
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: SoC blocks, maps, memories and boot behavior documented.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Resolve requirement differences, review exact implementation, and record approved frozen map/boot/controller policy.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 1.8 — Address map frozen

- Criterion: Every slave has base address and size, no overlaps, error response defined for unmapped access
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: SoC blocks, maps, memories and boot behavior documented.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Resolve requirement differences, review exact implementation, and record approved frozen map/boot/controller policy.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 1.9 — Interrupt map frozen

- Criterion: Every source numbered and mapped to a PLIC/CLINT input, with priority scheme stated
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: SoC blocks, maps, memories and boot behavior documented.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Resolve requirement differences, review exact implementation, and record approved frozen map/boot/controller policy.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 1.10 — Clock and reset architecture defined

- Criterion: Clock sources, dividers, reset tree, async-to-sync strategy and all CDC crossings listed
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Clock/reset/CDC inventory and top-pin documentation exist.
- Evidence: [ips/documentation/signoff/Clock_Reset_CDC_and_Pinlist.md](../../../../ips/documentation/signoff/Clock_Reset_CDC_and_Pinlist.md)
- Missing evidence / remaining action: Complete reviewed crossing strategy and pad/mux information; retain frozen architecture/pin approval.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 1.11 — Pin list / chip IO table frozen

- Criterion: Every top-level pin: name, direction, function, pad type and mux
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Clock/reset/CDC inventory and top-pin documentation exist.
- Evidence: [ips/documentation/signoff/Clock_Reset_CDC_and_Pinlist.md](../../../../ips/documentation/signoff/Clock_Reset_CDC_and_Pinlist.md)
- Missing evidence / remaining action: Complete reviewed crossing strategy and pad/mux information; retain frozen architecture/pin approval.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 1.12 — Boot plan defined

- Criterion: Boot mode pin: 0 = internal ROM, 1 = external SPI flash; fallback behaviour stated
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: SoC blocks, maps, memories and boot behavior documented.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Resolve requirement differences, review exact implementation, and record approved frozen map/boot/controller policy.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 1.13 — Micro-architecture document complete

- Criterion: Per-stage datapath, control signals, hazard/forwarding logic, memory interface protocol
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Per-stage datapath, control, hazards and memory interface are documented.
- Evidence: [ips/documentation/signoff/Core_Microarchitecture.md](../../../../ips/documentation/signoff/Core_Microarchitecture.md)
- Missing evidence / remaining action: Complete technical review and resolve marked ambiguities/unverified behavior before declaring document complete.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 1.14 — Verification plan (testplan) written

- Criterion: Feature to test to coverage-item mapping across all five verification phases
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Existing verification plan and component matrix provide a starting point.
- Evidence: [ips/Verification/soc_verification_plan.md](../../../../ips/Verification/soc_verification_plan.md)
- Missing evidence / remaining action: Finish exact feature-to-test-to-coverage mapping across all five official verification phases.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 1.15 — Area, frequency and power targets stated

- Criterion: Target clock frequency (MHz) and gate count / die area budget agreed with coach
- Required tool: Not specified in row
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: Approved quantitative frequency, area/gate budget and power targets not established.
- Owner, closure date and item-specific coach approval: not established; left blank.

