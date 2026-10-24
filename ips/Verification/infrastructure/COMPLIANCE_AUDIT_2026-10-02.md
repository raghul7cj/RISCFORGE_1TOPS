# SoC Verification Infrastructure — Independent Forensic Audit

**Auditor role:** Independent Forensic Auditor
**Date:** 2026-10-02
**Normative spec:** `rtl/ips/SoC Verification Infrastructure_ Integration Guide.html` (v1.0, infrastructure edition)
**Subject:** `rtl/ips/Verification/infrastructure/` and `rtl/ips/Verification/step4_checkers/`
**DUT:** `rtl/ips/RTL_SOC/riscforge_soc_subsystem.sv` (module `riscforge_soc_subsystem`, 1374 lines)

---

## 0. Headline verdict

**The status brief overstates delivered capability on all three audited axes.** The
7-layer blame engine, the end-to-end path scoreboard, and the 38/38 smoke pass
are each materially different from what the code contains.

There are **two parallel, divergent checker stacks** in the project, and the audit
brief attributes the capabilities of the *rich* one to files in the *thin* one:

| Capability claimed | Attributed to (brief) | Actually implemented in |
|---|---|---|
| 7-layer hierarchical blame + downstream marking | `infrastructure/checkers/failure_reporter.sv` (71 lines) | `step4_checkers/step4_reporter.sv` (761 lines) |
| LSU→AXI→APB end-to-end reference model | `infrastructure/checkers/mmio_path_scoreboard.sv` (56 lines) | `step4_checkers/step4_path_scoreboard.sv` |
| Independent IRQ priority predictor | `infrastructure/checkers/irq_predictor.sv` (143 lines) | `step4_pkg.sv` (`L_IRQ`) — partial |

The thin stack is the one wired into `soc_tb_top.sv`. The thick stack is bound to
the real DUT via `step4_bind.svh` but runs against a substitute bridge model
(`step4_sim.f:3-14`) and has never run on hardware RTL.

**No SoC-level testbench in this project has ever been elaborated.** See B-1.

---

## 1. Blocker findings

### B-1 — The SoC testbench cannot elaborate; it has never been compiled

`soc_tb_top.sv` taps the DUT through 16 hierarchical references. **None of the
16 exist** in `riscforge_soc_subsystem.sv`:

```
u_core  u_imem_wrapper  u_dsram           -> all MISSING
m0_awaddr m0_awvalid m0_bvalid
m0_araddr m0_rvalid                         -> all MISSING (no m0_* port bundle)
apb_paddr apb_psel apb_penable apb_pwrite
apb_pwdata apb_pready apb_prdata apb_pslverr -> all MISSING
```

The DUT's actual fabric is a **per-slot struct array**, not a flat vector
(`riscforge_soc_subsystem.sv:544-546`):

```systemverilog
apb_req_t  [NUM_APB_SLAVES-1:0] apb_req;    // {psel, penable, pwrite, paddr, pwdata}
apb_resp_t [NUM_APB_SLAVES-1:0] apb_resp;   // {pready, prdata, pslverr}
```

`soc_tb_top.sv:243-250` connects a flat `dut.apb_paddr` / 6-bit `dut.apb_psel`
instead. Independently, **`soc_verification.f` is stale — 39 of its 101 file
entries do not resolve:**

| Broken reference | Actual path |
|---|---|
| `../../SOC_FILES/**` (10 files) | directory does not exist anywhere in the repo |
| `../../apb_timer/apb_timer/` | `apb_timer-master/` |
| `../../uart/rtl/` | `apb_uart-main/` |
| `../../spi/spi_master/` | `spi_master_ip/spi_master/` |
| `../../RTL_SOC/rtl/` | `RTL_SOC/` (flat) |

The filelist also compiles **two mutually exclusive UART implementations**
(`SOC_FILES/include/obi/obi_uart.sv` *and* `uart/rtl/apb_uart.sv`), evidence it
was written against an older IP generation and never refreshed.

**Impact.** Every SoC-level claim in the brief is currently unfalsifiable. There
is no run in which the DUT, the monitors, and the checkers have coexisted.

