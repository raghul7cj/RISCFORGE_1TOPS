# RISCFORGE SoC Verification — Swarm Execution Plan (M2 / M4 / M5)

**Orchestrator:** `orchestrator_1`
**Date:** 2026-10-02
**Baseline:** M1 infrastructure complete. `run_rf_mon_smoke.ps1` PASSED 38/38 on XSim 2022.2.
**Scope:** coordinate M2 (fault-injection hardening), M4 (dual-simulator regression), M5 (7-stage proof suites).

---

## 0. Audit findings that re-baseline the plan

A disk audit contradicts several assumptions in `PROJECT.md`. These were verified directly, not inferred.

### 0.1 BLOCKER — two RTL source chains are absent from the repository

`riscforge_soc_subsystem.sv` instantiates peripherals whose implementations are **not present anywhere in `RISCFORGE_1TOPS-main`** (whole-tree search, not just `rtl/ips`):

| Chain | Entry point (SoC top) | Absent sources |
|---|---|---|
| UART | `apb_uart` @ `riscforge_soc_subsystem.sv:1069` → `apb_uart_wrap.sv:48` `apb_to_obi`, `:63` `obi_uart` | `obi_uart.sv`, `obi_uart_register.sv`, `obi_uart_modem.sv`, `obi_uart_baudgen.sv`, `obi_uart_rx.sv`, `obi_uart_tx.sv`, `obi_uart_interrupts.sv`, `obi_uart_pkg.sv` |
| GPIO | `gpio_apb_wrap` @ `riscforge_soc_subsystem.sv:1102` → `gpio_apb_wrap.sv:83` `apb_to_reg` | `reg_intf.sv`, `apb_to_reg.sv`, `prim_subreg_arb.sv`, `prim_subreg.sv`, `prim_subreg_ext.sv`, `reg_to_apb.sv` |

Both are upstream PULP `SOC_FILES` / `common_cells` sources. **`apb_to_obi.sv` and `obi_pkg.sv` survive at `apb_uart-main/include/obi/`; only the OBI UART core and the entire `register_interface` are gone.**

**Consequence: the SoC DUT cannot be elaborated today, by any simulator.** Not a filelist typo — the source does not exist. Every M4 and M5 worker is blocked behind recovering this. This is promoted to **Milestone 0**.

### 0.2 `soc_verification.f` / `.prj` — 37 of 124 refs unresolvable

Two distinct failure classes, which must not be conflated:

- **(a) Rename drift — fixable.** `SOC_FILES/`→`apb_uart-main/`, `spi/`→`spi_master_ip/spi_master/`, `uart/rtl/`→`apb_uart-main/rtl/`, `apb_timer/apb_timer/`→`apb_timer-master/rtl/`, and a dropped `rtl/` prefix on 6 `RTL_SOC/rtl/*` files.
- **(b) Genuinely absent — see 0.1.** `obi_uart*.sv` (7) and `register_interface/*` (6) have no on-disk target.

Proven by on-disk log `infrastructure/xvlog_test.log`: `ERROR: [XSIM 43-4316] Can not find file: ../../SOC_FILES/include/apb/apb_pkg.sv`.
**No SoC-level simulation has ever run.** All XSim artifacts on disk are `freeze_stress_sim` and `rf_mon_challenge_sim`.

### 0.3 `run_regression.ps1` executes no simulator

`regression/run_regression.ps1` (109 lines) builds `$xelabCmd`/`$xsimCmd` strings, `Write-Host`s them, and never invokes them. `$passedCount++` at L96 and L99 is unconditional; `$failedCount` is declared and printed but **never incremented**, so the summary always reports `Failed : 0`. `-Target remote` only echoes a path to `run_vcs.sh` and increments the pass counter. It also resolves `soc_verification.prj` at `Verification/` when the file is at `Verification/infrastructure/`, and omits `stage2_watchdog` from `$testList` (L32–39 lists stages 1,3,4,5,6,7).

### 0.4 Checkers cannot reach the failure reporter

