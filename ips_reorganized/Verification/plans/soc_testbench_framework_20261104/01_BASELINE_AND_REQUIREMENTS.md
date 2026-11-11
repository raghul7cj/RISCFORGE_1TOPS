# Baseline and requirement mapping

## 1. Authority and interpretation

Use [RISCFORGE_Verification_Plan_RevB.docx](../../../RISCFORGE_Verification_Plan_RevB.docx) as the principal verification-intent source. Use the [compact plan](../../../Compact_RISCFORGE_SoC_Verification_Plan.docx) for an overview, not as an independent source of newer requirements. Use current checked-in RTL to establish the implemented boundary. Differences become explicit decisions or defects; neither a stale plan nor an RTL implementation automatically overrides an architectural requirement.

Rev B contributes the four independent verification bands, anti-vacuity, checker viability, run identity, closure over declared bins, qualified exclusions and requirement/check/test/result traceability. Adopt those mechanisms. Do not copy its older source counts, six-source IRQ assumptions or execution-environment assertions without checking current assets.

This is a proposed verification baseline, ready to implement incrementally. Decisions that change external checklist acceptance, architectural expectations or simulator-of-record policy need an item-specific recorded disposition. No RTL modification is proposed here.

## 2. Current SoC boundary

The inspected [SoC top](../../../RTL_SOC/riscforge_soc_subsystem.sv) instantiates the core, bootloader, memories, two-requester/three-target AXI-Lite crossbar, AXI-Lite-to-APB bridge and six APB peripherals.

| Item | Current implementation | Testbench consequence |
|---|---|---|
| Top controls | `clk_i`, `hard_rst_ni`, `soft_rst_ni`, `test_mode_i`, legacy `fetch_enable_i`/`boot_addr_i` | Drive clock/reset; do not assume legacy controls stop the core or change its reset vector |
| Core fetch | Reset PC fixed to zero; BootROM then ISRAM fetch path | Observe actual ROM fetch, SRAM entry and firmware completion; no invented boot-mode strap |
| BootROM | Default 16 words, 64 bytes | Cover implemented ROM and trampoline; 4 KiB checklist requirement remains a scope discrepancy |
| ISRAM / DSRAM | `0x0001_0000..0x0001_7FFF` / `0x0002_0000..0x0002_7FFF` | Fetch and ordinary DSRAM traffic use direct native paths; they are not expected to appear on AXI/APB |
| AXI requesters | Core MMIO path and bootloader SRAM loader | In full SoC they are DUT-owned. No external AXI input port exists |
| AXI targets | ISRAM, DSRAM, APB aperture `0x4000_0000..0x4FFF_FFFF` | Full address map includes holes and errors, not just valid register addresses |
| APB slots | I2C `0x4000_0000`, Timer0 `0x4000_1000`, UART `0x4000_2000`, GPIO `0x4000_3000`, SPI `0x4000_4000`, Timer1 `0x4000_5000` | Record half-open ranges. GPIO ends at `0x4000_3800`; `0x4000_3800..0x4000_3FFF` is a hole |
| Reset | External hard and filtered soft reset; bootloader-generated core/peripheral/SPI resets | Observe actual internal resets, qualify progress checks and derive pulse acceptance from synchronization/filter behavior |
| Pins | UART TX/RX, I2C split open-drain pins, GPIO, single-lane SPI with two chip selects | One electrical driver per contribution; shared SPI MISO resolved by selected chip, I2C resolved wired-low with pull-ups |
| Interrupts | MTIP cause 7 plus fast causes 16–27; 13 gateway inputs in current `top.v` | Replace six-bit assumptions and verify raw event through commit/ISR/return |
| Unintegrated features | No integrated PLIC, CLINT/CLIC or AON watchdog; MEIP/MSIP tied low | Record exclusions from this implemented configuration; do not count forced core-input tests as real SoC delivery |

The IRQ mapping in the current [core](../../../riscv_core/rtl/top.v) and [arbiter](../../../riscv_core/rtl/irq_arbiter.v) is:

