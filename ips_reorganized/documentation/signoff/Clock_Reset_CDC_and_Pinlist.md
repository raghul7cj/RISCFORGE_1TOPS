# RISCFORGE SoC - Clock/Reset/CDC Architecture and Chip IO Pin List (as implemented)

Tape-out checklist items: **1.10** (clock / reset / CDC architecture) and **1.11** (pin list / chip IO table).

Status: documentation of the RTL **as implemented**. No RTL or testbench file was edited and no bug was fixed in producing this file. Where the RTL looks questionable, the item is recorded under *Observations* as a fact only.

Conventions:

- All paths are relative to the `ips/` root unless stated otherwise. `file:line` refers to the file as it exists on disk at the time of writing (see Section 0.2 for timestamps).
- "UNVERIFIED" marks a claim that was not confirmed by reading the cited source, or that rests on a stale artifact.
- "Top" = `RTL_SOC/riscforge_soc_subsystem.sv`. "Core" = `riscv_core/rtl/top.v`.

---

## 0. Scope and provenance

### 0.1 Device under documentation

- Module: `riscforge_soc_subsystem` (`RTL_SOC/riscforge_soc_subsystem.sv:232`), port list at `:259-333`, 1413 lines total.
- Design compile list: `RTL_SOC/soc_subsystem.f` (design only, no TB).
- Instantiated block inventory used for this document (from the instance list in the Top): bootloader, RV32IM core + `hybrid_mem_interface`, boot ROM, instruction-fetch demux, ISRAM/DSRAM (+ AXI bridges and SRAM muxes), `axi_lite_xbar`, `axi_lite_to_apb`, 6 APB timeout monitors, 1 AXI-Lite timeout monitor, I2C master, Timer 0, UART, GPIO, SPI master, Timer 1.
- Not instantiated: no AON timer, watchdog, CLIC, PLL, clock gate or clock divider block exists in the Top (grep of the Top for `aon|wdt|watchdog|pll|clk_div|boot_mode|strap` returns only a comment at `:1346`). `aon_timer/` and `clic-master/` directories exist in the repo but are not instantiated by the Top or listed in `soc_subsystem.f`.

### 0.2 Timestamps used for the current-vs-stale classification

| Item | Timestamp (file mtime) |
| --- | --- |
| `RTL_SOC/riscforge_soc_subsystem.sv` | 2026-11-02 20:00 |
| `apb_timer-master/rtl/timer.sv` | 2026-11-02 20:00 |
| `riscv_core/rtl/top.v` | 2026-10-29 23:19 |
| `bootloader/bootloader.sv`, `gpio-master/gpio*.sv`, `apb_i2c-master/apb_i2c.sv`, `bus_monitors/*.sv` | 2026-09-28 02:06-02:07 |
| `RTL_SOC/soc_subsystem.f` | 2026-10-02 13:37 |
| SpyGlass report (`spyglass/reports/spyglass_summary.rpt` header "Report Created on") | Wed Sep 9 2026 23:18:50 |
| JasperGold Superlint, top-level `jaspergold/reports/*` (report header Date) | Sep 10 2026 00:02:03 IST |
| JasperGold Superlint, `jaspergold/runs/soc_superlint_20261018_01/reports/*` (header Date) | Oct 18 2026 00:25:32 IST |
| JasperGold CDC/RDC, `spi_master_ip/jg/reports/cdc_violations.txt` (header Date) | Aug 30 2026 12:14:47 IST |

---

## 1. Clock architecture (checklist 1.10)

### 1.1 Clock inputs

| Clock | Port | Direction | Evidence |
| --- | --- | --- | --- |
| `clk_i` | top-level port | input | `RTL_SOC/riscforge_soc_subsystem.sv:259` |

There is **one** clock input port. No other clock port exists on the Top port list (`:259-333`).

### 1.2 Verification of "single clock domain"

Method: (a) every sequential-block sensitivity list in the compiled RTL directories (`axi_lite_xbar`, `axi_lite_to_apb`, `bus_monitors`, `apb_i2c-master`, `apb_timer-master/rtl`, `apb_uart-main/include/{obi,common_cells}`, `gpio-master`, `register_interface`, `spi_master_ip/spi_master`, `RTL_SOC`, `bootloader`, `riscv_core/rtl`, `instr_module`) was grepped for `posedge`/`negedge` on a signal other than the module clock/reset; (b) every clock pin of every instance in the Top was inspected (`:749, 767, 812, 841, 876, 899, 923, 960, 984, 1013, 1041, 1058, 1087, 1109, 1147, 1170, 1210, 1247, 1309, 1359, 1393`); all connect to `clk_i`.

Result: **single functional clock domain (`clk_i`) - VERIFIED for the Top and the RTL listed above.** Every sequential element found clocks on the positive edge of that module's `clk`/`clk_i`/`HCLK`/`CLK` port, which are all tied to `clk_i`. No negative-edge clocked flop and no flop clocked by a derived/gated signal was found. Residual exceptions to this verification:

- Testbench-only files that appear in the search directories (`axi_chan_compare.sv` with `clk_a_i/clk_b_i`, `axi_dumper.sv`, `axi_test.sv`, `*_tb.sv`) are verification utilities, not in `soc_subsystem.f`, and were not considered design clocks.
- The UART RTL actually compiled by the project tools is in `apb_uart-main/include/obi/` (see Observation O-9); it was grepped for sequential structure through the `FF` macro (`axi_lite_xbar/include/common_cells/registers.svh:47-48`, clock/async-reset style) and `sync` (`axi_lite_xbar/include/common_cells/sync.sv:27`). No second clock was found. Macro-expanded flops that use `FFNR` and other macro variants were not individually enumerated: UNVERIFIED for those.

### 1.3 Derived "clocks" - generated clocks vs. enables

None of the following is a clock domain; each is a **data/enable/output signal on `clk_i`**:

| Function | Mechanism | Generated clock or enable? | Evidence |
| --- | --- | --- | --- |
| SPI SCK (`spi_clk_o`) | 8-bit counter `counter` vs `counter_trgt` toggles a **register** `spi_clk` (output only). Divider is `clk_div` (APB CLKDIV register). `spi_rise`/`spi_fall` strobes are produced from the toggle for the clk_i-domain logic. | Registered **output waveform**, not used as a clock internally. No `posedge spi_clk` exists in the compiled RTL. The JasperGold SPI CDC script nevertheless **declares** `spi_clk` as a derived clock for analysis only. | `spi_master_ip/spi_master/spi_master_clkgen.sv:31-77`; top output `:319` driven at `:1181`; `spi_master_ip/jg/cdc.tcl` (clock section) |
| I2C SCL (`i2c_scl_oen_o`) | Prescaler counter `cnt` reloads from `clk_cnt` (PRE register); `clk_en` strobe; SCL is the open-drain output-enable flop `scl_oen`. `scl_o` and `sda_o` are tied to constant 0. | **Enable** on `clk_i` (`clk_en`); SCL is a registered data output. | `apb_i2c-master/i2c_master_bit_ctrl.sv:203-224` (clk_en), `:357-531` (`scl_oen` updates), `:541-542` (constant 0) |
| UART baud | Counter-based baud/oversample enables (`baud_rate_edge_o`, `double_rate_edge_o`) from a divisor (DLL/DLM). | **Clock enables** on `clk_i`. | `apb_uart-main/include/obi/obi_uart_baudgen.sv:11,18-19,85-107` |
| Timer prescaler | `prescaler_int` (CTRL[5:3]) compared with `cycle_counter_q`; counter increments on match. | **Enable** on `clk_i`. | `apb_timer-master/rtl/timer.sv:50,72,82-90` |
| GPIO | No divided clock; input stage is a 2-stage synchroniser on `clk_i` (see Section 3). A "no_clk_gates" variant of the input stage is the one in the filelist. | n/a | `gpio-master/gpio_input_stage_no_clk_gates.sv`; `RTL_SOC/soc_subsystem.f` (GPIO section) |
| Soft-reset noise filter | Counter of `SoftRstFiltCycles` (default 16) `clk_i` cycles. | Counter on `clk_i`. | Top `:250, 529-552` |
| Bootloader flash power-up wait, reset hold | Counters `flash_wait_cnt_q` (`FLASH_POWERUP_CYCLES`, default 30_000) and `rst_hold_cnt_q` (`RESET_HOLD_CYCLES`, default 4). | Counters on `clk_i`. | `bootloader/bootloader.sv:181, 185, 357, 704-709, 774` |

