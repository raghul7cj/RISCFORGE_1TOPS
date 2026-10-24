# Survey & Signal Tap Identification Report — RISCFORGE 1TOPS SoC

**Agent**: `explorer_survey_1`  
**Working Directory**: `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\explorer_survey_1`  
**Date**: 2026-10-01T21:30:00Z  
**Target Subsystem**: RISCFORGE RV32IM_Zicsr SoC Subsystem  
**Reference Document**: `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\ORIGINAL_REQUEST.md`

---

## 1. Observation

Direct examination of the RTL source code, bus interconnects, and testbench infrastructure revealed the exact hierarchy, interconnect mechanics, and signal nets.

### 1.1 Top-Level SoC Hierarchy (`RTL_SOC/riscforge_soc_subsystem.sv`)
- **Module Declaration**: `riscforge_soc_subsystem` (lines 230–328).
- **Core Instance**: Instantiated at line 1205 as `top #(.RESET_PC(32'h0000_0000)) i_riscv_core (...)`.  
  *(Note: `soc_tb_top.sv` lines 182–211 incorrectly refer to `dut.u_core`; the actual RTL instance name is `dut.i_riscv_core`)*.
- **AXI4-Lite Struct Interfaces**: AXI signals are not flat nets (e.g. `m0_awaddr`). They are SystemVerilog packed structs:
  - `axi_req_t` (lines 365–374): `aw.addr`, `aw.prot`, `aw_valid`, `w.data`, `w.strb`, `w_valid`, `b_ready`, `ar.addr`, `ar.prot`, `ar_valid`, `r_ready`.
  - `axi_resp_t` (lines 377–385): `aw_ready`, `w_ready`, `b.resp`, `b_valid`, `ar_ready`, `r.data`, `r.resp`, `r_valid`.
- **AXI Crossbar**: `axi_lite_xbar` instantiated at line 934 as `i_axi_lite_xbar`:
  - 2 Slave Ports: `xbar_slv_req[0]` (Core via timeout monitor), `xbar_slv_req[1]` (Bootloader).
  - 3 Master Ports: `xbar_mst_req[0]` (ISRAM bridge), `xbar_mst_req[1]` (DSRAM bridge), `xbar_mst_req[2]` (APB bridge).
- **AXI-to-APB Bridge**: `axi_lite_to_apb` instantiated at line 961 as `i_axi_lite_to_apb`:
  - Input: `xbar_mst_req[2]` / `xbar_mst_resp[2]`.
  - Output: `apb_req[NUM_APB_SLAVES-1:0]` (packed struct `apb_req_t`).
  - Response: `apb_resp[NUM_APB_SLAVES-1:0]` (bridge side, after timeout monitors).
- **APB Timeout Monitors**: Instantiated at line 995 (`gen_apb_timeout_mon[0..5].i_apb_timeout_monitor`):
  - Interposed on the response path only: `apb_resp_slv[i]` &rarr; `apb_timeout_monitor` &rarr; `apb_resp[i]`.
- **6 APB Slaves**:
  - Slot 0 (`0x4000_0000 - 0x4000_0FFF`): `apb_i2c` (line 1016, `i_apb_i2c`).
  - Slot 1 (`0x4000_1000 - 0x4000_1FFF`): `apb_timer` (line 1044, `i_apb_timer0`, 2 channels).
  - Slot 2 (`0x4000_2000 - 0x4000_2FFF`): `apb_uart` (line 1069, `i_apb_uart`, word addr `paddr[4:2]`).
  - Slot 3 (`0x4000_3000 - 0x4000_37FF`): `gpio_apb_wrap` (line 1102, `i_gpio_apb_wrap`, 2 KB decode).
  - Slot 4 (`0x4000_4000 - 0x4000_4FFF`): `apb_spi_master` (line 1127, `i_apb_spi_master`, routed via `i_bootloader`).
  - Slot 5 (`0x4000_5000 - 0x4000_5FFF`): `apb_timer` (line 1167, `i_apb_timer1`, 2 channels).