`report_failure(...)` is declared at `checkers/failure_reporter.sv:28` and has exactly **4 call sites, all in `tb/soc_tb_top.sv`** (L458, L480, L498, L524). No checker holds a reporter handle. All 6 checkers emit bare `$error` with no layer and no check-ID namespace: `mmio_path_scoreboard.sv:48`, `register_predictor.sv:263`, `irq_predictor.sv:107/121/137`, `apb_protocol_sva.sv:28/39/49`, `axi_lite_protocol_sva.sv:47/55/63/71/79`. The 7-layer blame engine therefore never sees an L1/L2 finding, so `LAYER_PROTOCOL` and `LAYER_PATH` are unreachable in practice.

### 0.5 `rf_mon_probe` is dead code at SoC level

`rf_mon_probe.sv` (483 lines) is compiled by `soc_verification.f:161` but has **zero instances in `soc_tb_top.sv`**. Its 1009-line class-monitor layer (`rf_monitors.sv`) + 523-line interface file (`rf_monitor_if.sv`) are therefore inert in every SoC run. Two independent reasons it cannot be dropped in: it hard-references `u_dut.*` while `soc_tb_top` names its DUT `dut`; and it expects `dut.core_axi_req` / `apb_req[g]` (packed structs) while `soc_tb_top` exposes flattened `dut.m0_*` / `apb_p*`.

### 0.6 Vacuity guard is 1 of the 4 required points

`soc_tb_top.sv:513–519` rejects PASS only when `u_retire_mon.total_retired_instr == 0`. `PROJECT.md` Feature 41 requires 4 conjuncts: `CMD_PASS` ∧ `retired_instr > 0` ∧ `bus_transaction_activity > 0` ∧ `n_find == 0`. Three are missing.

### 0.7 Corrections to earlier audit notes

- **Mailbox encodings match.** `tests/bsp/mailbox.h:17-19` defines `MAILBOX_CMD_PASS 0xC0DEC0DE`, `CMD_FAIL 0xBAADF00D`, `CMD_HALT 0xDEADBEEF` — identical to `tb_pkg.sv:168-170`. A prior audit claiming a `0x1`/`0x2` mismatch was **wrong**. No action.
- **Stage firmware is substantive**, not skeleton: stages 1–7 are 113/90/105/149/42/64/52 lines.
- `step4_disasm.sv` lives in `step4_checkers/`, not `infrastructure/checkers/`. `PROJECT.md:128` path is stale; no file should be moved.

### 0.8 M2 is NOT blocked by 0.1

`STEP4_SPEC.md` §14.1 prescribes deleting `step4_apb_bridge_model` and running the matrix against the **real `axi_lite_to_apb`** — which **is** present at `axi_lite_to_apb/axi_lite_to_apb.sv`. The matrix needs the bridge, not the SoC top. `step4_bind.svh`'s SoC binds are the only part needing the full DUT, and they are currently inert (not in `step4_sim.f`, never `` `include ``d). **M2 can run immediately, in parallel with M0.**

---

## 1. Milestone re-baseline

| # | Name | Status | Depends on |
|---|------|--------|-----------|
| **M0** | **RTL Source Recovery + Filelist Repair** | **NEW — BLOCKING** | none |
| M1 | Passive Protocol & Pipeline Monitors | **DONE** (38/38 XSim) | — |
| M2 | Protocol SVAs, MMIO Scoreboard & First-Fatal Blame Engine | hardening in progress | M1 |
| M3 | Peripheral Register & Interrupt Predictor Models | implemented, unwired | M1, M2 |
| M4 | Dual-Simulator Build & Regression Automation | blocked | **M0**, M2, M3 |
| M5 | 7-Stage Proof Suite Regression & Sign-Off | blocked | **M0**, M4 |

### Critical path

```
M0 (RTL recovery + filelist)  ──>  M4 (real compile/elab/run)  ──>  M5 (7 stages signed off)
       │                                                          ▲
       └────────────────> M2 (bridge matrix green) ─────────────┘
                              (runs in PARALLEL from t=0)
```

`M2` and `M0` start concurrently. `M2` finishes first and is a hard input to `M4`, because `M4` cannot claim "dual-simulator regression" if the checker suite it compiles has never been proven to fire.