---

### B-2 — The "7-layer blame engine" is a 6-layer legend with zero hierarchy

`checkers/failure_reporter.sv` is 71 lines. Its entire decision logic
(`failure_reporter.sv:34-36`) is:

```systemverilog
if (!first_fatal_latched) begin
  first_fatal_latched = 1'b1;
  freeze_monitors     = 1'b1;
```

This is **pure first-in-time**. It does not implement the guide's rule
(§3, *First failing check*):

> "It blames the lowest layer that failed first and marks later failures as
> downstream."

Three separate violations:

1. **No layer comparison.** A Layer-4 pin failure at cycle 100 followed by a
   Layer-1 protocol failure at cycle 101 keeps Layer 4 as the blame. The guide
   requires blame to *move down*.
2. **No downstream marking.** Later failures are silently discarded. The report
   cannot state how many downstream failures were suppressed, so a reader cannot
   tell a single root cause from a cascade.
3. **Only 6 layers exist.** `failure_reporter.sv:46` hardcodes
   `1:Protocol, 2:Path, 3:Reg, 4:Pin, 5:IRQ, 6:Firmware`, and `tb_pkg.sv:148-153`
   defines `LAYER_PROTOCOL..LAYER_FIRMWARE = 6`. The guide's Layer 6
   (**CPU state — retired instructions, CSRs, traps → ISS**) has **no slot at
   all**, so when Spike co-simulation is added there is nowhere to blame it.

The correct implementation already exists elsewhere. `step4_checkers/step4_reporter.sv`:

- `step4_pkg.sv:37-45` — the **full 7-layer taxonomy**, matching the guide table 1:1
  (`L_PROTO=1 … L_CPU=6, L_FW=7`).
- `step4_reporter.sv:133-140` — `else if (e.layer < hub.blame_layer) begin`
  … *"a more fundamental layer spoke late: move the blame"* → re-emits the page.
- `step4_reporter.sv:143` — `store(e, F_DOWNSTREAM);`
- `step4_reporter.sv:609-624` — `emit_layer_status()` walks all layers emitting
  `BLAME` / `FAIL` / `DOWNSTREAM`.

Measured delta:

| | `infrastructure/checkers` | `step4_checkers` |
|---|---|---|
| blame-reassignment / downstream logic | **0** | 19 |
| `assert property` | 8 | 35 |
| `cover property` / covergroup | **0** | 23 |
| fault-injection switches | **0** | full `step4_fault_inject.sv` |

---

### B-3 — The path scoreboard has neither an end nor an end-to-end

`checkers/mmio_path_scoreboard.sv` is described in the brief as an
"End-to-end LSU → AXI → APB routing reference model". It is an **APB address
decode check**. Specifically:

- **Lines 14-19 declare six LSU inputs — `lsu_req`, `lsu_we`, `lsu_addr`,
  `lsu_wdata`, `lsu_be`, `lsu_stall` — that are never read anywhere in the
  56-line body.** They are connected at `soc_tb_top.sv:270-275` and do nothing.
- **There are no AXI ports at all.** AXI transactions cannot be observed by this
  checker even in principle.
- **No data, strobe, or response comparison.** The single check
  (`mmio_path_scoreboard.sv:42-54`) verifies only that `psel[s]` matches the slot
  that `get_expected_apb_slot(paddr)` decodes to. It never checks that data,
  strobes, or response match the core's access.

The guide (Step 4) requires: *"each core MMIO access must appear as one AXI
transaction and one APB transfer on the slot given by the address map, **with the
same data, strobes and response**."* None of the three is checked.

The join machinery was written but **is dead code**:

| Helper | Definition | Real callers |
|---|---|---|
| `lsu_at()` | `tb_pkg.sv:968` | **0** (declaration only) |
| `axil_at()` | `tb_pkg.sv:978` | `rf_monitor_env.sv` (report text only) |
| `apb_on_slot()` | `tb_pkg.sv:988` | `rf_monitor_env.sv` (report text only) |
| `count_wrong_slot()` | `tb_pkg.sv:998` | `rf_mon_smoke_tb.sv` (**self-test only**) |
| `count_by_region()` | `tb_pkg.sv:1008` | **0** (declaration only) |