- **Core Memory Router**: `hybrid_mem_interface` instantiated at line 1262 as `i_core_data_if`:
  - Decodes `lsu_mem_*`: DSRAM (`0x0002_0000 - 0x0002_7FFF`) routed directly to `i_dsram_mux` port 0; MMIO (`0x4000_0000 - 0x4FFF_FFFF`) routed to `core_axi_req`.
- **AXI-Lite Timeout Monitor**: `axi_lite_timeout_monitor` instantiated at line 1310 as `i_axi_lite_timeout_monitor`:
  - Upstream: `core_axi_req` / `core_axi_resp`.
  - Downstream: `xbar_slv_req[0]` / `xbar_slv_resp[0]`.

---

### 1.2 RISC-V Core Pipeline (`riscv_core/rtl/top.v`)
- **Stage Instantiations**:
  - `fetch_cycle Fetch` (line 293): Output `PCF[31:0]`, `PCPlus4F[31:0]`, `InstrF[31:0]`, `InstrD[31:0]`, `PCD[31:0]`, `valid_D`.
  - `decode_cycle Decode` (line 322): Decodes `InstrD`. Emits register source indices, imm, ALU/branch controls.
  - `execute_cycle Execute` (line 375): Performs ALU ops, branch resolution (`PCSrcE`, `PCTargetE`), CSR execution, divider abort strobe (`div_abort_o`).
  - `memory_cycle Memory` (line 446): Manages LSU interface (`lsu_mem_req`, `lsu_mem_we`, `lsu_mem_addr`, `lsu_mem_wdata`, `lsu_mem_be`, `lsu_mem_rdata`, `lsu_mem_stall`, `lsu_mem_err`).
  - `writeback_cycle WriteBack` (line 503): Selects `ResultW` from ALU, DMEM, PC+4, or old CSR.
- **Architectural Retirement & Commit**:
  - Instruction Retirement Condition: `valid_W & ~exc_valid_W` (line 571, drives `.instr_retired_i` on `csr_file`).
  - Gated Register Write: `RegWriteW_gated = RegWriteW & valid_W & ~exc_valid_W & ~mret_commit;` (line 283).
  - Destination Register: `RDW[4:0]`. Write Data: `ResultW[31:0]`.
  - Program Counter at Retirement: `PC_W[31:0]`.
  - **Instruction Word in WB Stage**: `top.v` does **not** pipeline `Instr` through `EX`, `MEM`, and `WB`. The raw instruction word is available as `InstrF` (IF stage) and `InstrD` (ID stage). In `soc_tb_top.sv` line 193, `.instr_w(dut.u_core.InstrW)` is invalid because `InstrW` does not exist in `top.v`.
- **Trap and MRET Commit Controller (`wb_trap_mret_commit_controller.v`)**:
  - Instantiated at line 515 as `wb_commit`.
  - `trap_valid_o = valid_W & exc_valid_W` (trap commit strobe).
  - `trap_is_interrupt_o = exc_cause_W[5] & exc_valid_W` (**this serves as the architectural `irq_ack`**).
  - `trap_cause_o = {25'b0, exc_cause_W[4:0]}` (trap cause code).
  - `trap_pc_o = exc_pc_W` (`mepc`).
  - `trap_addr_o = exc_tval_W` (`mtval`).
  - `mret_commit_o = valid_W & is_mret_W & ~exc_valid_W` (MRET commit strobe).
  - `clear_gateway_o[5:0]`: One-hot pulse to clear edge-triggered gateway pending bits.

---

### 1.3 Interrupt Subsystem (`riscv_core/rtl/irq_gateway.v`, `irq_arbiter.v`)
- **Raw Peripheral Sources**:
  - `gpio_global_interrupt_o`, `gpio_pin_level_interrupts_o[31:0]`
  - `i2c_interrupt_o`
  - `spi_events_o[1:0]` (bit 0 = FIFO, bit 1 = End of Transfer / Watchdog)
  - `uart_int_o`
  - `timer0_irq_o[3:0]`, `timer1_irq_o[3:0]`
