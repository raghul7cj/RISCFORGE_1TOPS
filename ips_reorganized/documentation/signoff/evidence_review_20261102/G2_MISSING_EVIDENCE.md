# G2: recorded work and missing evidence

Review date: 2026-11-02. Entries describe inspected local assets; no new tool runs. Workbook blank means insufficient established evidence, not a claim that work was never performed. Done denotes completion of the exact item criterion only; coach approval and gate closure remain separate.

## 2.1 — PC generation unit coded

- Criterion: Reset PC parameterised; redirect priority (trap > branch/jump) implemented
- Required tool: NA
- Workbook status: Done
- Recorded work: RESET_PC parameter and trap-first next-PC mux inspected.
- Evidence: [ips/riscv_core/rtl/fetch_cycle.v](../../../../ips/riscv_core/rtl/fetch_cycle.v)
- Missing evidence / remaining action: No missing coding criterion identified by static review. Simulation/reset/redirect proof belongs to G4/G5.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 2.2 — Decoder and control unit coded

- Criterion: All declared ISA opcodes decode; I/S/B/U/J immediates generated
- Required tool: NA
- Workbook status: In Progress
- Recorded work: Decoder/control and immediate-generation implementation documented.
- Evidence: [ips/documentation/signoff/Core_Microarchitecture.md](../../../../ips/documentation/signoff/Core_Microarchitecture.md)
- Missing evidence / remaining action: Complete exact declared-ISA decode/encoding review; no exhaustive opcode evidence claimed.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 2.3 — Register file coded

- Criterion: x0 hardwired to zero; same-cycle read/write behaviour documented and implemented
- Required tool: NA
- Workbook status: In Progress
- Recorded work: Register file and same-cycle bypass coded.
- Evidence: [ips/riscv_core/rtl/Register_File.v](../../../../ips/riscv_core/rtl/Register_File.v)
- Missing evidence / remaining action: Confirm x0 always reads zero in the synthesis configuration: reads use Register[A] and x0 storage relies on initialization/write behavior. No fix or simulation performed.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 2.4 — ALU coded

- Criterion: Add/sub wrap, logical vs arithmetic shift, shift-amount masking, SLT/SLTU sign handling
- Required tool: Not specified in row
- Workbook status: Done
- Recorded work: 32-bit add/sub, masked shifts, signed arithmetic shift and SLT/SLTU inspected.
- Evidence: [ips/riscv_core/rtl/ALU.v](../../../../ips/riscv_core/rtl/ALU.v)
- Missing evidence / remaining action: No missing coding criterion identified by static review. Reference-model/corner verification remains G4.4.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 2.5 — Branch unit coded

- Criterion: BEQ, BNE, BLT, BGE, BLTU and BGEU all implemented
- Required tool: Not specified in row
- Workbook status: Done
- Recorded work: All six signed/unsigned branch conditions inspected.
- Evidence: [ips/riscv_core/rtl/JB_unit.v](../../../../ips/riscv_core/rtl/JB_unit.v)
- Missing evidence / remaining action: No missing coding criterion identified by static review. Compare-matrix verification remains G4.5.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 2.6 — MDU coded (if M extension)

- Criterion: MUL/DIV/REM including divide-by-zero and overflow per spec; handshake with bounded latency
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: MDU, memory/LSU and hazard/stall/forwarding implementation documented.
- Evidence: [ips/documentation/signoff/Core_Microarchitecture.md](../../../../ips/documentation/signoff/Core_Microarchitecture.md)
- Missing evidence / remaining action: Review complete criterion against frozen specification, including bounded handshake latency, wait/flush and alignment semantics.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 2.7 — Memory interface unit coded

- Criterion: Byte enables, store alignment, load sign/zero extension, one outstanding transaction
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: MDU, memory/LSU and hazard/stall/forwarding implementation documented.
- Evidence: [ips/documentation/signoff/Core_Microarchitecture.md](../../../../ips/documentation/signoff/Core_Microarchitecture.md)
- Missing evidence / remaining action: Review complete criterion against frozen specification, including bounded handshake latency, wait/flush and alignment semantics.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 2.8 — Hazard and forwarding logic coded

- Criterion: Load-use stall, flush on redirect, stall on MDU busy and on memory wait states
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: MDU, memory/LSU and hazard/stall/forwarding implementation documented.
- Evidence: [ips/documentation/signoff/Core_Microarchitecture.md](../../../../ips/documentation/signoff/Core_Microarchitecture.md)
- Missing evidence / remaining action: Review complete criterion against frozen specification, including bounded handshake latency, wait/flush and alignment semantics.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 2.9 — CSR block and trap logic coded

- Criterion: Matches the CSR table and trap model frozen in G1
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: CSR/trap RTL and static behavior documented.
- Evidence: [ips/documentation/signoff/CSR_and_Trap_Model.md](../../../../ips/documentation/signoff/CSR_and_Trap_Model.md)
- Missing evidence / remaining action: Demonstrate match to an approved frozen G1 CSR/trap specification; resolve remaining caveats.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 2.10 — Compressed decoder coded (if C extension)

- Criterion: 16-bit instructions expand correctly; misaligned fetch handled
- Required tool: Not specified in row
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No C extension in documented design. Leave blank; N/A requires exact scope decision, not inference.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 2.11 — RTL coding rules followed

- Criterion: Synthesisable subset only: no initial blocks, no delays, no latches, no multi-driven nets
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Core source and synthesis-guarded simulation initialization documented.
- Evidence: [ips/documentation/signoff/Core_Microarchitecture.md](../../../../ips/documentation/signoff/Core_Microarchitecture.md)
- Missing evidence / remaining action: Complete synthesizability/static review; exclude unintended latches and multiple drivers with retained evidence.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 2.12 — Core lint clean

- Criterion: Zero errors; every warning fixed or waived with a written reason
- Required tool: SpyGlass
- Workbook status: In Progress
- Recorded work: Historical SpyGlass report exists, with black-box errors.
- Evidence: [ips/spyglass/reports/spyglass_summary.rpt](../../../../ips/spyglass/reports/spyglass_summary.rpt)
- Missing evidence / remaining action: Current-core qualified SpyGlass lint, zero errors and disposition of every warning; historical report is not clean closure.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 2.13 — Core CDC clean

- Criterion: Every crossing synchronised; zero unwaived violations (Mark N/A for core on single clocks)
- Required tool: SpyGlass
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No current core CDC closure or item-specific approved single-clock N/A record.
- Owner, closure date and item-specific coach approval: not established; left blank.