The comment at `tb_pkg.sv:961-965` asserts *"These helpers are the query surface
the mmio_path_scoreboard uses"*. It does not. The scoreboard has no `rf_trace_db`
port and never queries the queues it needs.

---

### B-4 — Layers 1, 2 and 4 cannot reach the freeze broadcast

Only **four** `report_failure` call sites exist in the entire project, all in the
`forever` watcher of `soc_tb_top.sv`:

| Site | Layer | Trigger |
|---|---|---|
| `soc_tb_top.sv:458` | 6 Firmware | watchdog timeout |
| `soc_tb_top.sv:480` | 3 Register | `reg_pred_err` |
| `soc_tb_top.sv:498` | 5 IRQ | `irq_pred_err` |
| `soc_tb_top.sv:524` | 6 Firmware | mailbox `CMD_FAIL` |

`LAYER_PROTOCOL` and `LAYER_PIN` are **never referenced outside their own
declaration** in `tb_pkg.sv`. `LAYER_PATH` is used exactly once — at
`rf_mon_smoke_tb.sv:166` — in a *self-test that injects its own fake fatal*.

Consequence: `mmio_path_scoreboard.sv:48` and every SVA failure emit a raw
`$error`. They do not latch, do not set `freeze_monitors`, and do not appear in
`failure_report.md`. A protocol violation therefore **destroys the ring buffers
it should have preserved**, because the freeze is triggered only by Layers 3, 5
and 6. This inverts the guide's central premise (*"Lower layers are blamed
first, because a protocol error explains many higher-level failures"*).

`tb_pkg.sv:155-163` defines `layer_name()`, which **is never called** — the
reporter duplicates the legend as a hardcoded format string instead, so the two
cannot drift-check each other.

---

## 2. High findings

### H-5 — `register_predictor` GPIO model is wrong at four addresses

The header comment claims *"lowRISC APB GPIO (with atomic SET/CLEAR/TOGGLE)"* and
*"W1C (Write-1-to-Clear) status registers"*. Against the RTL's own
`gpio-master/gpio_reg_pkg.sv:167-186`:

| Offset | RTL truth | `register_predictor.sv` | Verdict |
|---|---|---|---|
| `0x000` | `GPIO_INFO` (RO ID/version) | modelled as **W1C status** (:174) | **WRONG** |
| `0x004` | `GPIO_CFG` | modelled as **interrupt enable** (:176) | **WRONG** |
| `0x380` | `GPIO_INTRPT_RISE_EN` (plain RW) | modelled as **W1C status** (:174) | **WRONG** |
| `0x400` | `GPIO_INTRPT_FALL_EN` (distinct RW) | aliased onto the same var as `0x004` (:176) | **WRONG** |
| `0x580` | `GPIO_INTRPT_STATUS` (**the real W1C register**) | **no model at all** | **MISSING** |
| `0x200/0x280/0x300` | SET / CLEAR / TOGGLE | correct (:182-187) | OK |

`0x380` being AND-cleared means any firmware enabling a rising-edge interrupt
produces a false mismatch; conflating `0x380` and `0x400` into one variable means
enabling both edges reports a mismatch against hardware. Conversely the genuine
W1C register at `0x580` is never compared, so the one side-effect the brief
credits the model with is unverified.

Two further coverage gaps: `t0_timer`/`t1_timer` (offset `0x000`, the most
frequently read register) and `i2c_txr` have write models but **no read model**;
`gpio_irq_en` and `gpio_irq_status` likewise have write models but no read model.

The `check_mask` design (`register_predictor.sv:212, 256`) compounds this:
unmodelled offsets silently yield `check_mask == 0` and are skipped. The predictor
therefore **cannot distinguish "correct" from "not modelled"** — a mostly-empty
model reports zero mismatches and looks healthy.