### 1.4 AON / other domains

- No always-on domain, no separate low-power clock, no clock gating cell, no PLL/clock-mux in the Top. UNVERIFIED for the downstream layers (pad ring / chip top) which are not in the repo.
- `gpio-master/gpio_input_stage_no_clk_gates.sv` is the input-stage variant listed in `soc_subsystem.f` (GPIO section); its comment at `:16-21` contrasts it with a clock-gated version of the stage, and the synchroniser here runs on `clk_i` regardless of `en_i`.

### 1.5 Target frequency

No target frequency, SDC, or clock constraint file was found (`*.sdc` search under `ips/` excluding snapshots returned none). The only frequency references are a comment ("16 = 160 ns at 100 MHz", Top `:248-249`) and the TB clock period of 10 ns (`RTL_SOC/soc_imem_boot_tb.sv:187`, `:210`). See Ambiguity A-3.

---

## 2. Reset architecture (checklist 1.10)

### 2.1 Reset inputs

| Port | Polarity | Source of truth | Use |
| --- | --- | --- | --- |
| `hard_rst_ni` | active low | Top `:260` | Cold boot. Used raw as async reset of three top-level flop groups, and as input of the `sys_rst_n_raw` AND and of the `hard_rst_sync_q` chain (Section 2.3). |
| `soft_rst_ni` | active low | Top `:261`; described as "board push button" at `:523` | Warm boot. Never used raw internally (`:219-220, 523`); enters a 2-FF synchroniser then a noise filter. |

There is **no** software-triggered reset register, no watchdog reset and no reset output pin in the Top. The CPU cannot reset the SoC through any register found in the instantiated blocks (the INFRA tracker also lists the AON WDT as "does not exist", `INFRA_TRACKING.md:114`). Resets other than the two pins are produced by the bootloader FSM (Section 2.4).

### 2.2 Internal reset nets

| Net | Defined | Meaning |
| --- | --- | --- |
| `soft_rst_meta_q[1:0]` | Top `:531, 535-538` | 2-FF synchroniser of `soft_rst_ni`. Async reset by `hard_rst_ni` to `2'b11` (de-asserted). |
| `soft_rst_n_filt_q` | Top `:532, 540-552` | Filtered soft reset. Changes only after the synchronised level differs for `SoftRstFiltCycles` consecutive cycles. Async reset by `hard_rst_ni` to 1. |
| `sys_rst_n_raw` | Top `:499, 554` | `hard_rst_ni & soft_rst_n_filt_q` (combinational AND). |
| `sys_rst_sync_q[3:0]` / `sys_rst_n` | Top `:500, 556-559, 566` | 4-FF chain, async assertion on `sys_rst_n_raw`, synchronous de-assertion (shifts in 1). |
| `hard_rst_sync_q[3:0]` / `hard_rst_sync_n` | Top `:501, 561-564, 567` | 4-FF chain, async assertion on `hard_rst_ni`, synchronous de-assertion. Feeds bootloader only. |
| `core_rst_n`, `periph_rst_n`, `spi_rst_n` | Top `:504-506`; produced `bootloader/bootloader.sv:827-829` | Registered outputs of the bootloader FSM (`core_rst_q`, `periph_rst_q`, `spi_rst_q`). |

### 2.3 Reset synchroniser presence and style