- **Core Inbound Mapping (`top.v` lines 1236–1252)**:
  - `timer_irq_i = timer0_irq_o[1]` (Timer 0 Channel 0 compare &rarr; `mip[7]` MTIP).
  - `fast_irq_i[15:0]`:
    - `[0]` = GPIO (`mip[16]`)
    - `[1]` = I2C (`mip[17]`)
    - `[2]` = SPI FIFO (`mip[18]`)
    - `[3]` = UART (`mip[19]`)
    - `[4..6]` = Timer 0 (`mip[20..22]`)
    - `[7..10]` = Timer 1 (`mip[23..26]`)
    - `[11]` = SPI EOT / Watchdog (`mip[27]`)
- **Gateway**: `irq_gateway` (line 213): Captures edge vs level lines with pulse-wins latch; outputs `pend_gateway[5:0]`.
- **Arbiter**: `irq_arbiter` (line 227): Two-level priority class arbitration:
  - Class 2 (Real-Time): Timer 0 compare, SPI EOT/WD.
  - Class 1 (Stream): UART &harr; SPI round-robin.
  - Class 0 (Background): I2C &harr; GPIO round-robin.
  - Hardware Shadow Stack: Depth 2, tracked via `cur_class_sb[1:0]` and `nest_depth_sb[1:0]`.

---

### 1.4 Existing Verification Infrastructure (`Verification/infrastructure/`)
- **Verification files examined**:
  - `monitors/fetch_monitor.sv`, `retire_monitor.sv`, `lsu_monitor.sv`, `axi_lite_monitor.sv`, `apb_monitor.sv`, `irq_monitor.sv`.
  - `checkers/failure_reporter.sv`: Houses `freeze_monitors` output task `report_failure(layer, check_id, msg, pc)`.
  - `tb/soc_tb_top.sv`: Top-level testbench instantiating DUT, BFMs, monitors, and checkers. Contains legacy/broken net names (`dut.u_core.*`, `m0_awaddr`).
  - `tb/rf_mon_probe.sv`, `tb/rf_monitor_if.sv`, `tb/tb_pkg.sv`: Advanced SystemVerilog interface & class-based probe layer containing exact real hierarchical paths (`u_dut.i_riscv_core.*`, `u_dut.core_axi_req`, `u_dut.apb_req[g]`).

---

## 2. Logic Chain

```
[RTL Code Review] 
       │
       ├─► Core lacks flat InstrW in WB ──► Shadow PC-to-Instruction tracking in Testbench
       │
       ├─► Core lacks irq_ack pin ────────► trap_commit_valid & trap_commit_is_interrupt in WB
       │
       ├─► AXI/APB are packed structs ────► Unpack via continuous assignments in probe layer
       │
       ├─► Need zero RTL timing impact ───► Clocking blocks with #1step (Preponed region), no backpressure
       │
       └─► Need simultaneous freeze ──────► failure_reporter.freeze_monitors broadcast to all 6 rings
```

### 2.1 Non-Intrusive Tapping Derivation
1. **Passive Sniffing**: To ensure zero backpressure and no alteration of RTL timing, monitor interfaces must be purely observational (inputs to monitors). Monitors must never drive RTL handshakes (`ready`, `valid`, `req`, `stall`, `gnt`, `penable`, `pready`).
2. **Race-Free Delta-Cycle Independence**: By using SystemVerilog clocking blocks with `default input #1step` (or sampling on `@(posedge clk)` strictly without driving NBA updates back into the design), the monitors sample in the Preponed region. This guarantees identical values to waveform traces and prevents simulation event races.
3. **Instruction Recovery at Retire Stage**: Because `top.v` does not propagate `Instr` from Decode to Writeback in standard RTL, modifying the core RTL to add 96 flip-flops (`Instr_E`, `Instr_M`, `Instr_W`) would alter design area and potentially timing paths. Instead, the non-intrusive approach is for the testbench/monitor environment to shadow the instruction word during the Fetch/Decode stage keyed by PC, and retrieve it when `PC_W` retires.