Two diagnostic defects in the same block:
- `register_predictor.sv:261-263` — `reg_err_msg <= $sformatf(...)` then
  `$error("%s", reg_err_msg)`. Non-blocking assignment means the `$error` prints
  the **previous (empty)** string. Every register-mismatch message prints blank.
- Same NBA-then-read pattern at `irq_predictor.sv:107` and `:137`.

### H-6 — `irq_predictor` performs no arbitration prediction, and its priority table contradicts `tb_pkg`

The brief claims *"Independent 2-level priority arbiter Class 2 > Class 1 > Class 0,
gateway pulse capture, 2-deep shadow stack"*. The 2-deep shadow stack and pulse
capture are present and correct. **The priority arbiter is absent:**

- `pend_q` is written at `irq_predictor.sv:94, 96, 100` and **never read**. No
  winner is ever computed from the pending set. The model cannot predict *which*
  source should be granted.
- `irq_exp_id` is declared `output` (:33), cleared in `reset_model()` (:79), and
  **never assigned anywhere else.** It is permanently `5'd0`.
- `soc_tb_top.sv:496` prints it as `Exp ID` — so the "expected" half of the
  predictor comparison always prints `0`, while `irq_got_id` is assigned in
  exactly one place (:134, the preemption branch).
- `irq_mismatch_err` is raised only on shadow-stack overflow (:104), underflow
  (:119), and the preemption invariant (:132). **The model never checks that the
  DUT granted the highest-priority pending source** — the single property that
  matters most for Layer 5.

The static class table also **contradicts the project's own canonical
classification**:

| Source | ID | `tb_pkg.sv:346-353` (`irq_class`) | `irq_predictor.sv:46-55` (`class_map`) |
|---|---|---|---|
| SPI_EVT1 | 27 | Class **1** | Class **2** (:53) |
| T0_C0_OVF | 20 | Class **2** | Class **0** (default, never set) |
| T1_C0_OVF | 23 | Class **2** | Class **0** (default, never set) |
| T0/T1 C1_OVF/CMP (8,9,24-26) | — | Class **2** | Class **0** (default) |

`class_map` initialises all 32 entries to `2'd0` (:48) and sets only six. So the
predictor believes every timer source is lowest priority, while `tb_pkg` records
`irq_class = 2` on every ring entry built from the *other* table. **A single
failure report would show the monitor's class and the predictor's class
disagreeing**, and the preemption check at :132 (`cand_class <= cur_class`) would
raise a false *Illegal preemption* the first time firmware enables a timer
interrupt.

The same check flags same-class preemption as illegal, which contradicts the
round-robin design in the same file's own header (:43, *"Class 1: Medium
(Round-Robin)"*). `tb_pkg`'s `irq_txn_t` captures `rr_ptrs` per event, but the
predictor keeps **no RR-pointer shadow**, so intra-class ordering is unverified.

### H-7 — Live, unresolved ring-buffer event loss (the freeze evidence is not trustworthy)

The most recent and most comprehensive run in the repository is **not** a pass:

```
EMPIRICAL STRESS TEST RESULTS: 165 Checks, 1 Failures
>>> CHALLENGE IDENTIFIED BUGS / FAILURES (1 failed) <<<
[ASSERTION FAILED] [IRQ_CONCURRENCY_PRESERVED]
   Simultaneous IRQs caused ring buffer slot overwrite / dropped event!
```

This failure is present in **all four** archived `xsim_*.backup.log` files — it
has never been fixed or waived.

Root cause, `monitors/irq_monitor.sv:97-119`: `push_event` writes
`ring_buffer[head_ptr]` with non-blocking assignments and advances
`head_ptr <= (head_ptr + 1) % DEPTH`. When two IRQ sources rise on the same clock
edge, `push_event` is called twice within one time step; both calls read the
*stale* `head_ptr`, so both write the **same slot** and one event is lost. The
paired `total_irq_asserts <= total_irq_asserts + 1` (:145, :149) collapses two
increments into one.

This is precisely the failure mode that destroys forensic value: the ring buffer
loses events under **multi-source collision**, the exact scenario the IRQ
architecture cares most about, and the guide's whole debugging model (§7: *"Read
the failure report before opening waveforms"*) assumes those events are intact.

