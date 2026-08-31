# RISCFORGE SoC Specification & LSU Verification Environment

## 1. SoC Architecture Overview

```
                    ┌──────────────────────────────────────┐
                    │         RV32IM_Zicsr Core            │
                    │  ┌───┐ ┌───┐ ┌───┐ ┌────┐ ┌──┐    │
                    │  │IF │ │ID │ │EX │ │MEM│ │WB│    │
                    │  └───┘ └───┘ └───┘ └────┘ └──┘    │
                    └──────────────┬──────────────────────┘
                                   │ AXI4-Lite Master
                                   ▼
                ┌──────────────────────────────────────┐
                │        hybrid_mem_interface            │
                │  (address decoder + bus router)       │
                └──────────────┬──────────────────────┘
                               │
            ┌──────────────────┼──────────────────────┐
            ▼                  ▼                      ▼
    ┌──────────────┐  ┌────────────────┐  ┌──────────────────────┐
    │  Data_Memory │  │ axi_lite_dummy │  │ axil_ram (optional)  │
    │  (SRAM)      │  │ _slave (stub)  │  │ AXI4-Lite RAM        │
    │  0x8000_0000 │  │ 0x4000_0000    │  │ 16-bit addr width    │
    │  → 0x8040_0000│  │ → 0x4000_FFFF │  │ (future use)         │
    └──────────────┘  └────────────────┘  └──────────────────────┘
```

### 1.1 Core-to-SoC Integration (`top.v`)
- Core exposes **AXI4-Lite master** ports from `memory_cycle.v` for peripheral access
- `wb_trap_mret_commit_controller` has inputs `irq_valid_i`, `irq_id_i` for CLIC connection (hardwired to 0)
- `csr_regfile.v` receives `timer_intr_i` (stubbed to 1), `ext_intr_i` (0), `msft_intr_i` (0)
- `clic.sv` is a **dummy stub** — correct port signatures, all outputs driven to 0

### 1.2 Memory Map

| Region | Start | End | Target | Latency |
|---|---|---|---|---|
| IMEM (IF) | `0x8000_0000` | `0x8040_0000` | `Instruction_Memory_new` | 1 cycle read |
| DMEM (data SRAM) | `0x8000_1000` | `0x8040_0000` | `Data_Memory` | 2 cycles read via hmif, 1 cycle write |
| MMIO (AXI-Lite) | `0x4000_0000` | `0x4000_FFFF` | `axi_lite_dummy_slave` | Variable (AXI handshake) |
| Unmapped | Elsewhere | — | Access fault (`core_err=1`) | — |

### 1.3 SoC Peripheral Slaves

#### `axi_lite_dummy_slave.v`
- Zero-latency AXI4-Lite stub for simulation
- `awready=wready=arready=1` (always ready)
- Write: asserts `bvalid` for 1 cycle after both awvalid+wvalid seen; returns `bresp=OKAY`
- Read: asserts `rvalid` for 1 cycle after arvalid; returns `rdata = 32'hdead0000 + addr[3:2]`
- No internal storage

#### `axil_ram.v` (available at `verif/axil_ram.v`)
- Full AXI4-Lite RAM with parameterized `DATA_WIDTH=32`, `ADDR_WIDTH=16`
- Configurable `PIPELINE_OUTPUT` for registered read data
- Write: registers awready/wready/bvalid. Read: registers arready/rvalid/rdata
- Not currently instantiated — available for SoC integration

---

## 2. LSU Subsystem (DUT Boundary)

```
                        ┌──────────────────────────────────────┐
                        │            DUT (Subsystem)            │
                        │                                      │
 core_addr[31:0]  ──────▶  ls_unit  ──▶ hybrid_mem_interface ──▶ Data_Memory  ──▶ sram_rdata
 core_wdata[31:0] ──────▶      │              │                              │
 lsunit[4:0]      ──────▶      │              └──▶ axi_lite_dummy_slave      │
                        │      ▼                                             │
 core_rdata[31:0]  ◀──────│  (formatted load data)                          │
 core_stall        ◀──────│  (pipeline freeze)                              │
 core_err          ◀──────│  (access fault)                                 │
                        └────────────────────────────────────────────────────┘
```

**TB drives only the core-side interface of `ls_unit`. Internal wires between sub-modules are not touched directly.**

### 2.1 DUT Sub-Modules

#### `ls_unit.v`
- **Ports:**
  - Core side: `core_addr[31:0]`, `core_wdata[31:0]`, `lsunit[4:0]` (in); `core_rdata[31:0]`, `core_stall`, `core_err` (out)
  - Memory bridge: `mem_req`, `mem_we`, `mem_addr[31:0]`, `mem_wdata[31:0]`, `mem_be[3:0]` (out); `mem_rdata[31:0]`, `mem_stall`, `mem_err` (in)