### 2.2 Simultaneous Freeze Buffer (64-entry) Derivation
1. **Circular Ring Buffers**: Each of the 6 monitors maintains a circular buffer of 64 entries (`ring_buffer[0:63]`). A pointer (`head_ptr`) increments modulo 64 on each valid transaction.
2. **Unified Timebase**: A single 64-bit cycle counter (`cycle_cnt` / `rf_timebase_if.cycle`) timestamps every transaction across all 6 monitors.
3. **Simultaneous Freeze Signal**: When any checker (protocol SVA, MMIO path scoreboard, peripheral predictor, or interrupt predictor) detects an anomaly or unexpected trap, it calls `failure_reporter.report_failure(...)`.
4. `failure_reporter` asserts `freeze_monitors = 1'b1`.
5. On the clock edge where `freeze_monitors == 1'b1`, all 6 ring buffers inhibit write pointer advancement (`if (!freeze)`). The buffers stop simultaneously, preserving the exact 64-entry pre-failure window across Fetch, Retire, LSU, AXI, APB, and IRQ for instant blame-layer root-cause extraction.

---

## 3. Signal Tap Specifications (The 6 Monitors)

### Monitor 1: Fetch Stage Monitor
| Signal Name | Width | RTL Hierarchical Path | Timing / Sampling Condition | Description |
|:---|:---:|:---|:---|:---|
| `clk` | 1 | `dut.clk_i` | posedge | System Clock (100 MHz) |
| `rst_n` | 1 | `dut.hard_rst_ni` | active-low async | System Reset |
| `freeze` | 1 | `u_failure_reporter.freeze_monitors` | Synchronous freeze | Freezes ring buffer |
| `pc_f` | 32 | `dut.i_riscv_core.Fetch.PCF` | `imem_sram_en && !StallF && !imem_stall` | Current PC in fetch stage |
| `pc_plus4_f`| 32 | `dut.i_riscv_core.Fetch.PCPlus4F` | Same as above | Sequential next PC |
| `pc_next_f` | 32 | `dut.i_riscv_core.Fetch.PC_next` | Same as above | Target PC resolved by branch/trap |
| `instr_f` | 32 | `dut.i_riscv_core.Fetch.InstrF` | Same as above | Instruction word (NOP-gated) |
| `imem_en` | 1 | `dut.i_riscv_core.imem_sram_en` | Sampled every cycle | Core fetch request strobe |
| `stall_f` | 1 | `dut.i_riscv_core.StallF \| dut.i_riscv_core.Fetch.imem_stall` | Sampled every cycle | IF-stage stall / backpressure |
| `exc_valid_f`| 1 | `dut.i_riscv_core.Fetch.exc_valid_F` | Sampled on fetch | Fetch misaligned exception |

---