---

## 2. Workstreams, worker contracts, exit criteria

### W0 — RTL Source Recovery & Filelist Repair *(M0)*

**Owner:** 1 worker. **Effort:** highest risk item in the programme — schedule first, do not parallelize internally.

**Inputs**
- `RTL_SOC/soc_subsystem.f` — the reference dependency list, and the only filelist whose paths have previously compiled end-to-end.
- Known-absent set (table 0.1): 8 OBI-UART files, 6 `register_interface` files.
- Upstream provenance: PULP `common_cells` / `SOC_FILES`. Two retrieval routes, tried in order:
  1. Remote VLSI server — `iiita@172.16.33.48:/home/iiita/Documents/CJ/` (Synopsys host, `SNPSLMD_LICENSE_FILE=27020@14.139.1.126`). The `/home/iiita/MALAY_SOC/rtl/SOC_FILES/` tree referenced by `soc_subsystem.f` comments may still hold them.
  2. Upstream open-source import matching the SHL-0.51 headers already present in `apb_uart-main/include/`.
- `infrastructure/xvlog_test.log` — reproduces the current failure on demand.

**Tasks**
1. Recover the 14 absent files into `apb_uart-main/include/obi/` and `apb_uart-main/include/register_interface/`. **Do not** invent or synthesise substitutes — a hand-written UART defeats the purpose of verifying the real one, and `STEP4_SPEC.md` §10 makes exactly this point about stub models.
2. Repair `soc_verification.f`: 31 rename-drift paths + 6 dropped `rtl/` prefixes. Reconcile against `soc_subsystem.f` line-for-line rather than patching in isolation.
3. Rebuild `soc_verification.prj` from the corrected `.f`. It must additionally **add** the four RF class-layer files it currently omits (`rf_monitor_if.sv`, `rf_monitors.sv`, `rf_monitor_env.sv`, `rf_mon_probe.sv`) — see 0.5.
4. Elaborate `riscforge_soc_subsystem` standalone, no TB, under **XSim** first, then **VCS**. Standalone elaboration isolates missing-source failures from TB wiring failures.

**Outputs**
- 14 recovered `.sv` files, each with a recorded provenance line (URL/commit or server path).
- Corrected `infrastructure/soc_verification.f` and `.prj`.
- `infrastructure/M0_recovery_log.md` — per-file provenance + the exact old→new path mapping table.
- `infrastructure/elab_only.f` — a TB-free filelist, so downstream workers can run elaboration independently of TB health.

**Exit criteria (all must hold)**
- [ ] `grep`-level proof that zero source files in `soc_verification.f` resolve to a missing path (re-run the path-resolution audit used to produce table 0.2; expect `0` unresolved).
- [ ] `xelab` elaborates `riscforge_soc_subsystem` on XSim with **zero** module-not-found / unknown-package errors.
- [ ] `vcs -full64` elaborates the same top with **zero** errors.
- [ ] **Negative control:** a deliberate typo injected into one filelist path *must* fail the audit script. A path checker that cannot fail is the same vacuity trap `STEP4_SPEC.md` §10 warns about.
- [ ] UART loopback proven at RTL level: `apb_uart` TX→RX through `uart_sin_i`/`uart_sout_o` observed on waveform, proving the recovered OBI UART is functional and not merely elaboratable.
- [ ] GPIO `apb_to_reg` path proven: one 32-bit APB write to a GPIO output register produces the expected `gpio_out` bit.

**Gate to M4:** `M0_recovery_log.md` merged + elaboration green on both simulators. No M4 worker may begin before this.

---

### W1 — Fault-Injection Matrix Hardening *(M2)*

**Owner:** 1 worker. **Runs parallel to W0.**

**Inputs**
- `step4_checkers/STEP4_SPEC.md` §14.1–14.5 — the authoritative open-items list.
- `axi_lite_to_apb/axi_lite_to_apb.sv` — the real bridge (present; not blocked by W0).
- `step4_checkers/{step4_pkg,step4_hub,step4_reporter,step4_axi_sva,step4_apb_sva,step4_path_scoreboard,step4_fault_inject,step4_disasm}.sv`
- `run_step4.ps1` — already real, already self-verdicts with `exit 1`.
- `STEP4_SPEC.md` §10 — the six reproducible XSim constraints (interface codegen, module-as-port-type, `$past` in action blocks, `axi_lite_to_apb` unelaboratable on XSim, undriven output → X, function-local bit-select).