- Control bus `lsunit[4:0]`: `[4]=en, [3]=is_store, [2:0]=funct3`
- Load formatting: LB (sign-ext byte), LH (sign-ext half), LW (passthrough), LBU (zero-ext byte), LHU (zero-ext half) — byte-offset aware
- Store alignment: SB/SH/SW — byte/half/word enables + data shifting per `byte_offset = addr[1:0]`
- `core_stall = mem_req & mem_stall`

#### `hybrid_mem_interface.v`
- **Ports:** See DESIGN_SPEC.md §3.3
- SRAM read FSM: `IDLE → WAIT → READY → IDLE` (2-cycle latency, stall=1 during IDLE+WAIT)
- SRAM writes: pass-through combinational, no stall
- AXI write FSM: `IDLE → WAIT_ADDR/WAIT_DATA → WAIT_RESP → IDLE`
- AXI read FSM: `IDLE → WAIT_READ → IDLE`
- Error aggregation: `mem_err = addr_fault | axi_w_err | axi_r_err`
- Read data mux: SRAM region → `sram_rdata`, MMIO region → `axi_rdata_reg`

#### `Data_Memory.v`
- Synchronous SRAM: write at posedge (byte-masked), read from registered address
- `addr_r` width: `[19:0]` in simulation, `[11:0]` in synthesis

#### `axi_lite_dummy_slave.v`
- Simulation stub, zero-latency handshake, no storage

---

## 3. LSU Verification Testbench Architecture

### 3.1 TB Component Map

```
┌─────────────────────────────────────────────────────────────┐
│                        lsu_env                              │
│  ┌─────────┐  ┌───────────┐  ┌────────────┐  ┌──────────┐ │
│  │sequencer│─▶│  driver   │──▶│  monitor   │─▶│scoreboard│ │
│  │ (gen)   │  │ (stimulus)│  │ (sample)   │  │ (check)  │ │
│  └─────────┘  └─────┬─────┘  └─────┬──────┘  └──────────┘ │
│                     │              │                        │
│                     │     ┌───────▼────────┐               │
│                     │     │  coverage      │               │
│                     │     │  (covergroup)  │               │
│                     │     └────────────────┘               │
│                     │            ▲                          │
│                     ▼            │                          │
│              ┌───────────────────┴──────────┐              │
│              │          lsu_if              │              │
│              │  (clocking blocks + modports)│              │
│              └──────────────┬──────────────┘              │
└─────────────────────────────┼────────────────────────────┘
                              │
                    ┌─────────▼──────────┐
                    │   DUT Subsystem    │
                    │ (ls_unit + hmif +  │
                    │  dmem + axi_slave) │
                    └────────────────────┘
```

### 3.2 TB Files

| File | Lines | Function |
|---|---|---|
| `lsu_pkg.sv` | 47 | Package: memory map constants, LSU opcode encodings, `region_t` enum, `lsunit_to_string()` |
| `lsu_if.sv` | 45 | Interface with `drv_cb` and `mon_cb` clocking blocks, DRV/MON modports |
| `lsu_transaction.sv` | 74 | Transaction class: rand `addr`, `wdata`, `lsunit`, `region`; response `rdata`, `stall_cycles`, `err` |
| `lsu_driver.sv` | 94 | Drives core-side inputs, holds during stall, idles after completion |
| `lsu_monitor.sv` | 116 | Samples core-side outputs, detects completion (lsunit[4] & !core_stall), builds response txn |
| `lsu_ref_model.sv` | 168 | Behavioral golden model with `shadow_mem[logic[31:0]]` associative array, `axi_mock_reg[0:3]` |
| `lsu_scoreboard.sv` | 238 | Compares monitor captures vs ref model predictions, pass/fail logging, summary report |
| `lsu_sequencer.sv` | 195 | Directed tests + random phase, sends txns to driver mailbox |
| `lsu_env.sv` | 72 | Wires all components, creates mailboxes, runs fork/join_none |
| `lsu_tb_top.sv` | 253 | Top-level: DUT instantiation, interface binding, clock gen, watchdog, assertions |
| `lsu_assertions.sv` | 81 | SVA: stall duration, rdata X-check, rdata stability, no-err on SRAM, misaligned no-hang |
| `lsu_coverage.sv` | 104 | Covergroup: op×alignment cross, data patterns, regions, address corners, error output |
| `run_lsu_tb.ps1` | 72 | Vivado compile/elab/sim/coverage script |

