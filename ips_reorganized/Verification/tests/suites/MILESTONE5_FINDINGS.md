# Milestone 5 — Stage 1..7 Proof Suite: Findings & Handover

Date: 2026-10-02
Scope: `Verification/tests/suites/stage1_hello` .. `stage7_nested_irq`, plus the
BSP, drivers, and the testbench-side anti-vacuity guard they depend on.

---

## 1. What was delivered

All seven bare-metal stages are implemented and **compile clean** with the real
toolchain (`riscv64-unknown-elf-gcc`, `-march=rv32im_zicsr -O2 -Wall -Wextra`):

```
stage1_hello          ELF OK   text=5716  data=12  bss=284
stage2_watchdog       ELF OK   text=3956  data=4   bss=288
stage3_monitor_count  ELF OK   text=5548  data=4   bss=360
stage4_fault_inject   ELF OK   text=6468  data=4   bss=304
stage5_reg_sweep      ELF OK   text=6828  data=4   bss=280
stage6_polled_periph  ELF OK   text=8100  data=4   bss=280
stage7_nested_irq     ELF OK   text=7192  data=12  bss=304
```

New / modified files:

| File | Change |
|:---|:---|
| `tests/bsp/proof_activity.h` | **new** — activity attestation primitives |
| `tests/bsp/proof_activity.c` | **new** — counter/scratch definitions |
| `tests/bsp/mailbox.h` | opcode fix, attestation word, `mailbox_halt()` |
| `tests/bsp/test_harness.h` | `TEST_REQUIRE_ACTIVITY`, `TEST_ASSERT_NE`, arg0 fix |
| `tests/bsp/soc_regs.h` | `mie`/`mip` helpers, `IRQ_ID_*`, `MCAUSE_*` |
| `tests/bsp/crt0.s` | removed boot-stopping illegal CSR write |
| `suites/stage{1..7}_*/main.c` | rewritten (see §3) |
| `infrastructure/tb/soc_tb_top.sv` | anti-vacuity guard, IRQ hookup fix, stage-2 inversion |
| `infrastructure/checkers/failure_reporter.sv` | added `n_find` fatal counter |
| `infrastructure/soc_verification.f` | filelist paths repaired |
| `regression/run_regression.ps1` | actually runs the sims, judges logs, exits non-zero |
| `regression/build_stages.sh` | **new** — WSL build harness |
| `infrastructure/fix_filelist.py` | **new** — filelist path validator |

---

## 2. BLOCKERS — the SoC cannot elaborate yet

These are **pre-existing** and independent of Milestone 5. No stage can be
simulated until they are resolved. Do not debug the stages first.

### B1 — Missing vendor IP: `obi_uart` (7 modules)
`apb_uart-main/rtl/apb_uart_wrap.sv:63` instantiates `obi_uart`, but none of
`obi_uart.sv`, `obi_uart_register.sv`, `obi_uart_baudgen.sv`, `obi_uart_rx.sv`,
`obi_uart_tx.sv`, `obi_uart_interrupts.sv`, `obi_uart_modem.sv` exist anywhere
in the tree. **UART peripheral dead** → blocks stages 5, 6, 7 and the whole TB.

### B2 — Missing vendor IP: `register_interface` (5 modules)
`gpio-master/gpio_reg_top.sv:15455` includes `register_interface/typedef.svh`,
but no `register_interface/` directory exists. Missing: `reg_intf`, `apb_to_reg`,
`prim_subreg`, `prim_subreg_arb`, `prim_subreg_ext`. **GPIO peripheral dead.**

### B3 — Mailbox opcode mismatch (FIXED here, but note the blast radius)
`tb_pkg.sv:168-170` defines `CMD_PASS = 32'hC0DE_C0DE`, `CMD_FAIL = 32'hBAAD_F00D`,
`CMD_HALT = 32'hDEAD_BEEF`. The old `mailbox.h` used `0x1` / `0x2` / `0xD0`.
**Every stage would have timed out instead of reporting.** `mailbox.h` now
mirrors `tb_pkg.sv` exactly. Any other consumer of the old constants (the
`tb1_*` tests under `Verification/`) must be re-checked.

### B4 — Illegal CSR write in `crt0.s` (FIXED here)
`crt0.s` did `csrw 0x7C0, zero` (mintprio). CSR `0x7C0` is **not implemented** in
`riscv_core/rtl/csr_regfile.v` (decodes only 300/304/305/340/341/342/343/344/
B00/B02/B80/B82), so this took an illegal-instruction trap before `main()` was
ever reached. Replaced with `csrw mie, zero` / `csrw mip, zero`.