**Tasks**
1. **§14.1 — go green on the real bridge.** Delete `step4_apb_bridge_model` (`step4_smoke_tb.sv:600`). Re-bind the matrix directly to `axi_lite_to_apb` and run under **VCS/Xcelium**, where the array APB ports elaborate. Do not patch the model — §14.1 explicitly prescribes deletion. The matrix must remain reachable on XSim for day-to-day use via a reduced bridge-direct variant; document any case that cannot run on XSim and why.
2. **§14.2 — assert the timeout-ordering invariant.** Add the directed test: APB monitor must always answer before AXI monitor, else the APB error is swallowed upstream. Currently `PATH-3012` is bound but unasserted.
3. **§14.3 — implement `REG-4001`.** Sub-word write (`pstrb != 4'b1111`) to GPIO must be answered with PSLVERR and must suppress the register write. Belongs with `register_predictor` (M3 scope) but is defined in the M2 check-ID table, so it is closed here.
4. **§14.5 — prove the decoupling forwarder.** `ev_q` depths are 4–8 with free-running pointers; an observer firing more checks in one cycle than the forwarder drains loses the oldest. Force `evt_overflow` non-zero by construction (deepen one queue, or compress drain) and show the oldest event is the one lost, i.e. the documented bound is real.
5. **§14.4 — bind `xbar_mst_req/resp[0..1]`** (ISRAM, DSRAM) if and only if SRAM agents go multi-transaction. Otherwise close with a written justification; do not silently drop.
6. **Close the M3 wiring gap (0.4).** Give each checker a `failure_reporter` handle and route findings through `report_failure(layer, check_id, ...)` with proper IDs: `AXIL-1001..`, `APB-2001..`, `PATH-3001..`, `REG-4001..`, `IRQ-5001..`. This is what makes `LAYER_PROTOCOL`/`LAYER_PATH` reachable and gives the blame engine something to absorb.

**Outputs**
- Green 11-case fault-injection matrix under VCS/Xcelium on the real bridge.
- `step4_bind.svh` either included via `step4_sim.f` or explicitly retired, with the reason recorded.
- `checkers/*.sv` updated to call `report_failure` with layer + namespaced check-ID.
- `STEP4_SPEC.md` §14 rewritten: each of 14.1–14.5 marked closed with the evidence that closed it.

**Exit criteria**
- [ ] All 11 matrix cases green against the real `axi_lite_to_apb`; expected check-ID matches actual in every case, and the case table in `STEP4_SPEC.md` is updated to the real check-IDs (currently it uses short names like `PATH_STRB` while §9.1 documents `PATH-3007` — **reconcile these two tables**, they disagree).
- [ ] **Vacuity:** each case must prove a *non-zero* finding count. A case that reports 0 findings is a FAIL, not a pass. This is the specific failure mode §10 item 4 documents (an undriven `o_penable` made the scoreboard report "0 findings", indistinguishable from a pass).
- [ ] **Negative control:** re-enable one previously-failing injection and confirm the checker *does* fire; then revert. A matrix that only ever passes proves nothing.
- [ ] Clean-traffic run reports exactly 0 findings — non-vacuously, with `total_observed > 0` printed alongside.
- [ ] `evt_overflow` observed non-zero in a constructed test.
- [ ] Disassembler self-test (`step4_disasm_tb`) still green — §8.3 found 5 wrong-output bugs, so this gate must not be dropped.
- [ ] `run_step4.ps1` exits 0 on XSim for the XSim-eligible subset, and its verdict logic is itself audited for vacuity.

---

### W2 — Dual-Simulator Regression Harness *(M4)*

**Owner:** 1 worker. **Starts only after W0 gate.**