### 3.3 Test Sequences (from `lsu_sequencer.sv`)

| # | Test | Description |
|---|---|---|
| 1 | `test_sram_word_rw` | SW then LW same address, verify readback |
| 2 | `test_sram_byte_lanes` | SB to all 4 byte offsets, read back with LBU |
| 3 | `test_sram_half_lanes` | SH to both halfword offsets, read back with LHU |
| 4 | `test_sram_sign_extend` | LB/LH with negative data, verify sign extension |
| 5 | `test_sram_word_data_patterns` | Write/read 6 data patterns: 0, FFFF_FFFF, A5A5_A5A5, 5A5A_5A5A, F0F0_0F0F, DEAD_BEEF |
| 6 | `test_addr_boundary` | SRAM first/last word, just below/above (OOR) |
| 7 | `test_mmio_write` | SW to MMIO, verify no `core_err` |
| 8 | `test_mmio_read` | LW from MMIO, verify data matches dummy slave pattern |
| 9 | `test_oor_access` | LW from unmapped address, verify `core_err=1` |
| 10 | Random phase | 1000 fully-randomized SRAM-only (default) or all-region transactions |

### 3.4 Mailbox Flows

```
sequencer ──drv_mbx──▶ driver ──(drives DUT)──▶ DUT
                                                     │
DUT ──(outputs)──▶ monitor ──scb_mbx──▶ scoreboard
                           └─cov_mbx──▶ coverage
```

### 3.5 SVA Assertions (from `lsu_assertions.sv`)

| Assertion | Check |
|---|---|
| `A_LOAD_STALL_DUR_SRAM` | SRAM load stall must be exactly 1 cycle |
| `A_LOAD_RDATA_GOOD` | No X/Z on rdata after stall drops |
| `A_LOAD_RDATA_STABLE` | rdata stable after stall drops |
| `A_NO_ERR_ON_SRAM_LOAD` | No `core_err` on SRAM loads |
| `A_MISALIGNED_NO_HANG` | Misaligned loads don't hang (stall clears within 20 cycles) |

### 3.6 Coverage (from `lsu_coverage.sv`)

| Coverpoint | Bins |
|---|---|
| `cp_op` | LB, LH, LW, LBU, LHU, SB, SH, SW |
| `cp_alignment` | byte_aligned, offset_1, offset_2, offset_3 |
| `cp_op_x_alignment` | Cross with illegal bins for unaligned LW/SW/LH/SH/LHU |
| `cp_wdata` | zero, ones, aa55, five5aa, f00f, deadbeef |
| `cp_region` | SRAM, MMIO, OOR |
| `cp_err` | no_err, err |
| `cp_op_x_region` | Cross op × region |
| `cp_addr` | sram_first, sram_last, mmio_first, mmio_last, oor_sample |

### 3.7 Simulation Script (`run_lsu_tb.ps1`)
- Compiles RTL (`ls_unit.v`, `hybrid_mem_interface.v`, `Data_Memory.v`, `axi_lite_dummy_slave.v`)
- Compiles TB (`lsu_pkg.sv`, `lsu_tb_top.sv` — which `include`s all other SV files)
- Elaborates: `xelab lsu_tb_top -debug typical --cov_db_dir .`
- Runs: `xsim lsu_tb_top -runall` with Tcl for wave dump + coverage flush
- Reports: HTML coverage via `xcrg`

---

## 4. Reference Model (`lsu_ref_model.sv`)

- **Shadow memory**: `logic [7:0] shadow_mem[logic[31:0]]` — byte-addressed associative array
- **MMIO mock**: `logic[31:0] axi_mock_reg[0:3]` — mirrors dummy slave
- **Prediction methods:**
  - `do_write(addr, wdata, be)` — updates shadow_mem or axi_mock_reg per byte enables
  - `predict_read(addr, funct3)` — returns formatted load data (sign/zero extended, byte-offset aligned)
  - `predict_err(addr)` — returns 1 if address outside SRAM and MMIO
- **Stall prediction**: 0 cycles for SRAM writes, 2 for SRAM reads (hmif WAIT+READY), variable for AXI

---

## 5. RISCOF Compliance Testbench (`tb_riscof.v`)

- 10ns clock, 20ns reset
- `+begin_sig`, `+end_sig`, `+tohost_addr`, `+max_cycles`, `+dump_vcd` plusargs
- HW timeout timer (max_cycles+500 × 10ns)
- PC stagnation detection (500 cycles same PC → dump signature and finish)
- Signature dump: reads DMEM from `begin_sig` to `end_sig`, writes hex words to `sig_file`
- Accesses core via `uut.Memory.dmem.*` (hierarchical path to DMEM instance)