Note the class-based monitor (`rf_monitors.sv:826-877`) is **not** affected —
`ring.push()` is a blocking `push_back` (`tb_pkg.sv:677-685`). The two stacks
diverge in behaviour (see M-11).

### H-8 — The "38/38 PASS" has no log artifact and never exercised any checker

`run_rf_mon_smoke.ps1` runs `rf_mon_smoke.f`, which compiles **only**:
`tb_pkg.sv`, `rf_monitor_if.sv`, `rf_monitors.sv`, `rf_monitor_env.sv`,
`rf_mon_probe.sv`, `rf_mon_stub_dut.sv`, `rf_mon_smoke_tb.sv`.

Consequences:

- **The DUT is a stub** (`tb/rf_mon_stub_dut.sv`, 291 lines of deterministic
  synthetic stimulus). The real `riscforge_soc_subsystem` is not involved.
- **No checker is compiled.** `mmio_path_scoreboard`, `register_predictor`,
  `irq_predictor`, `failure_reporter`, `axi_lite_protocol_sva`, `apb_protocol_sva`
  are all outside the filelist. Zero of the 38 checks validate Layer 1-5 logic.
- **Freeze is hardwired off:** `rf_mon_smoke_tb.sv:46` — `.freeze(1'b0)`. The
  `failure_reporter → freeze_monitors → monitors` broadcast is never exercised.
  The `F1.frozen` / `F2.cycle` checks (:167-168) read `env.db.frozen`, which is
  set by `note_fatal()` *inside the DB under test* — a self-fulfilling assertion
  that never touches the broadcast path.
- **No log supports the claim.** Scanning every `xsim*.log` in the directory:
  `[SMOKE] pass` = **0**, `[SMOKE] FAIL` = **0**. The logs that exist are all
  from the challenge/freeze-stress suites, and three of the five report failures
  (`CHALLENGE SUITE FAILED with 4 error(s)`, `with 1 error(s)`, and the H-7
  ring-buffer failure).
- **10 of the 38 checks are tautological.** `D1`-`D10`
  (`rf_mon_smoke_tb.sv:150-159`) test `get_expected_apb_slot()` /
  `decode_region()` against literals hardcoded in the *same file* that
  implements them. They assert the lookup table agrees with itself. A further
  4 checks (`P3`-`P6`) assert that APB slots 0, 3, 4, 5 are **idle** — the stub
  deliberately never drives them.

Net: the 38 checks are real and the 6 `M*` event-count and 5 `A*` AXI-channel
checks are genuinely non-vacuous. But ~40% of the pass is self-consistency and
absence-of-activity, and none of it touches the real SoC or any checker.

---

## 3. Medium findings

### M-9 — Layer 4 (pins) and the per-channel AXI stream have no ring buffer at all

`tb_pkg.sv:845-848` declares exactly six rings: `r_fetch, r_retire, r_lsu,
r_axil, r_apb, r_irq`. But `record_gpio/uart/i2c/spi` (:926-944) push **only** to
the unbounded live queues `q_*` and never to a ring; likewise
`record_axi_evt` (:903-906) — the separate AW/W/B/AR/R channel events the guide
Step 3 explicitly mandates (*"AXI-Lite (AW, W, B, AR and R as separate events)"*)
has **no frozen history**.

The guide (§3) requires the reporter to freeze *"the ring buffers that hold the
last transactions of **every monitor**"*. For Layer 4 pin models and for
individual AXI channel handshakes, there is nothing to freeze. A failure report
cannot show what the UART pins or the W channel did immediately before the fault.

Also note the live queues trim to `DEFAULT_LIVE_Q = 200000` (`tb_pkg.sv:40`), so
they *are* progressively discarded pre-mortem.

### M-10 — Two of the guide's five pass-rule clauses are unimplemented; vacuity is advisory, not gating

Guide §3 *Pass rule*: PASS requires **all five** of (a) mailbox PASS, (b) no
checker failed, (c) checkers actually saw activity, (d) **no predicted event left
unobserved**, (e) no timeout.