| Class | Causes and sources | Expected service rule |
|---|---|---|
| 2 | 7 Timer0 ch0 compare; 22 Timer0 ch1 compare; 24 Timer1 ch0 compare; 26 Timer1 ch1 compare; 20 Timer0 ch0 overflow; 21 Timer0 ch1 overflow; 23 Timer1 ch0 overflow; 25 Timer1 ch1 overflow | Fixed priority in this listed order |
| 1 | 19 UART, 18 SPI threshold, 27 SPI end-of-transfer | Cyclic round robin; update history on committed service, not a speculative winner |
| 0 | 17 I2C, 16 GPIO | Round robin; reset search starts at I2C |

`irq_raw = {fast_irq_i[11:0], timer_irq_i}`, `edge_mode = 13'h0002` and `event_mode = 13'h1fe9`: GPIO uses rising-edge capture; timers and both SPI events use event capture; I2C/UART use level pass-through. Captures coalesce while pending and win a simultaneous acknowledgement clear. Verify source persistence and clear behavior from each peripheral. Current CSR RTL uses live trap-context registers, not the older plan's hardware shadow stack. Nesting therefore needs reviewed software save/restore and threshold policy; do not inherit old predictor expectations.

## 3. Established assets and reuse verdict

Existing source is implementation evidence. A retained log is scoped execution evidence. Current-candidate coverage and closure require an attributable rerun.

| Existing asset | What is established | Reuse decision / remaining work |
|---|---|---|
| `infrastructure/tb/soc_tb_top.sv` | Real DUT instance, firmware mailbox, pin models, passive monitor/checker connections | Refactor incrementally behind a single observation adapter. Fix widths and reset-domain assumptions in verification code after review |
| `infrastructure/monitors/` | Fetch, retire, LSU, AXI, APB, IRQ recorders; smoke/stress artifacts | Keep qualified capture logic; add common transaction contracts, current-width taps, reset epochs and completion rules |
| `checkers/mmio_path_scoreboard.sv` | Selected APB address-to-slot check | It does not implement a queued LSU→AXI→APB join, response checking or drain. Its GPIO range is stale; replace/extend under one scoreboard owner |
| `checkers/register_predictor.sv` | Partial shadows for six peripherals | Wrong I2C layout, incomplete timer-channel coverage and outdated GPIO/UART assumptions need review. Complete masks, banks, side effects, dynamic state and byte-enable policy from independently reviewed descriptors |
| `checkers/irq_predictor.sv` | Legacy IRQ model | Rebuild for 13 sources/current classes. Existing model assigns cause 27 to class 2, while current arbiter places it in class 1 |
| UART pin VIP | Fixed 8-bit TX capture and selectable loopback | Extend into configurable RX driver and independent frame monitor with parity/framing/error checks; console capture alone is insufficient |
| I2C EEPROM / SPI flash models | Existing lightweight and vendor model options | Qualify exact commands/timing/error capabilities. Keep fast functional and vendor-timing model runs separately identified |
| `step4_checkers/` | Richer reporting/checker self-proof, including injected faults | Mine useful algorithms/check IDs. Do not bind two independent reporters or assume its bridge-model self-proof establishes full-SoC checking |
| `tests/suites/stage1..stage7` and drivers | Firmware tests, mailbox, IRQ dispatch, peripheral driver starting points | Audit each against current map/IRQ policy. Stage5 is a scoped reset sweep, not a complete register inventory. Existing ELF files alone prove no execution |
| Regression and identity scripts | Runners, result folders, P0 hash machinery | Extend existing entry points. Generate one resolved source manifest; distinguish absolute runtime paths from portable canonical identity |
| `verification_matrix.csv` | 26 scoped evidence records with boundary limitations | Preserve; add generated detailed requirement/check/test/result links rather than hand-promoting old entries |

Paths above are under `ips/Verification/` unless stated otherwise. Principal evidence references are the [verification matrix](../../verification_matrix.csv), [phase snapshot](../../status/PHASE_STATUS.md), [Stage3 raw log](../../artifacts/stage_proofs/20261024_stage3_monitor_count/logs/stage3_monitor_count_sim.log), [boot record](../../components/memory/boot_path.md) and [monitor record](../../components/observability/monitors_and_checkers.md).

Additional integration hazards identified statically: the current `soc_tb_top` I2C output-enable expression appears opposite to the leaf's active-low enable; cold boot can wait for `boot_done` before activating its runtime watchdog; an alternate BSP header places a mailbox at the exclusive DSRAM end; OOP probe interfaces also contain obsolete six-bit IRQ and round-robin pointer widths. Treat these as verification integration findings to reproduce/resolve before trusting the relevant experiments. They are not new simulated DUT failures. The selected source manifest includes a UART OBI dependency chain despite older filelist comments claiming it is absent.

