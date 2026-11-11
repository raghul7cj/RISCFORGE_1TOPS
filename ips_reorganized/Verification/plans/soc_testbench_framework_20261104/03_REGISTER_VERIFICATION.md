# Register verification and semantic coverage

## 1. Goal and honest denominator

Close checklist 6.2 by demonstrating every **addressable integrated register view** and its applicable RW/RO/W1C behavior. Support 6.3 with field/mode evidence. A register sweep that reads one safe offset per aperture is useful bring-up, not the denominator.

Maintain three counts: physical offsets, semantic views and fields. A UART address can have different read/write or DLAB-selected views; a GPIO alias has its own address but shares underlying state. Both timer instances contain two channels. Rev B's historical inventory counts are a starting comparison, not a final current count. Publish the actual inventory only after reviewing the leaf decodes against the selected filelist.

The inventory covers six APB peripherals. Core CSRs receive a separate inventory and trap test suite; they do not inflate the APB register completion percentage. Unintegrated AON/CLIC registers are outside this configuration, explicitly listed rather than silently omitted.

## 2. Descriptor schema

Create `Verification/spec/soc_registers.yaml` as the reviewed behavioral contract. Every entry needs:

| Field group | Required content |
|---|---|
| Identity | Stable register/view/field IDs, instance, absolute address, local offset, alias target, read/write direction and bank selector |
| Authority | Requirement and Rev B check IDs when available, leaf RTL locator, data-sheet/spec reference, known discrepancy or unresolved expectation |
| Width / lanes | Implemented bit width, bus width, legal alignment/access widths, byte lane mapping and partial-write response policy |
| Reset | Reset domain, reset value/mask, retention rules, reset-release settling requirement |
| Access masks | Readable, writable, compare, required-zero, reserved and writable-but-ineffective bits; no unexplained zero compare mask |
| Behavior | RW, RO, WO, W1C, W0C if present, clear-on-read, FIFO push/pop, command pulse, self-clear, set/clear/toggle alias, banked view, hardware set/clear precedence |
| Dynamic state | Volatility, independent event inputs/time model, prediction validity window and comparison tolerance with reason |
| Testability | Legal setup/cleanup, dangerous operations, pin preconditions, read side effects, error response and downstream-side-effect policy |
| Coverage | Applicable access operations, field legal values/modes, named bins, exclusion authority and review date |

Generate address constants, C tables, SV descriptors and an inventory report from this file. Generate syntax and address views; do not generate expected semantic behavior directly from DUT implementation. Review shared metadata independently because a common wrong address can make both stimulus and oracle agree incorrectly. Add directed address/alias negative checks to expose that common-mode risk.

## 3. Inventory review order

1. Resolve the actual UART dependency chain and GPIO/timer variants compiled in the canonical manifest. Do not choose leaf sources by similar filenames.
2. Enumerate decode addresses from I2C, both timer channels in each instance, UART banked/read-write aliases, GPIO package/register top and SPI APB interface. Enumerate holes and unsupported widths separately.
3. Compare with each BSP/header and existing predictor. Reconcile known I2C layout, GPIO interrupt offsets, UART SCR and timer-channel discrepancies. Record each mismatch as spec, DUT, driver or checker issue; do not skip it merely to preserve a pass.
4. Review masks, reset domains and event semantics independently of firmware code. Resolve simultaneous-event policies before writing the checker.
5. Freeze inventory version/hash for each test build. Inventory changes reopen affected bins/tests and require a new coverage-model identity.

Specific current-source cautions from the independent review: UART SCR reads zero and ignores writes; GPIO aggregate status/clear behavior differs from per-type W1C fields; GPIO partial writes are currently rejected by its wrapper; UART's wrapper hardwires write strobes. These are implementation observations to verify against the desired interface contract. If the required byte-lane behavior differs, retain a conformance failure rather than redefining correctness to match the implementation.

## 4. Access execution

### Full SoC frontdoor

The C executor consumes a pre-generated operation table through the normal core load/store path. Suggested operation kinds are `READ_COMPARE`, `WRITE`, `WRITE_EXPECT_EFFECT`, `POLL_BOUNDED`, `CHECKPOINT`, `WAIT_CYCLES`, `SAVE_RESTORE`, `EXPECT_ACCESS_FAULT` and `VERIFY_MEMORY`. Every row carries test/check/operation IDs, address, width, value/mask, bank state, expected response and maximum latency. Firmware records its outcome and progress, but SV independently observes bus responses and reference-model results.

A bounded poll records its attempts and final condition. A loop that times out must emit its own failure code before the outer watchdog when execution remains possible. A faulting access uses a reviewed trap handler that validates cause and resume PC; firmware must not hang on an expected error. Misaligned accesses may trap in the core before any bus beat, so their expectation is a core trap, not an obligatory APB transfer.

Use explicit volatile accesses, compiler barriers and assembly for exact widths or instruction sequences. Retain disassembly proving the intended `lb/lbu/lh/lhu/lw/sb/sh/sw` and CSR instructions were emitted. A generic C RMW is prohibited for FIFO, W1C, read-clear and command registers unless that is the behavior being tested.