**Inputs**
- Corrected `soc_verification.f` / `.prj` from W0.
- Checkers wired to the reporter from W1 task 6.
- `regression/elf_to_hex_clean.py` — working pure-Python ELF32-LE splitter, matches `tests/bsp/link.ld` (ISRAM `0x00010000/32K`, DSRAM `0x00020000/32K`).
- Server credentials in `rtl/AGENTS.md` §"Remote VLSI Servers": VCS `/home/iiita/Synopsys/Installed_tools/vcs/U-2023.03` on `172.16.33.48`.
- `Verification/run_vcs.sh` — currently core-only (`tb1_interrupts.f`, `-top core_interrupt_tb`). Needs a SoC-level sibling.

**Tasks**
1. **Rewrite `run_regression.ps1` for real.** Invoke `xvlog`/`xelab`/`xsim` and capture `$LASTEXITCODE` per stage. Increment `$failedCount` on non-zero exit and on watchdog timeout. Propagate a non-zero process exit so CI can gate on it. Fix the `.prj` path to `infrastructure/`. **Add `stage2_watchdog` to `$testList`** (currently missing).
2. **Decide the verdict source of truth.** The script must parse a machine-readable verdict, not "did it not crash". Add a `[VERDICT] stage=<n> result=PASS|FAIL findings=<n> retired=<n> bus_txns=<n>` line per stage; `run_regression.ps1` parses this. Anything less re-creates 0.3.
3. **Wire `-Target remote` to actually invoke VCS.** New `Verification/run_vcs_soc.sh`: compile `soc_verification.f` with `vcs -sverilog -full64 -debug_access+all -kdb +define+FSDB`, run `soc_tb_top` with the same plusargs as local, emit the identical `[VERDICT]` line. Both paths must agree.
4. **Generate `soc_verification.prj` from `soc_verification.f`** by a checked-in script, so the two cannot drift. They have already drifted (0.2).
5. **Activate `rf_mon_probe` in `soc_tb_top`** or formally retire it. If activated: parameterise the DUT instance name (`u_dut` vs `dut`) and reconcile the signal-source mismatch (`core_axi_req`/`apb_req[]` vs `m0_*`/`apb_p*`). If retired, delete the dead 1009+523 lines from the `.f` and record the decision.
6. **Firmware build path.** Confirm `riscv64-unknown-elf-gcc` on PATH; `elf_to_hex_clean.py` handles ELF→hex. Emit `<stage>.elf` into `Verification/build/` (does not exist yet; created by the script at L22).

**Outputs**
- Working `regression/run_regression.ps1` (real execution, real exit codes, all 7 stages).
- New `Verification/run_vcs_soc.sh`.
- `regression/gen_prj.py` (single-source filelist→prj).
- `regression/VERDICT.md` — the machine-readable contract both simulators emit.
- Build artifacts: `Verification/build/<stage>{.elf,_imem.hex,_dmem.hex}`.

**Exit criteria**
- [ ] `-Target local` runs all **7** stages under XSim and exits non-zero if **any** stage fails. **Negative control: deliberately corrupt one stage's hex and confirm the run FAILS and `$failedCount > 0`.** Without this, the harness reproduces defect 0.3 in a new costume.
- [ ] `-Target remote` runs the same 7 stages under VCS on `172.16.33.48` and exits non-zero on any failure.
- [ ] Local and remote `[VERDICT]` lines agree on `result=` and on `findings=0`.
- [ ] A stage that reports `CMD_PASS` while `findings > 0` is correctly scored **FAIL**.
- [ ] `soc_verification.prj` regenerated by script; a diff against the checked-in copy is empty.
- [ ] One clean full-local regression run logged end-to-end with per-stage timing.

---

### W3 — 7-Stage Proof Suites with Vacuity Guards *(M5)*

**Owner:** 1 worker per stage pair, or 1 sequential worker. **Starts after W2.**

**Inputs**
- Working harness from W2.
- `tests/bsp/` — `crt0.s`, `link.ld`, `mailbox.h`, `soc_regs.h`, `test_harness.h`, `trap_handler.s`, `isr_dispatch.c` (all present).
- `tests/drivers/` — all 5 (uart, timer, gpio, i2c, spi) present with state recovery.
- `tests/suites/stage{1..7}/main.c` — 113/90/105/149/42/64/52 lines respectively.
- `soc_tb_top.sv:513` — existing single-point vacuity guard.
- `STEP4_SPEC.md` §10 — vacuity is a known, recurring failure mode in this project.