### B5 — `soc_tb_top.sv` probed nets that do not exist (FIXED here)
The TB connected `dut.u_core.irq_req`, `.irq_ack`, `.irq_ret` and a 5-bit
`.irq_id`. The core has **none** of those. `top.v:222-225` exposes
`irq_pending`, `irq_winner_id[4:0]`, `irq_winner_class[1:0]`, and `irq_id[30:0]`.
The architectural ack point is `trap_commit_valid & trap_commit_is_interrupt`
(`top.v:252`) and the return point is `mret_commit` (`top.v:253`).
The `irq_monitor` port list also did not match at all — the TB passed 5 ports
where the monitor declares 21. All reconnected.

### B6 — `irq_predictor` was fed the wrong Timer 0 bit (FIXED here)
`soc_tb_top.sv:316` passed `timer0_irq[0]` (overflow) while the DUT wires
`timer0_irq_o[1]` (compare) to `timer_irq_i` → MTIP (`riscforge_soc_subsystem.sv:1249`).
The predictor would have modelled a source the core never sees. Now `timer0_irq[1]`.

### B7 — Broken filelist (FIXED here)
`soc_verification.f` referenced `SOC_FILES/`, `uart/rtl/`, `apb_timer/apb_timer/`,
`spi/spi_master/`, `RTL_SOC/rtl/`, `bootloader/rtl/` — **none exist**. It also used
VCS-only `+incdir+` and `-timescale`/`-top`, which `xvlog` 2022.2 rejects outright.
All paths repaired and validated by `fix_filelist.py`.

### B8 — `run_regression.ps1` never ran anything (FIXED here)
The old script did `$passedCount++` unconditionally, printed
`"Simulation command prepared: ..."` and exited 0 for every test. **7/7 green
without a single simulation.** It also omitted `stage2_watchdog` from the list.
The new script compiles, runs, parses the log for the pass marker, rejects any
run containing a vacuity/fatal line, reports `BLOCKED` distinctly, and exits
non-zero unless everything passed.

---

## 3. Per-stage design

Anti-vacuity is enforced by **two independent halves** that do not trust
each other:

* **Firmware** (`proof_activity.h`): `proof_dsram_signature()` writes a
  seed-dependent pattern, reads all 16 words back and folds them into an FNV-1a
  checksum. Verified in the disassembly to be 16 real `sw` + 16 real `lw` — the
  loads are not elided. `proof_mmio_ping()` does a bounded read-modify-write on
  an approved probe register and checks the value that physically came back.
  `TEST_REQUIRE_ACTIVITY()` then enforces a declared minimum before PASS.
* **Testbench** (`soc_tb_top.sv`): a firmware PASS is treated as a *request*.
  The run is only green if **G1** retired>0, **G2** AXI beats>0, **G3** APB
  transfers>0, **G4** `n_find==0`, **G5** firmware attestation word != 0,
  **G6** core `minstret` advanced. All six are printed on success so a green log
  still shows what the hardware did.

| Stage | Proves | Activity gate | Notes |
|:--|:--|:--|:--|
| 1 | BootROM→ISRAM handoff, crt0 `.bss` clear, `.data`/`.rodata` load, console streaming, 2-aperture bus liveness | 8 DSRAM, 6 MMIO, 2 slots | Two different seeds must give two different signatures (catches a stuck-at-constant DSRAM) |
| 2 | Watchdog fires, freeze buffers retain state, blame engine attributes to LAYER_FIRMWARE | **inverted** | Never calls PASS. Publishes evidence, then spins. TB inverts the verdict: timeout = pass, and a firmware PASS = **hard failure** |
| 3 | Exactly 20 DSRAM stores, forward + reverse read-back, sustained 8-read MMIO burst | 16 DSRAM, 14 MMIO, 3 slots | Zero MMIO in phase 1, so "no APB beats yet" is a real assertion, not a tautology |
| 4 | `0x4000_3800` decode hole → DECERR → mcause **5** (load) and **7** (store); mepc advance resumes; post-fault recovery | 16 DSRAM, 10 MMIO, 2 slots | Pre-fault health proven first, so "bus dead" and "fault caught" are distinguishable. `volatile` sink prevents GCC folding the load away |
| 5 | Reset values per aperture, verified **against RTL source** | 8 DSRAM, 24 MMIO, **6 slots** | GPIO `0x000`/`0x380` skipped — see D1. UART LSR checked for stability only — see D2 |
| 6 | UART loopback byte identity, timer monotonicity, GPIO pin loopback + atomic SET/CLEAR/TOGGLE, SPI JEDEC RDID, I2C EEPROM write→read-back | 8 DSRAM, 40 MMIO, 5 slots | All GPIO checks poll (`gpio_input_stage` registers the pin). I2C round-trips through the AT24C02 BFM |
| 7 | MTIP delivery, **2-level preemption** (Class 1 SPI ID 18 preempted by Class 2 Timer 0 ID 7), 12 callee-saved canaries, outer-handler canary across nested entry | 16 DSRAM, 6 MMIO, 3 slots | `sw_nest_depth` makes nesting *observable in firmware*; if nesting is not seen the stage **fails** (0x7A01/0x7073), it does not skip |