- (d) is **absent from the entire codebase** — no unobserved-prediction /
  prediction-coverage closure check exists in either stack.
- (c) is implemented, but **non-gating**. `step4_reporter.sv:717-724` prints
  `*** VACUOUS PASS ... ***` while the verdict branch has already been taken as
  `hub.n_find == 0 → "STEP 4 CHECKER VERDICT : CLEAN"`. The verdict does not
  change.
- In `soc_tb_top.sv:513-517` the sole vacuity guard is
  `u_retire_mon.total_retired_instr == 0` — a **Layer-6 CPU proxy**. A test that
  retires instructions but drives **zero MMIO, zero IRQs and zero pin activity**
  passes vacuously for Layers 1-5. This is the single largest remaining hole in
  the "no vacuous pass" requirement, and it is the check the brief singles out
  for Milestone 5.

### M-11 — Two divergent monitor stacks; the validated one is dead code in the real TB

`soc_verification.f:155-169` compiles **both** the class-based stack
(`rf_monitors.sv` / `rf_monitor_env.sv` / `rf_mon_probe.sv`, 1,166+525+221 lines)
*and* the legacy module monitors (`fetch_monitor.sv`, `retire_monitor.sv`, ...).

`soc_tb_top.sv` instantiates **only the legacy module monitors** —
`rf_mon_probe` / `rf_monitor_env` / `rf_monitors` appear **nowhere** in the file.

So the 1,166-line deliverable that passed 38/38 is **not connected to the SoC
testbench**, and the behaviour difference is not cosmetic: the legacy
`irq_monitor.sv` loses simultaneous events (H-7) while the class-based monitor
does not. The stack that was tested is the one that works; the stack that is
wired up is the one that is broken.

### M-12 — Zero fault injection and zero coverage in the delivered checker set

Guide Step 4: *"Give every checker a fault-injection switch (for example, force
one byte strobe) so you can prove it fires. Proof: each injected fault is named
by the correct check ID in the report, and every assertion has a cover that is
hit."*

`infrastructure/checkers/` contains **no** fault-injection port, **no**
`cover property`, **no** covergroup (measured: 0 / 0). There is no mechanism by
which any of its four checkers can be proven to fire.

`step4_checkers/` satisfies both: `step4_fault_inject.sv` exposes a
`step4_fault_inject_cfg_t` switch driving 26 injection points (LSU req/we/stall,
all AXI valid/ready pairs, all APB psel/penable/pwrite/pready, addr/wdata/strb/
resp), and the SVA files carry **23** cover properties against **35** assertions.

The "Remaining Work Scope → Milestone 2" note scopes fault injection to
`Verification/step4_checkers/` only. That scoping is the root cause of B-2/B-3:
the `infrastructure/checkers/` files were never held to the Step 4 bar.

### M-13 — `failure_reporter` derives the cycle number from `$time`, violating the shared timebase

`failure_reporter.sv:40` — `fail_cycle = $time / 10; // assuming 10ns clock`.

Guide Step 3 mandates *"timestamped transaction objects on **one shared cycle
counter**"*. A magic divisor hard-coded to a 10 ns period will silently produce
wrong cycle numbers for any other clock, and it will not agree with the
`tb_cycle` that every monitor stamps its transactions with. The same `$time`-based
value is what appears in `failure_report.md`.

---

## 4. Compliance matrix — guide §3 seven layers