### Monitor 2: Retire Stage Monitor (RVFI / Commit)
| Signal Name | Width | RTL Hierarchical Path | Timing / Sampling Condition | Description |
|:---|:---:|:---|:---|:---|
| `clk` | 1 | `dut.clk_i` | posedge | System Clock |
| `rst_n` | 1 | `dut.hard_rst_ni` | active-low async | System Reset |
| `freeze` | 1 | `u_failure_reporter.freeze_monitors` | Synchronous freeze | Freezes ring buffer |
| `retire_valid`| 1 | `dut.i_riscv_core.valid_W && !dut.i_riscv_core.exc_valid_W` | posedge clk | True instruction retirement |
| `pc_w` | 32 | `dut.i_riscv_core.PC_W` | Sampled on `retire_valid` | Retiring instruction PC |
| `instr_w` | 32 | *Shadow PC Lookup* (or `dut.i_riscv_core.InstrW` if `RVFI` defined) | Sampled on `retire_valid` | Instruction word retired |
| `rd_addr_w` | 5 | `dut.i_riscv_core.RDW` | Sampled on `retire_valid` | Destination register ($x0..$x31) |
| `rd_wdata_w`| 32 | `dut.i_riscv_core.ResultW` | Sampled on `retire_valid` | Architectural writeback data |
| `reg_we_w` | 1 | `dut.i_riscv_core.RegWriteW_gated` | Sampled on `retire_valid` | Gated register write enable |
| `trap_valid`| 1 | `dut.i_riscv_core.trap_commit_valid` | `valid_W && exc_valid_W` | Trap commit strobe |
| `trap_is_irq`| 1 | `dut.i_riscv_core.trap_commit_is_interrupt` | On `trap_valid` | 1 = Interrupt, 0 = Exception (`irq_ack`) |
| `trap_cause`| 31 | `dut.i_riscv_core.trap_commit_cause` | On `trap_valid` | Trap cause code (mcause) |
| `trap_pc` | 32 | `dut.i_riscv_core.trap_commit_pc` | On `trap_valid` | Trapped PC (`mepc`) |
| `trap_addr` | 32 | `dut.i_riscv_core.trap_commit_addr` | On `trap_valid` | Fault address (`mtval`) |
| `mret_commit`| 1 | `dut.i_riscv_core.mret_commit` | `valid_W && is_mret_W && !exc_valid_W` | MRET commit strobe |
| `csr_we_w` | 1 | `dut.i_riscv_core.csr_write_en_W_gated`| Sampled on `retire_valid` | CSR write strobe |
| `csr_addr_w`| 12 | `dut.i_riscv_core.csr_addr_W` | Sampled on `retire_valid` | CSR address written |
| `csr_wdata_w`| 32 | `dut.i_riscv_core.new_csr_W` | Sampled on `retire_valid` | CSR new value |

---

### Monitor 3: LSU (Load/Store Unit) Monitor
| Signal Name | Width | RTL Hierarchical Path | Timing / Sampling Condition | Description |
|:---|:---:|:---|:---|:---|
| `clk` | 1 | `dut.clk_i` | posedge | System Clock |
| `rst_n` | 1 | `dut.hard_rst_ni` | active-low async | System Reset |
| `freeze` | 1 | `u_failure_reporter.freeze_monitors` | Synchronous freeze | Freezes ring buffer |
| `lsu_req` | 1 | `dut.i_riscv_core.lsu_mem_req` | Strobe | Memory request strobe |
| `lsu_we` | 1 | `dut.i_riscv_core.lsu_mem_we` | Sampled with req | 1 = Store, 0 = Load |
| `lsu_addr` | 32 | `dut.i_riscv_core.lsu_mem_addr` | Sampled with req | Byte address of transfer |
| `lsu_wdata`| 32 | `dut.i_riscv_core.lsu_mem_wdata` | Sampled with req | Store data payload |
| `lsu_be` | 4 | `dut.i_riscv_core.lsu_mem_be` | Sampled with req | Byte lane enables (strobe) |
| `lsu_rdata`| 32 | `dut.i_riscv_core.lsu_mem_rdata` | On `lsu_req && !lsu_stall` | Returned read data |
| `lsu_stall`| 1 | `dut.i_riscv_core.lsu_mem_stall` | Sampled every cycle | Backpressure stall from router |
| `lsu_err` | 1 | `dut.i_riscv_core.lsu_mem_err` | On transfer completion | Bus access error strobe |
| `pc_m` | 32 | `dut.i_riscv_core.PC_M` | Sampled with req | PC of LSU instruction |
| `lsunit_op`| 5 | `dut.i_riscv_core.lsunitM` | Sampled with req | Opcode: LB/LH/LW/SB/SH/SW |

---