---

## 4. Open defects found (not fixed — need a decision)

**D1 — `register_predictor` GPIO offsets are wrong.** Lines 174-177 treat GPIO
`0x000` as `INTRPT_STATUS_W1C` and `0x380` as an interrupt-enable register.
`gpio_reg_pkg.sv` puts `INTRPT_STATUS` at **`0x580`** and `INTRPT_RISE_EN` at
`0x380`. So a write to `0x000` wrongly clears the modelled `irq_status`, and
`INTRPT_STATUS` (0x580) is not modelled at all. `gpio_init()` writes `0x380`,
which the predictor tracks as a plain RW register — benign today, but the model
is wrong. Stages avoid `0x000`; the checker should be fixed.

**D2 — UART LSR reset value is unverifiable.** The RTL that implements LSR
(`obi_uart_register.sv`) is missing (B1), so the old assertion
`(lsr & 0x60) == 0x60` cannot be confirmed from source. Stage 5 now checks LSR
*stability* and proves the UART write path via LCR (real, predictor-modelled
state) instead. Pin the constant once B1 is resolved.

**D3 — `isr_dispatch.c` cannot distinguish interrupt from exception.**
`idx = mcause & 0x1F` maps exception 7 (store access fault) and interrupt 7
(MTIP) to the same slot. Harmless today because stage 4 runs with `mie=0`, but
it is a latent collision. Recommend keying on `mcause[31]` as well.

**D4 — `spi_clk_div` is 8 bits, predictor shadows 32.**
`spi_master_apb_if.sv:42` declares `output logic [7:0] spi_clk_div`, but
`register_predictor` stores/reads it as 32-bit. Any SPI write above `0xFF`
reads back truncated and trips the predictor **on a correct design**. Stages
keep SPI values ≤ 0xFF; the predictor should mask to 8 bits.

**D5 — `mmio_path_scoreboard` GPIO range disagrees with the RTL.**
Scoreboard line 35 says GPIO is `0x4000_3000..0x4000_3FFF`; the actual
`apb_addr_map[3]` is `0x4000_3000..0x4000_37FF`. Not currently harmful (a
decode error generates no APB transaction, so no check fires) but it should
match.

**D6 — Timer 1 interrupts are unusable.** `timer1_irq_o[0..3]` map to
`mip[23..26]`, but `wb_trap_mret_commit_controller.v:84-94` only emits a gateway
clear for IDs 7/16/17/18/19/27, and `irq_predictor`'s `class_map` has no entry
for 23-26. Enabling a Timer 1 interrupt commits a trap with no gateway clear →
re-trap storm. `soc_regs.h` documents this so nobody tries it.

---

## 5. How to proceed

1. Resolve **B1** and **B2** (restore vendor IP, or re-point `apb_uart` at
   `reg_uart_wrap.sv` and replace `gpio_reg_top` with a hand-written
   `gpio_apb_wrap` + simple register file).
2. Then `cd Verification/infrastructure && xvlog -sv -f soc_verification.f -i ../../axi_lite_xbar/include -i ../../apb_uart-main/include -i ../../apb_i2c-master -i tb`
   until clean, then `xelab`/`xsim`.
3. Build + run all stages: `Verification/regression/run_regression.ps1`
   (or `wsl bash Verification/regression/build_stages.sh` for compile-only).
4. A stage is green only if the log contains `[MAILBOX PASS]` (or
   `[STAGE2 PASS]`) **and** no `VACUITY VIOLATION` / `FATAL` / `MAILBOX FAIL`.