### Fabric/component access

The same abstract register test descriptions may use an AXI/APB BFM backend in declared F or peripheral-component configurations. This makes exhaustive masks/negative width tests faster and diagnoses errors precisely. A component pass remains component evidence; each required real-SoC register view also needs an S-profile frontdoor observation or an explicit disposition.

## 5. Model update rules

1. Capture independent hardware events and accepted/completed bus operations once. Use the register's defined update point, not a generator request. Delayed responses and reset require explicitly tracked in-flight operations.
2. For reads, compare with the expected **pre-read** state, then apply read side effects. FIFO reads remove exactly one expected entry only when the real transaction takes effect.
3. For successful writes, update only the documented fields/lanes. For rejected accesses, verify the expected response and absence of unauthorized state change where the contract promises rejection before mutation.
4. Do not equate every error response with rollback. A timeout can respond upstream before a late downstream write completes. Track downstream completion, drain and any permitted late side effect separately; unexpected side effects remain failures.
5. Resolve simultaneous hardware set and software clear from the reviewed priority table. For the current GPIO per-type W1C storage, hardware update precedence must be verified explicitly. Aggregate clear strobes have a different transition rule.
6. Model volatile state from clocks and external events. For a timer, track enable, prescaler phase, count, compare-write behavior and wrap; for UART/SPI/I2C, track peer/FIFO events. If exact prediction is unavailable, specify a justified range or relation and an independent source of the expected bounds. Never learn the expected value from the same DUT read being checked.
7. Reset only fields belonging to the asserted domain; warm retention is a positive expectation. Invalidating a mirror is explicit and leaves associated comparisons unqualified until reinitialized.

## 6. Required test families

| Family | Concrete stimulus | Required comparison |
|---|---|---|
| Reset / retention | Hard reset, accepted soft reset, rejected short pulse; observe internal reset/release | Every stable reset field; documented retained fields and bank defaults |
| RW | Zero, ones within legal writable mask, alternating patterns, walking bit, boundary legal field values | Written bits match; reserved/RO/neighbour fields preserved; restore initial state |
| RO | Read stable values; write legal bus patterns under controlled hardware state | No unauthorized change; dynamic fields follow event model, not simple equality |
| WO / command | Issue command with prepared peer/data; repeat with relevant zero/nonzero mask | Independent pin/state effect exactly as specified; no false readback requirement |
| W1C | Generate real event, write zero, clear selected bits, mixed zero/one, event concurrent with clear | Zero preserves, one clears selected pending state, other bits unaffected, concurrent-event precedence correct |
| Aliases | Write SET/CLEAR/TOGGLE with complementary and overlapping masks | Canonical state changes, unrelated bits preserved; do not use alias readback if undefined |
| Banks / direction | UART DLAB 0/1 with separate RBR/THR/DLL and IER/DLM views | Bank isolation, correct read versus write view, restore DLAB safely |
| FIFO / read side effects | Empty/one/full boundary, ordered payloads, repeated reads/writes | Push/pop ordering, status transitions, under/overflow response and recovery |
| Volatile timer | Disabled read stability; running count; divider/compare bounds; both channels | Cycle/prescaler model, compare/overflow event and write-related count effects |
| Width / alignment | Supported lanes/widths, rejected widths, aligned boundaries, protected writes | Required response/side effect; lane preservation or deliberate rejection, classified by intended contract |
| Decode / holes | First/last legal view, adjacent hole, GPIO `+0x800`, unmapped APB window | Error reaches intended boundary; no wrong peripheral selection or mutation |

RO, WO and dangerous side-effect views are not blindly written merely to claim "100% read and written." Publish the exact applicable test for each view and the reason an operation is inapplicable. That semantic interpretation must be recorded for checklist 6.2 acceptance.

## 7. Coverage and output

Produce `register_inventory.csv` and `register_results.csv`, one row per view and operation obligation. Columns include descriptor ID, field IDs, address/bank, access type, expected response/effect, test/run/check IDs, attempted count, observed completion count, comparison count, pass/fail, waveform/event locator and disposition. A zero comparison mask without a reason is a harness defect. Dynamic/read-side-effect checks name their alternative oracle.

Register functional coverage samples completed accesses, with separate semantic-success bins sampled after comparison. Required dimensions are view × applicable access, field × legal values/boundaries, W1C zero/set/clear/overlap, bank × direction, lane policy × response, reset domain × retention and mode/enable combinations. Add targeted cross bins only where a requirement requires interaction; do not multiply every register by every global mode.

**6.2 exit:** all inventory entries reviewed, all applicable obligations have attributed passing S evidence or a named accepted disposition, no unexplained mismatch/error, all expected events drained and independent negative proofs pass. **6.3 exit:** every declared applicable field/mode bin hit by checked DUT behavior or has an approved waiver/exclusion. Register access coverage, semantic correctness and field functional coverage are three separate reports.