### Monitor 4: AXI4-Lite Bus Monitor
*Tapped at the Core Master Port (upstream of timeout monitor) or Crossbar Port 0.*
| Signal Name | Width | RTL Hierarchical Path | Timing / Handshake | Description |
|:---|:---:|:---|:---|:---|
| `clk` | 1 | `dut.clk_i` | posedge | System Clock |
| `rst_n` | 1 | `dut.hard_rst_ni` | active-low async | System Reset |
| `freeze` | 1 | `u_failure_reporter.freeze_monitors` | Synchronous freeze | Freezes ring buffer |
| `awaddr` | 32 | `dut.core_axi_req.aw.addr` | `awvalid && awready` | Write address |
| `awprot` | 3 | `dut.core_axi_req.aw.prot` | `awvalid && awready` | Protection attributes |
| `awvalid` | 1 | `dut.core_axi_req.aw_valid` | Strobe | Write address valid |
| `awready` | 1 | `dut.core_axi_resp.aw_ready`| Handshake | Write address ready |
| `wdata` | 32 | `dut.core_axi_req.w.data` | `wvalid && wready` | Write data |
| `wstrb` | 4 | `dut.core_axi_req.w.strb` | `wvalid && wready` | Write byte strobes |
| `wvalid` | 1 | `dut.core_axi_req.w_valid` | Strobe | Write data valid |
| `wready` | 1 | `dut.core_axi_resp.w_ready` | Handshake | Write data ready |
| `bresp` | 2 | `dut.core_axi_resp.b.resp` | `bvalid && bready` | Write response status |
| `bvalid` | 1 | `dut.core_axi_resp.b_valid` | Strobe | Write response valid |
| `bready` | 1 | `dut.core_axi_req.b_ready` | Handshake | Write response ready |
| `araddr` | 32 | `dut.core_axi_req.ar.addr` | `arvalid && arready` | Read address |
| `arprot` | 3 | `dut.core_axi_req.ar.prot` | `arvalid && arready` | Protection attributes |
| `arvalid` | 1 | `dut.core_axi_req.ar_valid` | Strobe | Read address valid |
| `arready` | 1 | `dut.core_axi_resp.ar_ready`| Handshake | Read address ready |
| `rdata` | 32 | `dut.core_axi_resp.r.data` | `rvalid && rready` | Read data |
| `rresp` | 2 | `dut.core_axi_resp.r.resp` | `rvalid && rready` | Read response status |
| `rvalid` | 1 | `dut.core_axi_resp.r_valid` | Strobe | Read data valid |
| `rready` | 1 | `dut.core_axi_req.r_ready` | Handshake | Read data ready |
| `wr_timeout`| 1 | `dut.axi_wr_timeout_pulse` | Pulse | Write timeout monitor fire |
| `rd_timeout`| 1 | `dut.axi_rd_timeout_pulse` | Pulse | Read timeout monitor fire |

---

### Monitor 5: APB 6-Slot Peripheral Bus Monitor
| Signal Name | Width | RTL Hierarchical Path | Timing / Handshake | Description |
|:---|:---:|:---|:---|:---|
| `clk` | 1 | `dut.clk_i` | posedge | System Clock |
| `rst_n` | 1 | `dut.hard_rst_ni` | active-low async | System Reset |
| `freeze` | 1 | `u_failure_reporter.freeze_monitors` | Synchronous freeze | Freezes ring buffer |
| `paddr` | 32 | `dut.apb_req[0].paddr` | Setup/Access | Common peripheral byte address |
| `pprot` | 3 | `dut.apb_req[0].pprot` | Setup/Access | Protection attributes |
| `penable` | 1 | `dut.apb_req[0].penable` | Access Phase | APB enable strobe |
| `pwrite` | 1 | `dut.apb_req[0].pwrite` | Setup/Access | 1 = Write, 0 = Read |
| `pwdata` | 32 | `dut.apb_req[0].pwdata` | Setup/Access | Write data payload |
| `pstrb` | 4 | `dut.apb_req[0].pstrb` | Setup/Access | Byte strobes |
| `psel[5:0]`| 6 | `dut.apb_req[i].psel` | Setup/Access | Individual slot selects (0..5) |
| `pready[5:0]`| 6 | `dut.apb_resp[i].pready` | Access Phase | Slot ready (post-timeout) |
| `prdata[5:0]`| 6x32 | `dut.apb_resp[i].prdata` | `psel[i] && penable && pready[i]` | Read data returned per slot |
| `pslverr[5:0]`| 6 | `dut.apb_resp[i].pslverr` | On completion | Slot error response (or timeout) |
| `timeout_pulse`| 6 | `dut.apb_timeout_pulse[5:0]` | Pulse | Per-slot timeout fire pulse |
| `raw_pready`| 6 | `{dut.timer1_pready, dut.spi_pready, dut.i_gpio_apb_wrap.s_bridge_pready, dut.uart_pready, dut.timer0_pready, dut.i2c_pready}` | Raw slave | Slave PREADY before timeout mux |