Retained examples: Stage3 reports 5,551 retired instructions and 18 APB transfers on slots 0/1/5; staged boot/Timer0 reports 52/52; monitor-buffer stress reports 165 checks/zero failures; IRQ unit Xcelium functional report covers 471/471 declared bins. These results have different boundaries and identities. None is a new execution result from this planning exercise. Some summary prose predates newer runs; raw logs and run-specific manifests take precedence for historical facts.

## 4. Checklist crosswalk and completion evidence

| Item | Planned mechanism | Evidence required for this item |
|---|---|---|
| 6.1 SoC environment | Real SoC top, pin agents, bus/IRQ observation, models, coverage; active AXI agents in fabric top | Current elaboration topology, agents/checkers enabled, self-tests and non-vacuous full-SoC smoke; exact SV/UVM disposition |
| 6.2 Registers | Semantic descriptor model plus firmware frontdoor executor | Every addressable register/bank/alias disposition; legal RW/RO/W1C checks; observed accesses and comparisons, zero unexplained mismatch |
| 6.3 Register fields | Field/legal-mode covergroups | 100% declared applicable enable/mode bins with reviewable waivers/exclusions |
| 6.4–6.7 Peripherals, IRQ, fabric, map | Pin scoreboards, 13-source IRQ scoreboard, isolated fabric stress, firmware map/error tests | Unit and real-SoC results separately attributed; end-to-end evidence for each applicable obligation |
| 6.8 Peripheral+IRQ stress | Mixed firmware work plus external pin traffic and controlled peripheral IRQ generation | Event-qualified runs, checked data, source/service counts, no unexpected protocol error, no unbounded stall |
| 6.9–6.11 Boot | Genuine cold flash load and separately labeled warm preload | Observed fetch/load/release/continuation; missing strap/remap expectations explicitly dispositioned |
| 6.12 Bare-metal suite | March/walking patterns, peripheral duplex/loopbacks, implemented interrupt paths | Memory regions/patterns, observed pin payloads, IRQ entry/return and final signatures; software/external IRQ tie-offs recorded as scope decisions |
| 6.13 Trap robustness | Assembly load/store/branch/M-extension kernels interrupted by real peripheral events | Saved GPR/CSR/PC/memory state checks, intended nesting/defer/return coverage, replayable event schedule |
| 6.14 Random/stress | Full-SoC external/reset workload plus complementary fabric BFM campaigns | Natural SoC timing and legal fabric backpressure separately reported; no synthetic result mislabeled full-SoC |
| 6.15 Functional coverage | Declared bus/register/pin/IRQ/reset/boot/trap bins | Same-identity merged database, per-bin provenance and hole disposition |
| 6.16 Code coverage | Shipping DUT hierarchy report | Raw statement/line, branch, condition and toggle counts; explicit exclusions and per-metric targets |
| 6.17 Full regression | Candidate manifest of directed/random/software/negative suites | Zero unexpected failures on exact candidate source identity; expected-negative tests separately classified; all required tests executed |

## 5. Flexible departures and fixed safeguards

Keep the mechanism rigorous while allowing the implementation to stay small:

- Pure SV is the selected default. Record a narrow 6.1 acceptance decision instead of pretending the word UVM is already satisfied.
- Use VCS as the proposed coverage-of-record baseline because Rev B §10.1 names it. Qualify its classes, covergroups, assertions and database workflow before committing campaign time. Xcelium is a viable alternative only after recording the change and rebaselining measurement; XSim remains useful for local bring-up. No commercial-tool availability was tested for this plan.
- Report Rev B's 100% line/branch/condition after reviewed exclusions alongside the checklist's raw ≥95% statement/branch/toggle request. Toggle targets deferred in Rev B do not erase the checklist. Keep the request OPEN unless it is met or explicitly superseded; do not average metrics or tool databases.
- Use convergence and event counts to size stress. Initial budgets in this package are implementation targets, not proof of reliability or a silent replacement for Rev B's release campaign.
- No RTL changes, new architecture ports, fake IRQ wires or arbitrary wait-state forcing are necessary to begin. Missing implemented capabilities remain visible scope items.