| # | Guide layer | Expected source | Status | Evidence |
|---|---|---|---|---|
| 1 | Protocol — AXI-Lite & APB handshakes | Assertions | **PARTIAL** | 8 `assert property`, **0 cover**, no fault injection, cannot freeze (B-4) |
| 2 | Path — core access → AXI → APB | Scoreboard + address map | **FAIL** | B-3: no LSU/AXI use, no data/strobe/response check |
| 3 | Register — peripheral R/W | Register predictor | **FAIL** | H-5: wrong GPIO map, W1C unmodelled, self-blanking diagnostics |
| 4 | Peripheral function at pins | Pin models | **PARTIAL** | 4 pin VIPs present; **no ring buffer** → no frozen post-mortem (M-9); no fault injection |
| 5 | Interrupt — raise/pending/grant/accept/ack | Independent IRQ predictor | **FAIL** | H-6: no arbitration prediction, dead `irq_exp_id`, class table contradiction |
| 6 | CPU state — retire, CSRs, traps | ISS (Spike) | **ABSENT** | No Spike co-sim, no RVFI port; **and no blame slot exists** (B-2) |
| 7 | Firmware result — mailbox, checksum | Test + host values | **PARTIAL** | Mailbox read/watchdog present; no checksum, no 5-clause pass rule (M-10) |

Guide §3 *First failing check* (freeze + blame lowest layer + mark downstream +
one page with disassembly): **FAIL** in the wired stack (B-2, B-4);
implemented in `step4_reporter.sv`. No disassembly of retired instructions is
produced by the wired stack — `step4_disasm.sv` exists but is unreachable from
`soc_tb_top.sv`.

---

## 5. Recommended remediation order

1. **Make `soc_tb_top.sv` elaborate.** Rebind all 16 probes to the real
   `apb_req[s]` / `apb_resp[s]` struct arrays and to the actual core instance
   name; repair or regenerate `soc_verification.f` against the current IP
   generation (`apb_timer-master`, `apb_uart-main`, `spi_master_ip`, flat
   `RTL_SOC/`, drop `SOC_FILES`). Nothing else can be validated until this lands.
2. **Resolve the duplicate-stack split.** Either delete
   `infrastructure/checkers/*` and re-point `soc_tb_top.sv` at the `bind`-based
   `step4_checkers` stack, or port the 7-layer blame logic from
   `step4_reporter.sv:133-143` into `failure_reporter.sv`. Do not maintain both.
3. **Wire `LAYER_PROTO`/`LAYER_PATH`/`LAYER_PIN` to `report_failure`.** Add the
   `L_CPU` slot. Replace the `$time/10` cycle derivation with the shared counter.
4. **Fix the GPIO register model** against `gpio_reg_pkg.sv` — move W1C to
   `0x580`, un-alias `0x380`/`0x400`, add read models for every write model.
5. **Fix `irq_predictor`**: read `pend_q` to compute the expected winner, drive
   `irq_exp_id`, delete the local `class_map` in favour of `tb_pkg::irq_class()`,
   and add an RR-pointer shadow.
6. **Fix `irq_monitor.sv:97-119`** — advance `head_ptr` with a blocking
   assignment (or push to a queue) so same-cycle multi-source events cannot
   collide. Re-run `run_freeze_stress.ps1` to green.
7. **Implement the unobserved-prediction clause** (guide §3 clause d) and make
   the vacuity check **gating**, keyed per-layer (MMIO/IRQ/pin activity), not on
   `total_retired_instr`.
8. **Add rings for Layer 4 pin events and the per-channel AXI stream** (M-9).
9. **Port fault-injection switches and cover properties** into
   `infrastructure/checkers/`, or delete that directory (M-12).
10. **Fix the NBA-string diagnostic bug** in `register_predictor.sv:263` and
    `irq_predictor.sv:107,137` — use a local `string` and assign with `=`.

---

## 6. Audit method / limitations

- Normative text extracted from `SoC Verification Infrastructure_ Integration
  Guide.html` (30,803 bytes, 161 rendered lines) — note this file lives at
  `rtl/ips/`, **not** at `Verification/` as the brief states.
- All findings verified by direct source inspection and by scripted existence
  checks; no claim rests on the status brief.
- `xsim`, `vcs` and `iverilog` were not re-executed. Every "has never run"
  finding is inferred from (a) non-resolving filelist entries, (b) absent
  hierarchical targets, (c) absence of any passing log artifact, and (d)
  `step4_sim.f:3-14`, which documents a known XSim elaboration blocker on the
  real bridge's unpacked-array ports.
- Milestones 4 and 5 (dual-simulator regression, bare-metal stage suites) were
  out of scope and not assessed.