---

### Monitor 6: IRQ Lines & Interrupt Controller Monitor
| Signal Name | Width | RTL Hierarchical Path | Timing / Sampling Condition | Description |
|:---|:---:|:---|:---|:---|
| `clk` | 1 | `dut.clk_i` | posedge | System Clock |
| `rst_n` | 1 | `dut.hard_rst_ni` | active-low async | System Reset |
| `freeze` | 1 | `u_failure_reporter.freeze_monitors` | Synchronous freeze | Freezes ring buffer |
| `gpio_irq` | 1 | `dut.gpio_global_interrupt_o` | Level/Edge | GPIO global IRQ line |
| `gpio_pin_irqs`| 32 | `dut.gpio_pin_level_interrupts_o` | Level | GPIO individual pin IRQs |
| `i2c_irq` | 1 | `dut.i2c_interrupt_o` | Level | I2C master byte transfer IRQ |
| `spi_events`| 2 | `dut.spi_events_o[1:0]` | Pulse | SPI events ([0]=FIFO, [1]=EOT/WD)|
| `uart_irq` | 1 | `dut.uart_int_o` | Level | UART TX/RX interrupt |
| `timer0_irq`| 4 | `dut.timer0_irq_o[3:0]` | Edge/Level | Timer 0 ovf/cmp channels 0 & 1 |
| `timer1_irq`| 4 | `dut.timer1_irq_o[3:0]` | Edge/Level | Timer 1 ovf/cmp channels 0 & 1 |
| `gateway_pend`| 6 | `dut.i_riscv_core.u_irq_gateway.pend_o`| posedge | Captured pending latches |
| `fast_irq_in`| 16 | `dut.i_riscv_core.fast_irq_i` | Core input | Fast local interrupts (mip[31:16])|
| `timer_irq_in`| 1 | `dut.i_riscv_core.timer_irq_i` | Core input | Timer interrupt (mip[7] MTIP) |
| `irq_pending`| 1 | `dut.i_riscv_core.irq_pending` | Arbiter output | Grant pending to pipeline |
| `irq_winner_id`| 5 | `dut.i_riscv_core.u_irq_arbiter.irq_id_o` | Arbiter output | Winning interrupt ID |
| `irq_class` | 2 | `dut.i_riscv_core.u_irq_arbiter.irq_class_o`| Arbiter output | Class: 2=Real-Time, 1=Stream, 0=BG |
| `cur_class` | 2 | `dut.i_riscv_core.cur_class_sb` | CSR Sideband | Current executing priority class |
| `nest_depth`| 2 | `dut.i_riscv_core.nest_depth_sb` | CSR Sideband | 2-deep shadow stack depth |
| `irq_commit_ack`| 1 | `dut.i_riscv_core.trap_commit_valid && dut.i_riscv_core.trap_commit_is_interrupt` | WB stage commit | Architectural interrupt accept (`irq_ack`) |
| `irq_ack_id`| 5 | `dut.i_riscv_core.trap_commit_cause[4:0]` | On commit | Accepted interrupt ID |
| `mret_commit`| 1 | `dut.i_riscv_core.mret_commit` | WB stage commit | ISR return / shadow stack pop |

---

## 4. Caveats & Integration Risks

