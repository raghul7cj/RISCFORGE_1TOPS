# G3: recorded work and missing evidence

Review date: 2026-11-02. Entries describe inspected local assets; no new tool runs. Workbook blank means insufficient established evidence, not a claim that work was never performed. Done denotes completion of the exact item criterion only; coach approval and gate closure remain separate.

## 3.1 — GPIO integrated (mandatory)

- Criterion: 32-pin GPIO instantiated, registers reachable, pins routed to top level
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Peripheral instances/maps and scoped component evidence are available.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Complete each row against real current SoC integration, pins/register reachability and required interrupt/flash/slave path.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.2 — UART integrated (mandatory)

- Criterion: 1-2 instances; at least one dedicated to debug output
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Peripheral instances/maps and scoped component evidence are available.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Complete each row against real current SoC integration, pins/register reachability and required interrupt/flash/slave path.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.3 — SPI / QSPI master integrated (mandatory)

- Criterion: Reaches external flash model and supports boot fetch
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Peripheral instances/maps and scoped component evidence are available.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Complete each row against real current SoC integration, pins/register reachability and required interrupt/flash/slave path.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.4 — PLIC integrated (mandatory)

- Criterion: 16-32 sources supported; every peripheral interrupt wired in
- Required tool: Not specified in row
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No integrated PLIC identified. User reports verbal departures broadly; exact PLIC disposition still unrecorded.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.5 — Timer integrated (mandatory)

- Criterion: System tick generates an interrupt to the core
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Peripheral instances/maps and scoped component evidence are available.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Complete each row against real current SoC integration, pins/register reachability and required interrupt/flash/slave path.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.6 — CLINT / CLIC integrated (mandatory)

- Criterion: Timer and software interrupts reach the core
- Required tool: Not specified in row
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No integrated CLINT/CLIC timer/software delivery established; software IRQ tied off at SoC. Exact verbal disposition unrecorded.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.7 — I2C integrated (optional)

- Criterion: If present: master transactions complete against an I2C VIP or slave model
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Peripheral instances/maps and scoped component evidence are available.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Complete each row against real current SoC integration, pins/register reachability and required interrupt/flash/slave path.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.8 — I2S integrated (optional)

- Criterion: If present: basic TX and RX stream verified
- Required tool: Not specified in row
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No integrated I2S verification established. Optional scope/N/A decision not individually recorded.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.9 — Boot ROM integrated

- Criterion: 4 KB ROM with boot image; contents version-controlled and reproducible from source
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Boot ROM instantiated; active default is 16 x 32-bit words (64 bytes).
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Record exact verbal departure disposition or implement required 4 KiB; verify reproducible source image.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.10 — SRAMs integrated

- Criterion: Instruction and data SRAM macros instantiated at the sizes frozen in G1
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: Behavioral SRAM integration exists.
- Evidence: [ips/RTL_SOC/sram_sp.sv](../../../../ips/RTL_SOC/sram_sp.sv)
- Missing evidence / remaining action: Required foundry SRAM macro identities, instances/sizes and approved memory specification are not demonstrated.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.11 — Interconnect integrated

- Criterion: AXI4-Lite core-to-peripheral path; AXI to AXI-Lite and AXI-Lite to APB bridges in place
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: AXI-Lite/APB fabric, boot/reset control and decode implementation exist.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Resolve AXI-to-AXI-Lite/boot-control differences and verify complete current decode/error behavior and agreed controls.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.12 — System control block integrated

- Criterion: Reset control, clock control, boot mode strap sampling and any ROM remap
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: AXI-Lite/APB fabric, boot/reset control and decode implementation exist.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Resolve AXI-to-AXI-Lite/boot-control differences and verify complete current decode/error behavior and agreed controls.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.13 — Address decode matches G1 map

- Criterion: Every slave responds only in its own range; unmapped access returns the defined error
- Required tool: Not specified in row
- Workbook status: In Progress
- Recorded work: AXI-Lite/APB fabric, boot/reset control and decode implementation exist.
- Evidence: [ips/documentation/signoff/SoC_Architecture_Map_Boot.md](../../../../ips/documentation/signoff/SoC_Architecture_Map_Boot.md)
- Missing evidence / remaining action: Resolve AXI-to-AXI-Lite/boot-control differences and verify complete current decode/error behavior and agreed controls.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.14 — Top-level SoC lint clean

- Criterion: Zero errors at SoC level; warnings fixed or waived
- Required tool: SpyGlass
- Workbook status: In Progress
- Recorded work: Historical SoC static-check artifacts exist.
- Evidence: [ips/spyglass/reports/spyglass_summary.rpt](../../../../ips/spyglass/reports/spyglass_summary.rpt)
- Missing evidence / remaining action: Retain current-top SpyGlass clean/waived lint/connectivity results; historical errors and source identity remain unresolved.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.15 — SoC CDC and RDC clean

- Criterion: All clock and reset domain crossings synchronised; zero unwaived violations
- Required tool: SpyGlass
- Workbook status: blank
- Recorded work: No qualifying evidence established in this inspection.
- Evidence: blank
- Missing evidence / remaining action: No qualifying current SoC CDC/RDC zero-unwaived-violation report identified.
- Owner, closure date and item-specific coach approval: not established; left blank.

## 3.16 — Unconnected / floating nets checked

- Criterion: No unintentionally floating inputs or dangling outputs at any hierarchy level
- Required tool: SpyGlass
- Workbook status: In Progress
- Recorded work: Historical SoC static-check artifacts exist.
- Evidence: [ips/spyglass/reports/spyglass_summary.rpt](../../../../ips/spyglass/reports/spyglass_summary.rpt)
- Missing evidence / remaining action: Retain current-top SpyGlass clean/waived lint/connectivity results; historical errors and source identity remain unresolved.
- Owner, closure date and item-specific coach approval: not established; left blank.