**Task 0 (must precede any stage work): harden the vacuity guard.**
Replace the single check at `soc_tb_top.sv:513–519` with the 4-conjunct guard from `PROJECT.md` Feature 41:

```
PASS  ⟺  mb_cmd == CMD_PASS
     ∧  retired_instr_total > 0
     ∧  bus_transaction_total > 0        (AXI + APB combined)
     ∧  n_find == 0
```

Expose all four as separate counters in the `[VERDICT]` line so a vacuous pass is *diagnosable*, not just rejected. Mailbox encodings already match (`mailbox.h` = `tb_pkg.sv` = `0xC0DEC0DE` / `0xBAADF00D` / `0xDEADBEEF`) — no change needed.

**Per-stage tasks and exit criteria**

| Stage | Proves | Exit criteria |
|---|---|---|
| 1 `hello` | crt0 + link.ld + DSRAM mailbox console streaming | `CMD_PASS`; mailbox PASS observed by TB; char stream non-empty; `retired > 0`; `bus_txns > 0` |
| 2 `watchdog` | 1M-cycle timeout, buffer freeze, last-PC capture, blame-engine report | Induced hang trips the watchdog; `step4_report.txt` written; all 6 ring buffers frozen (`head_ptr` held); blame layer correct. **Currently omitted from `$testList` — must be re-added** |
| 3 `monitor_count` | exactly 20 retired instrs + 20 LSU stores, 0 spurious bus events | Counts exact, not `>=`; `n_find == 0`; AXI/APB event counts equal expected |
| 4 `fault_inject` | unmapped APB hole `0x4000_3800` → DECERR → Load Access Fault → handler adjustment | `mcause` == Load/AMO access fault; `mepc` advanced; handler completes; `CMD_PASS` |
| 5 `reg_sweep` | 32-bit aligned MMIO read sweep confirming HW reset defaults across all 6 APB IPs | Every read matches `register_predictor` shadow; **timeout sentinels `0xDEADBEEF` (APB) and `0xDEADDEAD` (AXI) explicitly rejected as register values** (`STEP4_SPEC.md` §8.4) |
| 6 `polled_periph` | UART loopback, Timer 0 progress, GPIO atomic SET/CLEAR/TOGGLE, SPI transfer, I2C recovery | Each peripheral exercised through its driver; GPIO sub-word write returns PSLVERR (closes `REG-4001` from W1); I2C recovery path taken and verified |
| 7 `nested_irq` | 2-level preemption, canary integrity across 5 ISR invocations, 0 GPR corruption | 5 ISR invocations observed by IRQ monitor; canary intact; `irq_predictor` reports 0 mismatches; no illegal preemption; no shadow-stack overflow |

**Outputs**
- Hardened vacuity guard in `soc_tb_top.sv`.
- 7 passing stages under both XSim and VCS.
- `Verification/tests/suites/STAGE_RESULTS.md` — per-stage `[VERDICT]` capture, retired/bus counts, finding counts, runtime.
- `tests/suites/stage<N>/` each with a `README.md` stating what it proves and what would make it fail.

**Exit criteria (suite-level)**
- [ ] All 7 stages `PASS` under **both** simulators, with `n_find == 0` and all 4 vacuity conjuncts non-trivially satisfied.
- [ ] **Anti-vacuity audit — mandatory.** For each of the 7 stages, perturb the firmware so the test *should* fail (e.g. invert one expected register value in stage 5, miscount in stage 3) and confirm the harness reports **FAIL**. A stage that cannot be made to fail is not a test. Record all 7 perturbations in `STAGE_RESULTS.md`.
- [ ] Stage 2 watchdog proven by an induced hang, not by raising the timeout.
- [ ] `stage2_watchdog` present in `$testList` and green.
- [ ] Zero `TIMEOUT`-terminated stages (a stage that ends in watchdog is a failure, never a pass).
- [ ] Full-suite run completed on XSim and VCS with logs archived.