1. **Instruction Word at Retire Stage**:
   - `top.v` does not propagate `Instr` to WB. In `soc_tb_top.sv` line 193, `.instr_w(dut.u_core.InstrW)` fails compilation.
   - *Remedy*: Retire monitor must back-fill the instruction word using a PC shadow map generated by the Fetch monitor, or the team can gate `Instr_W` in `top.v` under `` `ifdef RVFI ``.
2. **Missing `irq_ack` Hardware Pin**:
   - The core does not export a dedicated external `irq_ack` pin.
   - *Remedy*: Architectural acknowledgement must be tapped at the WB stage: `dut.i_riscv_core.trap_commit_valid && dut.i_riscv_core.trap_commit_is_interrupt`.
3. **AXI-Lite & APB Structs vs Flat Wires**:
   - `soc_tb_top.sv` assumes flat nets like `dut.m0_awaddr`. The actual RTL uses SystemVerilog packed structs `axi_req_t` and `apb_req_t`.
   - *Remedy*: Use the flattening continuous assign blocks established in `Verification/infrastructure/tb/rf_mon_probe.sv`.
4. **Hierarchical Name Inconsistencies in `soc_tb_top.sv`**:
   - `dut.u_core` must be updated to `dut.i_riscv_core`.
   - `dut.u_core.PC_F` must be updated to `dut.i_riscv_core.Fetch.PCF`.
   - `dut.u_core.rd_W` must be updated to `dut.i_riscv_core.RDW`.
   - `dut.u_core.stallF` must be updated to `dut.i_riscv_core.StallF`.
   - `dut.u_core.trap_taken` must be updated to `dut.i_riscv_core.trap_commit_valid`.
5. **GPIO Address Decode Window**:
   - APB slot 3 GPIO decodes 11 address bits (2 KB, `0x4000_3000 - 0x4000_37FF`). Any access to `0x4000_3800 - 0x4000_3FFF` does not hit GPIO; it returns SLVERR via the APB bridge decode default. Monitors must enforce 2 KB rather than 4 KB.

---

## 5. Conclusion

1. **Complete Architectural Mapping**: All 6 passive monitors (Fetch, Retire, LSU, AXI4-Lite, APB 6-Slot, and IRQ) have been mapped to exact RTL hierarchical nets and structs in `riscforge_soc_subsystem.sv` and `riscv_core/rtl/top.v`.
2. **Non-Intrusive Observability**: By utilizing preponed clocking block sampling (`#1step`), read-only taps, and out-of-band instruction shadow maps, the monitoring layer imposes **zero clock cycles of backpressure**, **zero gate loads on critical paths**, and **no change to RTL synthesis or simulation timing**.
3. **Simultaneous Freeze Synchrony**: The unified 64-bit cycle counter (`rf_timebase_if`) combined with `failure_reporter.freeze_monitors` guarantees that on the exact cycle of an assertion failure, scoreboard discrepancy, or unexpected trap, all 6 ring buffers freeze simultaneously, preserving the 64-entry pre-failure execution history for immediate automated root-cause diagnosis.

---

## 6. Verification Method

To independently verify the identified signal taps and ensure non-intrusive compilation and operation:

1. **Compilation Check (Vivado XSim)**:
   ```powershell
   cd "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\Verification\infrastructure"
   xelab -prj soc_verification.prj -top soc_tb_top -s soc_sim -timescale 1ns/1ps -debug typical
   ```
2. **Regression Execution**:
   ```powershell
   cd "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\Verification\infrastructure"
   powershell -ExecutionPolicy Bypass -File run_regression.ps1
   ```
3. **Non-Intrusive Timing Equivalence Check**:
   - Run simulation with monitors enabled (`RUN_MONITORS = 1'b1`).
   - Run simulation with monitors disabled (`RUN_MONITORS = 1'b0`).
   - Compare simulation cycles to completion (`cycle_cnt`) and register state dumps: cycle count and outputs must be bit-for-bit identical, verifying zero timing impact.