| Reset | Assertion | De-assertion | Synchroniser | Evidence |
| --- | --- | --- | --- | --- |
| `hard_rst_ni` -> `soft_rst_meta_q`, `soft_rst_n_filt_q`, `soft_rst_cnt_q` | async (pin is the async reset) | **Not synchronised** (pin de-asserts directly on these flops' async reset) | none (these flops are the soft-reset sync/filter themselves) | Top `:535, 540` |
| `hard_rst_ni` -> `hard_rst_sync_q` -> `hard_rst_sync_n` | async | sync, 4-FF | yes, local 4-FF chain | Top `:561-567` |
| `hard_rst_ni & soft_rst_n_filt_q` -> `sys_rst_sync_q` -> `sys_rst_n` | async (including when the filtered soft reset falls) | sync, 4-FF | yes, local 4-FF chain | Top `:554-559, 566` |
| `soft_rst_ni` -> `soft_rst_meta_q` -> filter -> `soft_rst_n_filt_q` | n/a (data path, not an async reset) | n/a | 2-FF + 16-cycle noise filter | Top `:535-552` |
| `soft_rst_n_filt_q` -> bootloader `soft_rst_sync_q[1:0]` | synchronous handling in the clocked branch | synchronous | **second** 2-FF synchroniser inside bootloader on an already-synchronised signal | `bootloader/bootloader.sv:366-378, 603-622` |
| `core_rst_n`, `periph_rst_n`, `spi_rst_n` | flop outputs of bootloader; asserted by hard reset (async via `hard_rst_sync_n`) and by the sync warm-boot branch | released by FSM states `S_CLEAN_RELEASE`/`S_DONE`, `S_CLEAR_SRAM/S_FLASH_WAIT/S_INIT_CLKDIV` for SPI | no further synchroniser (they are flop outputs on `clk_i`) | `bootloader/bootloader.sv:566-592, 603-622, 720-740` |

### 2.4 Which reset reaches which block

| Reset net | Blocks (instance, reset port, line) |
| --- | --- |
| `hard_rst_ni` (raw pin) | Top reset logic only (`:535, 540, 554, 561`). |
| `hard_rst_sync_n` | `i_bootloader.hard_rst_ni` (`:1394`). |
| `soft_rst_n_filt_q` | `i_bootloader.soft_rst_ni` (`:1395`); `i_isram_axi_if.soft_rst_ni` (`:814`); `i_dsram_axi_if.soft_rst_ni` (`:901`); `sys_rst_n_raw` AND (`:554`). Inside both AXI->SRAM bridges the signal gates the SRAM write enable: `sram_we_o = sram_we_int & soft_rst_ni` (`RTL_SOC/axi_lite_sram_if.sv:45, 52, 62`). |
| `sys_rst_n` | `i_isram_axi_if` (`:813`), `i_isram_mux` (`:842`), `i_isram` / `imem_sram_wrapper` (`:877`), `i_dsram_axi_if` (`:900`), `i_dsram_mux` (`:924`), `i_axi_lite_xbar` (`:985`), `i_axi_lite_to_apb` (`:1014`), 6x `i_apb_timeout_monitor` (`:1042`), `i_axi_lite_timeout_monitor` (`:1360`). Timeout-monitor sticky outputs are "sticky until sys_rst_n" (Top `:329`). |
| `periph_rst_n` | `i_apb_i2c` (`:1059`), `i_apb_timer0` (`:1088`), `i_apb_uart` (`:1110`), `i_gpio_apb_wrap` (`:1148`), `i_apb_timer1` (`:1211`). |
| `spi_rst_n` | `i_apb_spi_master` (`:1171`). |
| `core_rst_n` | `i_boot_rom` (`:750`), `i_instr_fetch_demux` (`:777`), `i_riscv_core.rst` (`:1248`), `i_core_data_if` / `hybrid_mem_interface` (`:1310`). |
| none | `i_dsram` / `sram_sp` (no reset port; `RTL_SOC/sram_sp.sv:41` is a plain `posedge` flop). |

### 2.5 Modules using asynchronous reset

All reset-bearing sequential logic found uses an **asynchronous, active-low reset** (`posedge clk or negedge rst`), with these module-level facts (grep of sensitivity lists in the files listed in Section 1.2):

| Module / file | Async-reset sequential blocks (examples) |
| --- | --- |
| Top reset logic | `riscforge_soc_subsystem.sv:535, 540, 556, 561` |
| `bootloader` | `bootloader/bootloader.sv:369` (soft sync), `:566` (FSM + reset-output flops) |
| `apb_i2c` / bit/byte ctrl | `apb_i2c-master/apb_i2c.sv:70, 169, 198`; `i2c_master_bit_ctrl.sv:194, 204, 231, 245, 252, 266, 288, 302, 312, 318, 352`; `i2c_master_byte_ctrl.sv:167, 176, 191` |
| `timer` | `apb_timer-master/rtl/timer.sv:135` |
| UART (`obi_uart*` through `FF` macros, `sync`) | `registers.svh:47-48`; `sync.sv:27` (reset value `ResetValue`, default 0) |
| `gpio_input_stage`, GPIO regs | `gpio-master/gpio_input_stage_no_clk_gates.sv:34`; `register_interface/apb_to_reg.sv:47` |
| `apb_spi_master` and sub-blocks | `spi_master_apb_if.sv:99`, `spi_master_clkgen.sv:56`, `spi_master_controller.sv:518`, `spi_master_fifo.sv:49, 73, 88`, `spi_master_rx.sv:121`, `spi_master_tx.sv:112`, `apb_spi_master.sv:119, 132` (all under `spi_master_ip/spi_master/`) |
| `bus_monitors` | `apb_timeout_monitor.sv:61, 75, 96`; `axi_lite_timeout_monitor.sv:85, 191` |
| SRAM wrappers / fetch path | `RTL_SOC/axi_lite_sram_if.sv:177`, `sram_mux.sv:108`, `boot_rom.sv:69`, `instr_fetch_demux.sv:114` |
| RV32IM core | `riscv_core/rtl/{PC,decode_cycle,fetch_cycle,execute_cycle,memory_cycle,csr_regfile,irq_gateway,irq_arbiter,imem_controller,rv32m_unit,rv32m_mul,rv32m_div,hybrid_mem_interface}` (e.g. `PC.v:36`, `csr_regfile.v:138, 208`, `hybrid_mem_interface.sv:132, 216, 293`) |
| Library blocks (`axi_lite_xbar`, `fifo_v3`, `spill_register`, etc.) | via `registers.svh` `FF`/`FFL`/`FFARN` macros (`:47-48, 78, 125-126, 215, 234`), async-low reset |

Flops found **without** reset: `RTL_SOC/sram_sp.sv:41`, `instr_module/Instruction_Memory.v:34, 40`, `riscv_core/rtl/Register_File.v:34`, and in the I2C bit controller `i2c_master_bit_ctrl.sv:189` (`dscl_oen`) and `:326`. No synchronous-reset-only sequential block style was found in the compiled directories (UNVERIFIED for macro-expanded `FFNR` users and for `prim_subreg*.sv`, which were not opened).

### 2.6 Reset sequencing as implemented

Cold boot (`hard_rst_ni` low -> high):

1. `hard_rst_ni` asserts all async-reset flops immediately. `hard_rst_sync_q` and `sys_rst_sync_q` reset to 0 (`:557, 562`); bootloader FSM goes to `S_RESET`, `warm_boot_q=0`, `core_rst_q=periph_rst_q=spi_rst_q=0` (`bootloader/bootloader.sv:567-591`).
2. After `hard_rst_ni` high, `hard_rst_sync_n` and `sys_rst_n` release together after 4 `clk_i` cycles (`:556-567`; rationale at `:517-521`).
3. Bootloader FSM: `S_RESET` -> `S_CLEAR_SRAM` (AXI writes, if `TOTAL_CLEAR_WORDS != 0`) -> `S_FLASH_WAIT` -> SPI init and burst reads via APB/SPI -> `S_CLEAN_ASSERT` / `S_CLEAN_HOLD` (all three resets low for `RESET_HOLD_CYCLES`) -> `S_CLEAN_RELEASE` / `S_DONE` (all three resets high; `boot_done_o` = `state_q == S_DONE`) (`bootloader/bootloader.sv:754-770, 720-740, 830`).
4. `spi_rst_q` is released early (states `S_CLEAR_SRAM`, `S_FLASH_WAIT`, `S_INIT_CLKDIV`, `:721-726`) so the SPI master exists during the boot copy; `core_rst_n` and `periph_rst_n` stay low until `S_CLEAN_RELEASE`.
5. By the Top's own comment, `sys_rst_n` releases about 121k cycles before `core_rst_n` (`:771-772`, the "whole boot").

Warm boot (`soft_rst_ni` low -> high):

1. `soft_rst_ni` -> 2-FF -> 16-cycle filter (`:535-552`) -> `soft_rst_n_filt_q`.
2. `soft_rst_n_filt_q` low asynchronously asserts `sys_rst_sync_q` (via the AND, `:554-557`), clamps SRAM WE (`axi_lite_sram_if.sv:62`), and, after a further 2-FF in the bootloader, synchronously forces the bootloader to `S_RESET` with `warm_boot_q=1` and all three resets low (`bootloader/bootloader.sv:603-622`).
3. `S_RESET` with `warm_boot_q` goes straight to `S_CLEAN_ASSERT` (no SPI fetch, no AXI clear) (`bootloader/bootloader.sv:755-756`).
4. `soft_rst_n_filt_q` high: `sys_rst_n` releases after 4 cycles; bootloader sees the release after 2 cycles. Whether `soft_rst_ni` is held across the full filter window is not documented anywhere except the Top comment at `:247-250`.

Software/watchdog reset: none found. Interrupts to the core are level/pulse inputs only and cannot reset the SoC (fast_irq mapping at `:1275-1290`).

---

## 3. CDC / RDC crossing list (checklist 1.10)

Premise: there is a single clock domain (Section 1.2). The crossings below are therefore **asynchronous-input-to-`clk_i`** crossings, **reset-pin crossings**, and the **SPI source-synchronous MISO** path. No `reg_cdc`, `cdc_*`, `apb_cdc`, `isochronous` or clock-gate cell is instantiated in the Top, bootloader, GPIO, register interface, timer, I2C, SPI or fabric RTL (grep: zero matches). `apb_uart-main/include/apb/apb_cdc.sv` exists on disk but is not instantiated and is not in `soc_subsystem.f`.

### 3.1 Crossing list

| # | Signal (source -> dest) | Source domain | Synchroniser used | Evidence |
| --- | --- | --- | --- | --- |
| X1 | `hard_rst_ni` (pin) -> async reset of `soft_rst_meta_q`, `soft_rst_n_filt_q`, `soft_rst_cnt_q` | async external | none on de-assertion for these three flops | Top `:535, 540` |
| X2 | `hard_rst_ni` -> `hard_rst_sync_q` -> `hard_rst_sync_n` -> bootloader | async external | 4-FF reset synchroniser (async assert, sync de-assert) | Top `:561-567`, `:1394` |
| X3 | `hard_rst_ni & soft_rst_n_filt_q` -> `sys_rst_sync_q` -> `sys_rst_n` | async external (hard) + clk_i flop (soft) | 4-FF reset synchroniser; the AND is combinational on the async-reset path of the chain | Top `:554-559, 566` |
| X4 | `soft_rst_ni` (pin) -> `soft_rst_meta_q` | async external | 2-FF (`soft_rst_meta_q`) then 16-cycle noise filter | Top `:535-552` |
| X5 | `soft_rst_n_filt_q` -> bootloader `soft_rst_sync_q` | clk_i domain (already synchronised) | second 2-FF | `bootloader/bootloader.sv:369-378` |
| X6 | `uart_sin_i` (pin) -> UART RX | async external | `sync` module, `NrSyncStages = 2` (`obi_uart_pkg.sv:15`) then 3-sample majority filter | `apb_uart-main/include/obi/obi_uart_rx.sv:135-141, 147-176`; `axi_lite_xbar/include/common_cells/sync.sv:13-35` |
| X7 | `gpio_in_i[31:0]` (pins) -> GPIO input stage | async external | `sync` x32, `NrSyncStages = 2`, then a `serial_q` register used for edge detect | `gpio-master/gpio.sv:152-162`; `gpio_input_stage_no_clk_gates.sv:25-42` |
| X8 | `i2c_scl_i`, `i2c_sda_i` (pins) -> I2C bit controller | async external | 2-FF capture (`cSCL`, `cSDA`), then 3-sample glitch/majority filter (`fSCL`, `fSDA`, `sSCL`, `sSDA`) gated by `filter_cnt` | `apb_i2c-master/i2c_master_bit_ctrl.sv:229-241, 244-281`; pins at `apb_i2c.sv:160, 163` |
| X9 | `spi_sdi1_i` (pin, MISO) -> SPI RX shift register | external, **source-synchronous to `spi_clk_o`** which is itself a registered `clk_i` waveform | **none**: sampled directly into `data_int` on the `rx_edge` strobe | `spi_master_ip/spi_master/spi_master_rx.sv:78-84` (sdi1 -> `data_int_next`); no `sync` in any `spi_master/*.sv` |
| X10 | `test_mode_i` (pin) -> `axi_lite_xbar.test_i` | static/async external | none; used as a test-mode strap | Top `:262, 986` |
| X11 | UART modem inputs (`CTSN`, `DSRN`, `DCDN`, `RIN`) -> modem block | tied to constant 1 at the SoC | `sync` 2-stage exists in the block but inputs are constants | Top `:1126-1129`; `obi_uart_modem.sv:42-78` |
| X12 | `fetch_enable_i`, `boot_addr_i[31:0]` (pins) | n/a | **no load**: not connected to any logic | Top `:267-268`; only mentions at `:1239-1241`; JasperGold `INP_NO_LOAD` x2 (see 3.3) |

There is no crossing between two clock domains inside the chip, because only one clock exists. Reset-domain crossings (RDC) in the design are the multi-reset-net structure of Section 2.4: `sys_rst_n` (async-asserted, sync-released), `periph_rst_n`/`core_rst_n`/`spi_rst_n` (flop outputs of the bootloader on `clk_i`), and the raw `hard_rst_ni` into three flop groups (X1).

### 3.2 Per-block external inputs not individually synchronised

Only the inputs in X1, X9, X10 and X12 reach flops (or none) without a synchroniser chain of at least 2 flops dedicated to that input. For X9, the validity of direct sampling is a timing property of the SPI clock ratio and the board/flash MISO delay; it is **not** established by any report in the repo (see 3.3 and Ambiguity A-6).

### 3.3 Current SpyGlass / JasperGold findings (counts and categories only)

Classification rule: a report is "current" only if it post-dates the RTL files it analysed. Against the Top mtime of 2026-11-02 20:00 and bootloader/GPIO/I2C mtimes of 2026-09-28, **every report below is stale for the Top**, and the Sep 9/10 reports are also stale for the bootloader, GPIO and I2C. The 2026-10-18 JasperGold run is the closest to current.

| Report | Tool/goal | Date in report | Class | Counts and categories | Path |
| --- | --- | --- | --- | --- | --- |
| SpyGlass SoC lint | `lint/lint_rtl` and `lint/lint_turbo_rtl` only (`spyglass/run_spyglass.tcl:138-152`) | 2026-09-09 | **STALE** (pre-dates bootloader change of 09-28 and every Top change since) | 1292 messages, 0 waived. Errors: `W110` x33, `ErrorAnalyzeBBox` x3, `SYNTH_5273` x2, `W123` x2, `InferLatch` x1, `SYNTH_5260` x1 (sum 42). Reset-relevant: `STARC05-1.3.1.3` x1 (async reset signal `core_rst_q` used as non-reset data in `fetch_cycle.v:295`/`decode_cycle.v:242`, `spyglass/reports/spyglass_moresimple.rpt:119`), `STARC05-2.11.3.1` x3, `InferLatch` on `warm_boot_q` (`spyglass/spyglass_soc_lint_report.md` section 3.2, bootloader line 476 of the older bootloader). | `spyglass/reports/spyglass_summary.rpt`, `spyglass/reports/spyglass_turbo_summary.rpt`, `spyglass/reports/spyglass_moresimple.rpt`, `spyglass/spyglass_soc_lint_report.md` (`spyglass/lint_warnings.md` exists but was not read) |
| SpyGlass CDC / reset rules | **not run** | n/a | **ABSENT** | The summary lists no `Ac_*`, `Ar_*`, `Clock_*` or `Reset_*` rule IDs. The policy list in the header names `clock-reset`, but only lint goals were executed. `INFRA_TRACKING.md:90` labels the asset "SpyGlass lint + CDC"; the report files do not contain CDC results. | same as above |
| JasperGold Superlint, top-level reports | Superlint, `clock clk_i`, `reset ~hard_rst_ni ~soft_rst_ni` (`jaspergold/lint.tcl:16-20`) | 2026-09-10 | **STALE** | LINT: 1 Error, 25 Warning, 3 Info (CODINGSTYLE 20, FILEFORMAT 1, STRUCTURAL 8 with the 1 Error). DFT_FUNCTIONAL: 19 Warning. Tags: `OTP_NO_RGTM` 19, `OTP_UC_INST` 9, `MOD_NO_IPRG` 7, `OTP_NR_READ` 6, `MAC_NR_DMUL` 3 (Info), `INP_NO_LOAD` 2, `RST_IS_DCMB` 1 (Error), `FIL_MS_DUNM` 1. This is the result quoted in `INFRA_TRACKING.md:89`. | `jaspergold/reports/superlint_summary.txt`, `superlint_violations.txt`, `superlint_violations.csv`; narrative `jaspergold/lint_warnings_jaspergold.md` |
| JasperGold Superlint, run 20261018_01 | same script, derived filelist (adds the UART wrapper/OBI chain) | 2026-10-18 | **STALE vs current Top** (its source snapshot has `sys_rst_n_raw = hard_rst_ni & soft_rst_ni` at `:515`, i.e. before the soft-reset filter, which is now at Top `:529-554`), but newest | LINT: 1 Error, 35 Warning, 3 Info (per `lint_summary.md`); DFT_FUNCTIONAL: 15 Warning. Tags: `OTP_NR_READ` 14, `OTP_NO_RGTM` 13, `OTP_UC_INST` 12, `MAC_NR_DMUL` 3, `MOD_NO_IPRG` 3 (`soft_rst_ni`, `spi_sdi1_i`, `uart_sin_i`), `FLP_IS_CSTD` 2, `INP_NO_LOAD` 2 (`fetch_enable_i`, `boot_addr_i`), `RST_IS_DFLP` 2, `RST_IS_DCMB` 1 (Error on `sys_rst_n_raw` driving `sys_rst_sync_q[0]`), `EXP_NR_MXSU` 1, `FIL_MS_DUNM` 1. Design size reported: 110 modules, 42,731 gates, 9,184 flops, 0 black boxes. The log also prints a separate internal tally (24 errors / 1,368 warnings / 3 info) whose scope differs from the exported tables (`lint_summary.md`). | `jaspergold/runs/soc_superlint_20261018_01/reports/superlint_summary.txt`, `.../superlint_violations.txt`, `.../lint_summary.md`, `.../run_manifest.txt` |
| JasperGold CDC/RDC, SPI IP only | `check_cdc` on `apb_spi_master` (`spi_master_ip/jg/cdc.tcl`), `HCLK` + declared derived `spi_clk` (factor 4 assumed) | 2026-08-30 | **STALE** (pre-dates SPI RTL mtime 2026-09-02; SoC top not analysed) | RDC domain: `RST_SYNCHRONIZATION` 1 Error, 0 waived (`RST_NO_SYNC`: `HRESETn` not synchronised to `HCLK` at `u_spictrl.u_rxreg.rx_CS`). No data-CDC section appears in the report. The waiver attempt in the script (`LEGACY` reason) is recorded in the script as not applying. | `spi_master_ip/jg/reports/cdc_violations.txt` (identical hash to `spi_master_ip/reports/cdc_violations.txt`), `.../cdc_violations_detailed.txt`, `spi_master_ip/jg/cdc.tcl` |
| SoC-level CDC / RDC run | none | n/a | **ABSENT** | No `check_cdc` or SpyGlass CDC goal run on `riscforge_soc_subsystem` exists in the repo. | n/a |

`INFRA_TRACKING.md` section 2.5 (lines 85-93) vs report files:

- "JasperGold Superlint LINT 1 Error / 25 Warn / 3 Info; DFT 19 Warn": **matches** `jaspergold/reports/*` (2026-09-10), **not** the 2026-10-18 run (35 warnings / DFT 15).
- "SpyGlass lint + CDC, 1292 messages, 0 waived": the count **matches** `spyglass_summary.rpt`; the "CDC" label is **not supported** by the report content (lint goals only).
- "SPI CDC RST_SYNCHRONIZATION: 1 Error": **matches** `spi_master_ip/jg/reports/cdc_violations.txt`.
- Whether the `RST_IS_DCMB` error still applies to the current Top (which now has `sys_rst_n_raw = hard_rst_ni & soft_rst_n_filt_q`, `:554`) is **UNVERIFIED**; no run has been made since the Top changed. The Top comment at `:528` states the rule "waived on this basis"; no waiver file or waiver command was found in `jaspergold/lint.tcl` or `spyglass/run_spyglass.tcl`.

---

## 4. Pin list / chip IO table (checklist 1.11)

Source: port list of `riscforge_soc_subsystem`, `RTL_SOC/riscforge_soc_subsystem.sv:259-333`. Parameters used for widths: `NR_GPIOS = GPIOCount = 32` (`gpio-master/gpio_reg_pkg.sv:10`), `TIMER0_CNT = TIMER1_CNT = 2` (`:237-238`), `NUM_APB_SLAVES = 6` (`:246`).

**Totals (bits)**: 73 input bits, 159 output bits, 0 `inout` (itemised in Section 4.8). The Top has **no `inout` ports**: every bidirectional function is split into `*_i` / `*_o` / `*_oen_o` (or `*_tx_en_o`) ports that must be merged into pads by the (not-in-repo) chip-top/pad ring.

**Pad type** and **Mux** columns are **TBD** for every row: no pad library, pad ring, IO constraint file, pin-mux or package spec exists in the repo. No value was invented. See Ambiguities A-1, A-2.

### 4.1 Global, reset, test and legacy

| # | Port | Dir | Width | Function | Driven by / consumed by | OE / notes | Pad type | Mux |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `clk_i` | in | 1 | Single functional clock (Section 1) | Consumed by every sequential block (Section 1.2) | n/a | TBD | TBD |
| 2 | `hard_rst_ni` | in | 1 | Cold-boot reset, active low | Consumed by top reset logic (`:535, 540, 554, 561`) | n/a; async | TBD | TBD |
| 3 | `soft_rst_ni` | in | 1 | Warm-boot reset, active low; described as a "board push button" (`:523`) | Consumed by `soft_rst_meta_q` (`:537`) only | n/a; 2-FF + 16-cycle filter | TBD | TBD |
| 4 | `test_mode_i` | in | 1 | Test mode | Consumed by `i_axi_lite_xbar.test_i` (`:986`) only; further fan-out inside the xbar library is UNVERIFIED | TB ties to `1'b0` (`soc_imem_boot_tb.sv:290`) | TBD | TBD |
| 5 | `fetch_enable_i` | in | 1 | Legacy stub port | **No load** (Top `:1239-1241`; JasperGold `INP_NO_LOAD`) | Debug/legacy; TB ties `1'b0` (`soc_imem_boot_tb.sv:292`) | TBD | TBD |
| 6 | `boot_addr_i` | in | 32 | Legacy stub port | **No load** (same refs) | Core reset PC is a parameter, `RESET_PC = 32'h0000_0000` (`:1245`); TB ties `32'h0` (`soc_imem_boot_tb.sv:293`) | TBD | TBD |
| 7 | `boot_done_o` | out | 1 | Boot complete (`state_q == S_DONE`) | Driven by `i_bootloader.boot_done_o` (`:1410`; `bootloader.sv:830`); also consumed internally by `i_isram_axi_if.reject_i` (`:818`) | push-pull, no OE | TBD | TBD |

### 4.2 I2C (APB[0])

| # | Port | Dir | Width | Function | Driven by / consumed by | OE / notes | Pad type | Mux |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 8 | `i2c_scl_i` | in | 1 | SCL pad input | Consumed by `i_apb_i2c.scl_pad_i` -> bit controller 2-FF + filter | async to `clk_i` (Section 3, X8) | TBD | TBD |
| 9 | `i2c_scl_o` | out | 1 | SCL pad output data | Driven by `i_apb_i2c.scl_pad_o`; **constant 0** (`i2c_master_bit_ctrl.sv:541`) | Open-drain style: data is constant 0, drive/release by `i2c_scl_oen_o` | TBD | TBD |
| 10 | `i2c_scl_oen_o` | out | 1 | SCL output enable, **active low** (`oen=0` drives low, `oen=1` releases) | Driven by `scl_oen` flop (`i2c_master_bit_ctrl.sv:157, 357-531`) | OE structure: pad = `oen ? Hi-Z : 0` | TBD | TBD |
| 11 | `i2c_sda_i` | in | 1 | SDA pad input | Consumed by `i_apb_i2c.sda_pad_i` | async to `clk_i` (X8) | TBD | TBD |
| 12 | `i2c_sda_o` | out | 1 | SDA pad output data | **constant 0** (`i2c_master_bit_ctrl.sv:542`) | as SCL | TBD | TBD |
| 13 | `i2c_sda_oen_o` | out | 1 | SDA output enable, **active low** | Driven by the I2C bit controller (`apb_i2c.sv:165`) | pad = `oen ? Hi-Z : 0` | TBD | TBD |
| 14 | `i2c_interrupt_o` | out | 1 | I2C interrupt | Driven by `i_apb_i2c.interrupt_o` (`:1068`); also consumed by core `fast_irq_i` bit for mip[17] (`:1286`) | observation/debug only at the pin | TBD | TBD |

Bidirectional functions (SCL, SDA): realised as `{_i, _o, _oen_o}` triples; external pull-ups are required for I2C and no pull-up exists in the RTL. The pad cell is TBD.

### 4.3 Timers

| # | Port | Dir | Width | Function | Driven by / consumed by | Notes | Pad type | Mux |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 15 | `timer0_irq_o` | out | 4 (`TIMER0_CNT*2`) | `[2N]` overflow, `[2N+1]` compare match for channel N (`:125`) | Driven by `i_apb_timer0.irq_o` (`:1097`). Consumed internally: `[0]`,`[2]`,`[3]` -> core fast IRQ mip[20..22] (`:1281-1283`); `[1]` -> core `timer_irq_i` (MTIP, `:1288`) | Debug/observation at the pin | TBD | TBD |
| 16 | `timer1_irq_o` | out | 4 (`TIMER1_CNT*2`) | same encoding | Driven by `i_apb_timer1.irq_o` (`:1220`). Consumed internally: `[0..3]` -> core fast IRQ mip[23..26] (`:1277-1280`) | Debug/observation at the pin | TBD | TBD |

### 4.4 UART (APB[2])

| # | Port | Dir | Width | Function | Driven by / consumed by | Notes | Pad type | Mux |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 17 | `uart_sin_i` | in | 1 | RX serial input | Consumed by `i_apb_uart.SIN` (`:1130`) | async; 2-FF `sync` + majority filter (X6) | TBD | TBD |
| 18 | `uart_sout_o` | out | 1 | TX serial output | Driven by `i_apb_uart.SOUT` (`:1131`) | push-pull, no OE | TBD | TBD |
| 19 | `uart_int_o` | out | 1 | UART interrupt | Driven by `i_apb_uart.INT` (`:1119`); also core fast IRQ mip[19] (`:1284`) | observation only at the pin | TBD | TBD |

Modem lines are **not ports**: outputs `OUT1N/OUT2N/RTSN/DTRN` are left open and inputs `CTSN/DSRN/DCDN/RIN` are tied to 1 inside the Top (`:1120-1129`).

### 4.5 GPIO (APB[3], 32 pins)

| # | Port | Dir | Width | Function | Driven by / consumed by | OE / notes | Pad type | Mux |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 20 | `gpio_in_i` | in | 32 | Pad inputs | Consumed by `i_gpio_apb_wrap.gpio_in` (`:1149`), per-pin 2-stage `sync` (X7) | async to `clk_i` | TBD | TBD |
| 21 | `gpio_out_o` | out | 32 | Pad output data (`GPIO_OUT` register bit) | `gpio.sv:168`: `gpio_out[i] = gpio_out_q[i]` | data is the register bit in every mode | TBD | TBD |
| 22 | `gpio_tx_en_o` | out | 32 | Pad output enable, **1 = output, 0 = input** (`gpio.sv:56`) | `gpio.sv:170-189`: mode `00` -> 0; `01` -> 1; `10` ("OPEN_DRAIN0") -> `gpio_out_q`; `11` ("OPEN_DRAIN1") -> `~gpio_out_q`; default 0 | OE is combinational from `GPIO_MODE` and `GPIO_OUT` registers; not registered (JasperGold `OTP_NO_RGTM`) | TBD | TBD |
| 23 | `gpio_in_sync_o` | out | 32 | Observation tap of synchronised input | `gpio.sv:144` (`s_gpio_in_sync`) | Debug/observation only; not needed at the pad ring | TBD | TBD |
| 24 | `gpio_global_interrupt_o` | out | 1 | Aggregated GPIO interrupt | `gpio.sv:140`; also core fast IRQ mip[16] (`:1287`) | observation only at the pin | TBD | TBD |
| 25 | `gpio_pin_level_interrupts_o` | out | 32 | Per-pin interrupt | `gpio.sv:141` | Debug/observation; not consumed by the core (Top `:1287` uses only `gpio_global_interrupt_o`) | TBD | TBD |

Bidirectional functions (GPIO[31:0]): realised as `{gpio_in_i, gpio_out_o, gpio_tx_en_o}` per pin.

### 4.6 SPI master (APB[4], standard SPI only)

| # | Port | Dir | Width | Function | Driven by / consumed by | Notes | Pad type | Mux |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 26 | `spi_clk_o` | out | 1 | SCK | `i_apb_spi_master.spi_clk` (`:1181`); registered divider output (`spi_master_clkgen.sv:56-77`) | push-pull, no OE | TBD | TBD |
| 27 | `spi_csn0_o` | out | 1 | Chip select 0: SPI flash, boot image source (`:316`) | `i_apb_spi_master.spi_csn0` (`:1182`) | active low; not registered (JasperGold `OTP_NO_RGTM`) | TBD | TBD |
| 28 | `spi_csn1_o` | out | 1 | Chip select 1: "SPI slave device" (`:316`) | `i_apb_spi_master.spi_csn1` (`:1183`) | active low | TBD | TBD |
| 29 | `spi_sdo0_o` | out | 1 | MOSI (IO0 data out) | `i_apb_spi_master.spi_sdo0` (`:1189`) | push-pull, no OE | TBD | TBD |
| 30 | `spi_sdi1_i` | in | 1 | MISO (IO1 data in; "per spi_master_rx.sv" in the TB, `soc_imem_boot_tb.sv:275`) | Consumed by `i_apb_spi_master.spi_sdi1` (`:1194`) | no synchroniser (X9) | TBD | TBD |
| 31 | `spi_events_o` | out | 2 | `[0]` threshold event (core mip[18]), `[1]` end-of-transfer (core mip[27]) | `i_apb_spi_master.events_o` (`:1180`); consumed by core (`:1277, 1285`) | observation only at the pin | TBD | TBD |

Tied-off, not ports: `spi_csn2`, `spi_csn3`, `spi_mode`, `spi_sdo1..3` left open (`:1186-1188, 1190-1192`); `spi_sdi0`, `spi_sdi2`, `spi_sdi3` tied to 0 (`:1193, 1195, 1196`). **Quad mode is not routed to any pin.**

### 4.7 Bus timeout monitor status (observation only)

| # | Port | Dir | Width | Function | Driven by | Notes | Pad type | Mux |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 32 | `apb_timeout_sticky_o` | out | 6 (`NUM_APB_SLAVES`) | Sticky timeout flag per APB slot, cleared by `sys_rst_n` | `i_apb_timeout_monitor[i].timeout_sticky_o` (`:1047`) | Declared as "observation only; not wired to any interrupt" (`:327-330`) | TBD | TBD |
| 33 | `axi_wr_timeout_sticky_o` | out | 1 | AXI write timeout sticky | `i_axi_lite_timeout_monitor` (`:1367`) | same | TBD | TBD |
| 34 | `axi_rd_timeout_sticky_o` | out | 1 | AXI read timeout sticky | `i_axi_lite_timeout_monitor` (`:1368`) | same | TBD | TBD |

### 4.8 Port-bit totals

- Inputs (bits): `clk_i` 1, `hard_rst_ni` 1, `soft_rst_ni` 1, `test_mode_i` 1, `fetch_enable_i` 1, `boot_addr_i` 32, `i2c_scl_i` 1, `i2c_sda_i` 1, `uart_sin_i` 1, `gpio_in_i` 32, `spi_sdi1_i` 1 = **73**.
- Outputs (bits): `boot_done_o` 1, I2C 5, `timer0_irq_o` 4, `timer1_irq_o` 4, UART 2, GPIO 129 (`gpio_out_o` 32 + `gpio_tx_en_o` 32 + `gpio_in_sync_o` 32 + `gpio_global_interrupt_o` 1 + `gpio_pin_level_interrupts_o` 32), SPI 6, monitors 8 = **159**.
- Total: **232** port bits across 34 named ports, before any pad-ring reduction. A subset of these (`gpio_in_sync_o`, `gpio_pin_level_interrupts_o`, the IRQ pins, the sticky flags, the legacy inputs) are observation or legacy ports, see 4.9.

### 4.9 Testbench / debug-only hooks and tie-offs

| Item | Where | Status |
| --- | --- | --- |
| `fetch_enable_i`, `boot_addr_i` | Top ports `:267-268` | Unconnected legacy stub ports (`:1239-1241`). The reset PC is the parameter `RESET_PC` (`:1245`). |
| `test_mode_i` | Top `:262` | Only reaches `axi_lite_xbar.test_i` (`:986`). |
| `ext_irq_i` (MEIP) and `sw_irq_i` (MSIP) | **Not top-level ports.** They are inputs of the core `top.v:60-61`, tied to `1'b0` at the instantiation (Top `:1289-1290`, "no platform PLIC / CLINT") | Internal tie-offs; no pin. |
| `PCSrcE1` | core debug output `riscv_core/rtl/top.v:31`, left open at the Top (`:1249`) | Debug only, not a port. |
| `*_irq_o`, `i2c_interrupt_o`, `uart_int_o`, `gpio_global_interrupt_o`, `gpio_pin_level_interrupts_o`, `spi_events_o` | Top ports | Duplicate the signals already routed to the core (`:1275-1288`) and are therefore observation/debug taps at the pin level. |
| `gpio_in_sync_o` | Top port `:309` | Observation of the internal synchronised copy of `gpio_in_i`. |
| `apb_timeout_sticky_o`, `axi_wr_timeout_sticky_o`, `axi_rd_timeout_sticky_o` | Top ports `:331-333` | Declared "observation only" (`:327-330`). |
| `boot_done_o` | Top port `:273` | Status output; also an internal control (`:818`). |
| `PCSrcE1`-style/debug nets inside the core | not enumerated | UNVERIFIED. |

### 4.10 External models / hookups needed for system bring-up

| Interface | Needed external device | Hookup facts | Evidence |
| --- | --- | --- | --- |
| SPI boot flash | SPI NOR flash on `spi_csn0_o` (SCK `spi_clk_o`, MOSI `spi_sdo0_o`, MISO `spi_sdi1_i`) | Bootloader assumes NOR opcode `0x03` read with auto-increment; image starts at `FLASH_START_ADDR`, chunked bursts (`bootloader.sv:74-92` comments). `spi_csn1_o` is documented as "SPI slave device" and no hookup was found. The in-tree TB uses a behavioural model `spi_flash_bfm` wired exactly this way (`RTL_SOC/soc_imem_boot_tb.sv:46, 268-276`). A vendor model package `spi_slave_infinion/infineon-s25fs512s-...zip` is present; whether any TB wires it is UNVERIFIED. | as cited |
| I2C | External I2C slave(s) (e.g. EEPROM) and external **pull-ups** on SCL/SDA | RTL only provides `_i/_o(=0)/_oen_o(active low)`. A device model exists under `i2c_slave_at24c02/` (`at24c02_device.sv`, `i2c_target_core.sv`, ...). The boot TB `soc_imem_boot_tb.sv` ties `i2c_scl_i`/`i2c_sda_i` to constant 1 (`:254-255`) and does not instantiate it. Which TB, if any, instantiates the AT24C02 model is UNVERIFIED (grep over `RTL_SOC` and `Verification` returned nothing). | as cited |
| UART | USB-UART bridge or terminal on `uart_sin_i`/`uart_sout_o`; no flow control | Modem lines are tied inside the SoC (`:1120-1129`). TB drives `uart_sin_i = 1'b1` (`soc_imem_boot_tb.sv:256`). | as cited |
| GPIO | board loads/sources | No model needed in RTL. | n/a |
| Reset button | `soft_rst_ni` is a board push-button per the Top comment (`:523`) | Debounce/noise filter is internal, 16 cycles by default. | Top `:247-250` |

---

## 5. Observations (facts only, no diagnosis or fixes)

| ID | Observation | Evidence |
| --- | --- | --- |
| O-1 | There are exactly one clock port and zero clock-generation, gating, PLL or AON blocks in the Top. | Top `:259-333`, instance list `:749-1411` |
| O-2 | Three flop groups (`soft_rst_meta_q`, `soft_rst_n_filt_q`, `soft_rst_cnt_q`) use raw `hard_rst_ni` as async reset directly, with no de-assertion synchroniser, while the other two reset chains use a local 4-FF synchroniser. | Top `:535, 540` vs `:556, 561` |
| O-3 | `sys_rst_n_raw` is a combinational AND of the raw pin `hard_rst_ni` and the flop `soft_rst_n_filt_q`, and drives the async reset of `sys_rst_sync_q`. The 2026-10-18 JasperGold run (older Top, `hard_rst_ni & soft_rst_ni` at `:515` of its snapshot) reports this as `RST_IS_DCMB` (Error). The Top comment states the rule is "waived on this basis" (`:528`); no waiver file/command was found. | Top `:528, 554-556`; `jaspergold/runs/soc_superlint_20261018_01/reports/superlint_violations.txt` (tag `RST_IS_DCMB`); `.../lint_summary.md` |
| O-4 | `soft_rst_n_filt_q` (already synchronised and filtered) is re-synchronised by a second 2-FF inside the bootloader. | `bootloader/bootloader.sv:366-378` |
| O-5 | On warm boot the bootloader sees the soft-reset release 2 cycles after `soft_rst_n_filt_q` rises, while `sys_rst_n` releases 4 cycles after. The warm-boot FSM path goes `S_RESET -> S_CLEAN_ASSERT` with no AXI traffic. | `bootloader/bootloader.sv:369-378, 755-756`; Top `:556-559` |
| O-6 | The three bootloader reset outputs (`core_rst_n`, `periph_rst_n`, `spi_rst_n`) are flop outputs on `clk_i`, and release at different times. `sys_rst_n` releases about 121k cycles before `core_rst_n` per the Top's own comment. The core, boot ROM, fetch demux and `hybrid_mem_interface` share `core_rst_n`; the crossbar, bridges, monitors, SRAM muxes and ISRAM share `sys_rst_n`. | Top `:771-772, 1248, 1310`; `bootloader/bootloader.sv:827-829` |
| O-7 | `sram_we_o` in both AXI->SRAM bridges is a combinational AND of `sram_we_int` and `soft_rst_ni` (= `soft_rst_n_filt_q`). | `RTL_SOC/axi_lite_sram_if.sv:62`; Top `:814, 901` |
| O-8 | `spi_sdi1_i` reaches the SPI receive shift register with no synchroniser flop between the pin and the sampled value. `spi_master_rx.sv` has no `sync`. The 2026-10-18 JasperGold run flags the pin as `MOD_NO_IPRG` (unregistered top-level input). | `spi_master_ip/spi_master/spi_master_rx.sv:78-84`; `jaspergold/runs/soc_superlint_20261018_01/reports/superlint_violations.txt:121` |
| O-9 | **Filelist/source mismatch for the UART.** `soc_subsystem.f:37-43, 157-161` states `apb_uart.sv` is self-contained and that the OBI sources "are absent from this repository". On disk, `apb_uart-main/rtl/apb_uart.sv:52` instantiates `apb_uart_wrap`, which instantiates `apb_to_obi` and `obi_uart` (`apb_uart_wrap.sv:48, 63`), and `obi_uart*.sv` files exist under `apb_uart-main/include/obi/` (mtime 2026-10-02 13:29). Neither `apb_uart_wrap.sv` nor those files are listed in `soc_subsystem.f`. The first JasperGold attempt failed elaboration for this reason; the completed run used a derived filelist that adds them (`jaspergold/runs/soc_superlint_20261018_01/run_manifest.txt`; `jaspergold/jg_soc.f:67-76`; `spyglass/run_spyglass.tcl` also lists them). | cited |
| O-10 | The in-tree SpyGlass `run_spyglass.tcl` uses `SOC_FILES/include/...` paths and a source list that differs from `RTL_SOC/soc_subsystem.f` (e.g. it contains `obi_*` and `apb_uart_wrap.sv`, uses `../apb_timer-master/timer.sv`). | `spyglass/run_spyglass.tcl` (incdir and `read_file` blocks) vs `RTL_SOC/soc_subsystem.f` |
| O-11 | `i2c_scl_o` and `i2c_sda_o` are constant 0; the source carries the comment `//FIXME ANTONIO CHECK`. | `apb_i2c-master/i2c_master_bit_ctrl.sv:539-542` |
| O-12 | GPIO `gpio_out_o` equals the `GPIO_OUT` register bit in every mode, and `gpio_tx_en_o` is `GPIO_OUT` (mode `10`) or `~GPIO_OUT` (mode `11`) in the "open-drain" modes. | `gpio-master/gpio.sv:168-189` |
| O-13 | `test_mode_i` is connected only to the crossbar `test_i`. No other DFT/scan structure (scan chain, scan enable, scan clock) exists on the port list. | Top `:262, 986` |
| O-14 | `fetch_enable_i` and `boot_addr_i` have no load; the Top says so itself. | Top `:1239-1241`; JasperGold `INP_NO_LOAD` |
| O-15 | The latest SpyGlass reports were generated before the bootloader modification of 2026-09-28. The `InferLatch` on `warm_boot_q` they cite refers to the earlier async-soft-reset bootloader; the current bootloader header describes that structure as removed (`bootloader.sv:56-64`). Re-run status: not run since. | `spyglass/spyglass_soc_lint_report.md` section 3.2; `bootloader/bootloader.sv:56-64` |
| O-16 | `RTL_SOC/riscforge_soc_subsystem.sv` and `apb_timer-master/rtl/timer.sv` carry an mtime of 2026-11-02 20:00, later than every lint/CDC artifact; all lint/CDC artifacts are therefore pre-change. | file mtimes, Section 0.2 |
| O-17 | `spyglass/reports/spyglass_design_summary.rpt`, `spyglass_moresimple_sev.rpt`, `spyglass_violations.rpt` and `W415_Report_tmp.rpt` are zero bytes. | `spyglass/reports/` directory listing |
| O-18 | SPI CDC script assumes a fixed `spi_clk_div = 4` ratio for the derived-clock declaration. The real divider is programmable (`CLKDIV` register). | `spi_master_ip/jg/cdc.tcl` (clock section comment) |

---

## 6. Ambiguities for the owner

| ID | Question | Why it matters / what was found |
| --- | --- | --- |
| A-1 | **Pad ring / pad library.** Which pad cells (input, output, tri-state, bidirectional, open-drain, Schmitt, pull-up/down) apply to each port, and where is the pad ring defined? | None found in the repo. All "Pad type" and "Mux" columns are TBD. |
| A-2 | **Pin mux / package pin assignment.** Is the intended chip IO set the 232 port bits as-is, or is a reduced set planned (e.g. drop `gpio_in_sync_o`, `gpio_pin_level_interrupts_o`, the `*_irq_o` taps, sticky flags, `fetch_enable_i`, `boot_addr_i`)? Are SPI `spi_csn1_o` and any pin-mux options intended? | No pin-mux register or mux logic exists in the Top; every function has its own dedicated port. |
| A-3 | **Target clock frequency.** The only reference is a comment ("160 ns at 100 MHz", Top `:248-249`) and a 10 ns TB clock. Is 100 MHz the intended target, and is the clock supplied externally or from an on-chip PLL (none in RTL)? | No SDC, clock constraint or PLL in the repo. |
| A-4 | **Boot-mode strap.** Is a `boot_mode` strap pin intended (e.g. SPI-flash boot vs. other)? | None found. Boot always uses the SPI flash path (`bootloader.sv:754-770`); `fetch_enable_i` / `boot_addr_i` are legacy and unconnected. Is there an intended replacement or are they to be removed from the pin list? |
| A-5 | **Which reset is the chip-level reset?** Is `soft_rst_ni` a real package pin (push button) or an internal/JTAG-driven signal? What is the intended minimum assertion length for `soft_rst_ni` given the 16-cycle filter? Is the raw `hard_rst_ni` guaranteed clean/glitch-free at the pad? | Top comment calls it a "board push button" (`:523`); nothing else is specified. |
| A-6 | **SPI MISO capture.** Is `spi_sdi1_i` sampling timing (flash tCLQV vs. SCK divider, board delay) to be closed by timing constraints, or is a synchroniser expected? | No synchroniser; no constraint/analysis in the repo. The SPI divider is software programmable. |
| A-7 | **Which CDC/RDC tool and run is the sign-off source?** SpyGlass was only run with lint goals; no SoC-level CDC/RDC run exists; the only CDC/RDC report is for the standalone SPI IP and is stale. Is a SoC-level CDC/RDC run required, and against which filelist (`soc_subsystem.f` currently omits the UART wrapper chain)? | Section 3.3, Observation O-9. |
| A-8 | **Intended waiver for `RST_IS_DCMB`.** The Top asserts a waiver "on this basis" (`:528`), but no waiver exists in the scripts or reports. Is a waiver file intended? | O-3. |
| A-9 | **I2C open-drain external structure.** Is the pad expected to implement the open-drain behaviour from `{_o=0, _oen}` as the RTL provides, with external pull-ups on the board? Is `//FIXME ANTONIO CHECK` (constant-0 outputs) intentional? | O-11. |
| A-10 | **GPIO "open-drain" modes.** Modes `10`/`11` set the output enable from the output data while `gpio_out_o` carries the same data. Is this the intended pad-level behaviour? | O-12. The RTL is documented here as implemented only. |
| A-11 | **AON / watchdog.** Is an AON domain, watchdog or software reset still planned for this tape-out? | `aon_timer/` and `clic-master/` exist in the tree but are not integrated; `INFRA_TRACKING.md:114` lists the AON WDT as non-existent. |
| A-12 | **UART source of truth.** Which UART sources are authoritative for tape-out: `apb_uart.sv` as the filelist describes, or the OBI chain actually present on disk? | O-9. |
| A-13 | **`spi_csn1_o` consumer.** Is a second SPI device planned? Only `spi_csn0_o` has a model hookup. | Top `:316`; TB. |

---

## Appendix A - Commands/search basis (for reproducibility)

- Port list: `Grep ^\s*(input|output|inout)\b` on the Top, lines 259-333.
- Reset/clock usage in the Top: targeted grep and reads of `:495-567, 740-1020, 1020-1413`.
- Sequential-block sensitivity lists: `always_ff|always @` enumeration per module directory, plus a search for single-signal `posedge` blocks (no async reset) across the compiled directories.
- Bootloader: reads of `:362-382, 560-743, 748-784`, and header grep.
- Synchronisers: `i2c_master_bit_ctrl.sv:180-281`, `gpio.sv:120-199`, `gpio_input_stage_no_clk_gates.sv`, `sync.sv`, `obi_uart_rx.sv` grep, `obi_uart_pkg.sv:15`.
- Reports: header, summary and tag counts for `spyglass/reports/spyglass_summary.rpt`, `jaspergold/reports/superlint_*`, `jaspergold/runs/soc_superlint_20261018_01/*`, `spi_master_ip/jg/reports/cdc_violations*.txt`, `INFRA_TRACKING.md:85-93`. Reports were not ingested in full.