---

## 3. Swarm roster & sequencing

| Worker | Milestone | Start | Depends on | Critical path |
|---|---|---|---|---|
| **W0** RTL Recovery + Filelist | M0 | t=0 | — | **YES — longest lead, do first** |
| **W1** Fault-Injection Hardening | M2 | t=0 (parallel to W0) | — | YES (input to W2) |
| **W2** Dual-Sim Regression Harness | M4 | after W0 gate | W0, W1 | YES |
| **W3a** Vacuity Guard + stages 1–3 | M5 | after W2 gate | W2 | — |
| **W3b** Stages 4–5 | M5 | parallel to W3a | W2 | — |
| **W3c** Stages 6–7 | M5 | parallel to W3a | W2 | — |

W0 and W1 are **independent and start immediately**. W3a/b/c parallelise once W2 clears.

**Inter-worker handoff gates** — each is a hard `stop`, not a soft dependency:
- **W0 → W2:** elaboration green on XSim **and** VCS, zero unresolved filelist paths, negative control on the path auditor demonstrated.
- **W1 → W2:** matrix green on the real bridge, vacuity counters non-zero, checkers routed through `report_failure`.
- **W2 → W3:** all 7 stages run (not necessarily pass) under both simulators; `[VERDICT]` contract emitted and parsed; deliberate-failure negative control demonstrated.

---

## 4. Programme-level risks

| # | Risk | Sev | Mitigation |
|---|------|-----|------------|
| R1 | OBI-UART / `register_interface` sources **unrecoverable** — no upstream copy, no server copy | **Critical** | W0 gates everything. If both retrieval routes fail, escalate immediately; the fallback (hand-written UART) invalidates stage 6 UART loopback and must be an explicit, documented programme decision, not a silent substitution |
| R2 | Recovered sources are version-mismatched vs `apb_uart-main/include/apb/typedef.svh` | High | Elaborate standalone first; the `apb_req_t`/`apb_resp_t` typedef macro is the integration seam |
| R3 | XSim cannot run the real bridge (§10.4, array APB ports) | Medium | Expected and accepted — the matrix goes green on VCS/Xcelium per §14.1. Document which cases are XSim-ineligible |
| R4 | Known core bugs in `rtl/AGENTS.md` (JALR bit-0, LHU misalignment, bubble `illegal_instr`, CSR write gate) surface as stage failures | High | Distinguish RTL defect from checker defect via the blame layer before "fixing" either. Do not patch DUT RTL to make a stage pass |
| R5 | Vacuous pass reappears in a new costume | High | Every stage requires a demonstrated-failure perturbation (W3 exit criteria). Non-negotiable |
| R6 | Checkers become over-fitted to green stages | Medium | Matrix cases use recorded expected check-IDs; W1 negative control re-enables a known failure |
| R7 | VCS server unavailable | Medium | W2 must also be green locally on XSim; remote is a parallel gate, not the only one |
| R8 | `evt_overflow` bound never exceeded → forwarder limit unproven | Medium | W1 task 4 forces it by construction |

---

## 5. Definition of done

- [ ] W0: 14 sources recovered with provenance; filelists repaired; elaboration green on 2 simulators; auditor negative control demonstrated.
- [ ] W1: 11-case matrix green on the real bridge, non-vacuously; `REG-4001`/`PATH-3012` implemented; `evt_overflow` proven; checkers wired to `report_failure`; `STEP4_SPEC.md` §14 closed.
- [ ] W2: `run_regression.ps1` really runs 7 stages on 2 simulators; deliberate failure → non-zero exit; `run_vcs_soc.sh` emits the same `[VERDICT]`; `.prj` script-generated.
- [ ] W3: 7 stages green on 2 simulators; 4-conjunct vacuity guard live; **all 7 stages demonstrated to fail when perturbed**; results archived.

**Not in scope for this plan:** RTL bug fixes in `riscv_core/` (R4 — diagnosed and reported, not fixed); synthesis; formal property closure; coverage closure beyond the functional bars above.
