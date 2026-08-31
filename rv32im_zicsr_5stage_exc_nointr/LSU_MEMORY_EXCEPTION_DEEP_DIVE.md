# LSU, Memory Cycle, Hybrid Controller, Stall & Exception Propagation — Deep Dive

---

## Table of Contents
1. [LSU Data Path Overview](#1-lsu-data-path-overview)
2. [ls_unit — Load/Store Formatting Engine](#2-ls_unit--loadstore-formatting-engine)
3. [hybrid_mem_interface — Address Decoder & Bus Router](#3-hybrid_mem_interface--address-decoder--bus-router)
4. [Data_Memory — Synchronous SRAM](#4-data_memory--synchronous-sram)
5. [Stall Architecture & Pipeline Freeze Logic](#5-stall-architecture--pipeline-freeze-logic)
6. [Exception Propagation System](#6-exception-propagation-system)
7. [Timing Diagrams](#7-timing-diagrams)


---

## 1. LSU Data Path Overview

```
EX Stage                    MEM Stage                              WB Stage
┌────────────┐    ┌──────────────────────────────────────────────┐    ┌───────────┐
│  ALU       │    │  memory_cycle                                │    │writeback  │
│  ResultM   │───▶│      ┌──────────┐     ┌──────────────┐      │    │  _cycle   │
│  = addr    │    │      │ ls_unit  │────▶│hybrid_mem_if │─────▶│───▶│ ResultW   │
│  WriteDataM│    │      │          │     │              │      │    │           │
│  = RS2     │───▶│      │ core_if  │     │  sram_if     │─────▶│    │           │
│  lsunitM   │───▶│      │          │     │  axi_if      │─────▶│    │ ReadDataW │
└────────────┘    │      └──────────┘     └──────────────┘      │    └───────────┘
                  │           │                    │             │
                  │           │  core_stall ────────┼───────────▶│ Hazard Unit
                  │           │  core_err  ────────┼───────────▶│ (stall/flush)
                  │           ▼                    ▼             │
                  │    ┌──────────────────────────────────────┐  │
                  │    │  Exception Merge (misalign + fault)  │  │
                  │    └──────────────────────────────────────┘  │
                  │           │                                  │
                  │           ▼                                  │
                  │    exc_valid_mem_final ────────────────────▶│ MEM→WB reg
                  └──────────────────────────────────────────────┘
```

**Key principle:** The EX stage computes the effective address (ALU_ResultM). The MEM stage does everything memory-related. The WB stage just muxes the result.

---

## 2. ls_unit — Load/Store Formatting Engine

**File:** `ls_unit.v` (161 lines)

### 2.1 Port Map

```
 Core Pipeline Side                   Memory Bridge Side
 ────────────────                    ──────────────────
 core_addr  [31:0]  ──in──▶  ls_unit  ──out──▶  mem_req
 core_wdata [31:0]  ──in──▶           ──out──▶  mem_we
 lsunit     [4:0]   ──in──▶           ──out──▶  mem_addr[31:0]
                                        ──out──▶  mem_wdata[31:0]
 core_rdata [31:0]  ◀──out──           ──out──▶  mem_be[3:0]
 core_stall         ◀──out──           ◀──in───  mem_rdata[31:0]
 core_err           ◀──out──           ◀──in───  mem_stall
                                        ◀──in───  mem_err
```

### 2.2 Control Bus — `lsunit[4:0]` Encoding

```
Bit 4 (en)    : 1 = load/store operation
Bit 3 (is_store): 1 = store, 0 = load
Bits [2:0]    : funct3 (same as RISC-V instruction encoding)
```

| Encoding | Mnemonic | Operation |
|---|---|---|
| `5'b10000` | LB | Load byte, sign-extend |
| `5'b10001` | LH | Load halfword, sign-extend |
| `5'b10010` | LW | Load word |
| `5'b10100` | LBU | Load byte, zero-extend |
| `5'b10101` | LHU | Load halfword, zero-extend |
| `5'b11000` | SB | Store byte |
| `5'b11001` | SH | Store halfword |
| `5'b11010` | SW | Store word |
| `5'b00000` | NOP | Idle / bubble |

### 2.3 Combinational Paths

#### Memory Request Generation (Layer 1)

```verilog
assign mem_req  = is_ls_valid;           // lsunit[4]
assign mem_we   = is_store_op;           // lsunit[4] & lsunit[3]
assign mem_addr = core_addr;             // full 32-bit byte address
assign core_stall = mem_req & mem_stall; // freeze signal
assign core_err   = mem_err;             // access fault pass-through
```

The stall is purely combinational: `core_stall = (active request) AND (bridge says busy)`. The core holds inputs until `core_stall` drops.

#### Load Data Formatting (Layer 2)

**Input:** `raw_mem_rdata[31:0]` (unaligned 32-bit word from bridge)  
**Output:** `formatted_core_rdata[31:0]` (byte/halfword extracted, sign/zero extended)

Algorithm (per funct3):

```
LB (000): byte_offset → select 1 byte, sign-extend to 32
LH (001): byte_offset[1] → select lower/upper 16 bits, sign-extend to 32
LW (010): passthrough raw_mem_rdata
LBU (100): byte_offset → select 1 byte, zero-extend to 32
LHU (101): byte_offset[1] → select lower/upper 16 bits, zero-extend to 32
```

The `byte_offset = core_addr[1:0]` selects which byte lane within the aligned 32-bit word:

```
offset 00: bits [7:0]
offset 01: bits [15:8]
offset 10: bits [23:16]
offset 11: bits [31:24]
```

For halfword: `offset[1]=0` → bits [15:0], `offset[1]=1` → bits [31:16].

#### Store Data Alignment & Strobe Generation (Layer 2)

**Input:** `raw_core_wdata[31:0]` (unaligned, as it would be in a register)  
**Output:** `aligned_mem_wdata[31:0]` and `byte_en_mask[3:0]`

```
SB (000): byte_offset → shift data left by offset*8, enable=1<<offset
SH (001): offset[1]=0 → passthrough, enables=0011
          offset[1]=1 → shift left 16, enables=1100
SW (010): passthrough, enables=1111
```

Example: `SB addr=0x80001003, wdata=0xAA`
- byte_offset = 3
- `aligned_mem_wdata = 0xAA << 24 = 0xAA00_0000`
- `byte_en_mask = 4'b1000`
- Memory at word-address `(0x80001003 >> 2)` = `0x20000400` gets byte lane 3 written with 0xAA

### 2.4 Timing: ls_unit is Pure Combinational

All formatting, alignment, request generation, and stall/error propagation are **combinational** (always @(*) blocks). No registers in ls_unit itself. The pipeline registers are in memory_cycle's MEM/WB flops.

---

## 3. hybrid_mem_interface — Address Decoder & Bus Router

**File:** `hybrid_mem_interface.v` (328 lines)

### 3.1 Address Decode

```verilog
localparam SRAM_BASE  = 32'h8000_0000;
localparam SRAM_LIMIT = 32'h8040_0000;   // 4 MB
localparam MMIO_BASE  = 32'h4000_0000;
localparam MMIO_LIMIT = 32'h4000_FFFF;   // 64 KB

wire addr_in_sram_range = (mem_addr >= SRAM_BASE) && (mem_addr <= SRAM_LIMIT);
wire addr_in_mmio_range = (mem_addr >= MMIO_BASE) && (mem_addr <= MMIO_LIMIT);
wire addr_fault         = mem_req && !(addr_in_sram_range || addr_in_mmio_range);
```

Three regions: SRAM, MMIO (AXI-Lite), and address-fault.

### 3.2 SRAM Routing

```
Combinational:
  sram_en    = sram_req_active  (= mem_req & addr_in_sram_range)
  sram_we    = mem_we
  sram_wmask = mem_be
  sram_addr  = mem_addr[31:2]   // word address (drop low 2 bits)
  sram_wdata = mem_wdata
```

#### SRAM Read FSM (3-state)

```
         ┌─────────────────────────────────────────────┐
         │                                             │
         ▼                                             │
    ┌─────────┐   sram_req_active && !mem_we    ┌─────────┐
    │  IDLE   │─────────────────────────────────▶│  WAIT   │
    │ (00)    │                                  │ (01)    │
    └────┬────┘◀─────────────────────────────────└────┬────┘
         │                                            │
         │  else                                      │  (always 1 cycle)
         │                                            │
         │                                     ┌──────▼──────┐
         │                                     │   READY     │
         │                                     │   (10)      │
         │                                     └──────┬──────┘
         │                                            │
         └────────────────────────────────────────────┘
                       (always 1 cycle)
```

- **IDLE**: Request arrives, drive sram_addr to SRAM. `sram_stall_needed=1`. At posedge, SRAM latches address.
- **WAIT**: SRAM internally drives `sram_rdata` from latched address (1 cycle SRAM latency). `sram_stall_needed=1`.
- **READY**: `sram_rdata` is valid. `sram_stall_needed=0`. MEM/WB captures `lsu_core_rdata` on next posedge.

**Total SRAM read latency observed by core: 2 cycles** (IDLE + WAIT, stall held both cycles).

SRAM writes: pass-through, **no stall** (1 cycle, write completes at posedge).

#### SRAM Read Cycle Trace

```
Cycle    : T0         T1         T2         T3
─────    : ──         ──         ──         ──
hmif FSM : IDLE       WAIT       READY      IDLE
core_stall: 1          1          0          0
sram_en  : 1          1          1          0
sram_addr: A          A          A          (next)
DMEM     : (latch A)  (compute)  (valid)    —
sram_rdata: X          X          data_A     data_A
mem_rdata : X          X          data_A     data_A
MEM→WB   : (hold)     (hold)     (hold)     ← capture data_A
```

### 3.3 AXI4-Lite Write FSM (4-state)

```
                  ┌──────────────┐
                  │              │
                  ▼              │
    ┌──────────┐  awready & wready  ┌───────────┐
    │  IDLE    │───────────────────▶│ WAIT_RESP │
    │  (00)    │                    │   (11)    │
    └──┬───┬───┘                    └─────┬─────┘
       │   │                             │
       │   └── only awready ──▶ WAIT_DATA│
       │                    ┌──────────┐ │
       │                    │WAIT_DATA │ │
       │                    │   (10)   │─┘
       │                    └─────┬────┘
       │                          │
       │   └── only wready ──▶ WAIT_ADDR
       │                    ┌──────────┐
       │                    │WAIT_ADDR │
       │                    │   (01)   │──(wait for wready)
       │                    └──────────┘
       │                                    bvalid
       └───────────────────────────────────────────┘
```

- IDLE: Capture addr/wdata/strb, assert awvalid+wvalid, set `axi_w_stall=1`
- WAIT_ADDR: awvalid=1, wait for awready
- WAIT_DATA: wvalid=1, wait for wready
- WAIT_RESP: wait for bvalid, capture bresp (OKAY/error), clear stall on completion

### 3.4 AXI4-Lite Read FSM (2-state)

```
    ┌──────────┐  mem_re && arready  ┌────────────┐
    │  IDLE    │────────────────────▶│ WAIT_READ  │
    │  (00)    │                     │    (01)    │
    └──────────┘◀────────────────────┘────────────┘
                       rvalid
```

- IDLE: assert arvalid, capture araddr, set `axi_r_stall=1`
- WAIT_READ: assert rready, wait for rvalid, capture rdata+rresp, clear stall

### 3.5 Aggregation Layer

```verilog
always @(*) begin
    mem_stall = sram_stall_needed | axi_w_stall | axi_r_stall;
    mem_err   = addr_fault | axi_w_err | axi_r_err;
    
    if (sram_rd_state == SRAM_WAIT || sram_rd_state == SRAM_READY)
        mem_rdata = sram_rdata;
    else
        mem_rdata = axi_rdata_reg;
end
```

Stall is the OR of all active interface stalls. Error is OR of address fault + AXI errors. Read data is muxed by FSM state.

---

## 4. Data_Memory — Synchronous SRAM

**File:** `Data_Memory.v` (101 lines)

### 4.1 Architecture

```
                 ┌──────────────┐
sram_addr[29:0]──▶  local_addr  │
                 │  subtractor  │──▶ addr_r (registered) ──▶ mem_array[addr_r] ──▶ sram_rdata
sram_wdata[31:0]─▶  (DMEM_BASE) │
                 └──────────────┘
```

### 4.2 Address Subtraction

```verilog
localparam DMEM_BASE = 30'h20000000;   // 0x80001000 >> 2
wire [29:0] local_addr_full = sram_addr - DMEM_BASE;
```

DMEM is mapped to `0x80001000` byte address (word addr `0x20000400`). The subtractor strips the base so `mem_array[0] = 0x80001000`.

### 4.3 Registered Pipeline

All control signals are registered (1-cycle delay):

```verilog
always @(posedge clk) begin
    wdata_r   <= sram_wdata;
    addr_r    <= local_addr;
    wmask_r   <= sram_wmask;
    sram_en_r <= sram_en;
    sram_we_r <= sram_we;
end
```

### 4.4 Synchronous Write (Registered)

```verilog
always @(posedge clk) begin
    if (sram_en_r && sram_we_r) begin
        if (wmask_r[0]) mem_array[addr_r][7:0]   <= wdata_r[7:0];
        if (wmask_r[1]) mem_array[addr_r][15:8]  <= wdata_r[15:8];
        if (wmask_r[2]) mem_array[addr_r][23:16] <= wdata_r[23:16];
        if (wmask_r[3]) mem_array[addr_r][31:24] <= wdata_r[31:24];
    end
end
```

Byte-masked write, 1 cycle after address is presented. Write enables and data are registered from the same posedge that latched the address.

### 4.5 Synchronous Read (Registered)

```verilog
assign sram_rdata = (sram_en_r && !sram_we_r) ? mem_array[addr_r] : 32'bx;
```

Read data is driven combinationally from the **registered** address. When `sram_en=1` at posedge T, address is latched, and by the end of T the output `sram_rdata` reflects `mem_array[addr_T]`. However, in the hmif, the data is only captured in the READY state (T+2 relative to original request), giving the effective 2-cycle latency.

### 4.6 Sizes

| Condition | Array Size | Address Width |
|---|---|---|
| Simulation (`ifndef SYNTHESIS`) | 1,048,576 × 32 (4 MB) | `[19:0]` |
| Synthesis (`ifdef SYNTHESIS`) | 4,096 × 32 (16 KB) | `[11:0]` |

**Simulation init:** `$readmemh("dmem.hex")` loads into `mem_array`.

---

## 5. Stall Architecture & Pipeline Freeze Logic

The stall system is distributed between `memory_cycle.v` (local gate logic) and `hazard_unit.v` (global pipeline control).

### 5.1 Stall Sources & Propagation

```
Source                   Mechanism           Freezes
──────                   ─────────           ───────
SRAM read (hmif)    ──▶  mem_stall_out   ──▶ IF, ID, EX, MEM (StallF/D/E/M)
AXI write (hmif)    ──▶  mem_stall_out   ──▶ IF, ID, EX, MEM
AXI read (hmif)     ──▶  mem_stall_out   ──▶ IF, ID, EX, MEM
Load-use (hazard)   ──▶  lwstall         ──▶ IF, ID (StallF/D), flush EX
CSR-to-CSR (hazard) ──▶  csr_stall       ──▶ IF, ID (StallF/D), flush EX
CSR-GPR (hazard)    ──▶  csr_gpr_stall   ──▶ IF, ID (StallF/D), flush EX
M-extension (EX)    ──▶  stallMUL        ──▶ IF, ID (StallF/D), flush EX, flush M
```

### 5.2 The Gated Request & Core Stall Bypass

```verilog
// memory_cycle.v line 273-280
wire gated_mem_req = lsu_mem_req & valid_M & ~(exc_valid_M | misaligned_load | misaligned_store);
wire gated_mem_we  = lsu_mem_we  & valid_M & ~(exc_valid_M | misaligned_load | misaligned_store);
wire core_stall_gated = lsu_core_stall & ~(misaligned_load | misaligned_store);
```

**Purpose:** Suppress memory transactions for instructions that are already faulted, misaligned, or bubbles. The `core_stall_gated` signal is critical:

- For a **normal** SRAM load: `core_stall_gated = lsu_core_stall` (hold MEM/WB reg)
- For a **misaligned** load: `core_stall_gated = 0` (do NOT hold — let exception propagate to WB)

Without this gating, a misaligned load would hang the pipeline because hmif would drive `mem_stall=1` forever (no valid transaction started) while the MEM/WB register is frozen, preventing the exception from reaching the commit controller.

### 5.3 Hazard Unit Stall Distribution

```verilog
// hazard_unit.v
assign StallF = wb_redirect ? 0 : (lwstall | csr_stall | csr_gpr_stall | stallMUL | mem_stall_i);
assign StallD = wb_redirect ? 0 : (lwstall | csr_stall | csr_gpr_stall | stallMUL | mem_stall_i);
assign StallE = wb_redirect ? 0 : (mem_stall_i);
assign StallM = wb_redirect ? 0 : (mem_stall_i);
```

| Stall Signal | Freezes | Why |
|---|---|---|
| `StallF` | PC register | No new fetch |
| `StallD` | IF/ID pipeline reg | Decode sees same instruction |
| `StallE` | ID/EX pipeline reg | EX stage instruction stays (MUL or mem wait) |
| `StallM` | EX/MEM pipeline reg | MEM stage result stays valid |

**WB redirect override:** When a trap or MRET commits, all stalls are forced to 0 so the redirect PC can propagate to IF immediately.

### 5.4 Fetch Stage Stall Path

```
mem_stall_out ──▶ hazard_unit ──▶ StallF ──▶ PC register (hold)
                                ──▶ StallD ──▶ IF/ID reg (hold)
                
imem_controller.stall (spec_tag) ──▶ OR'd with StallF for PC
                                  ──▶ OR'd with StallD for IF/ID
```

In `fetch_cycle.v`:

```verilog
PC program_counter (
    .StallF ((StallF | imem_stall_raw) && !PCSrcE && !wb_trap_redirect)
);
```

The PC stall also includes the imem_controller's own drain stall (`imem_stall_raw`) but is overridden during redirects.

### 5.5 Stall Timing for SRAM Read (Walkthrough)

```
Cycle    :  T0          T1          T2          T3          T4
─────    :  ──          ──          ──          ──          ──
EX       :  compute     (held)      (held)      (held)      next
           addr=X      StallM=1    StallM=1    StallM=1    StallM=0
MEM      :  request     ls_unit     hmif        hmif        capture
           lsunit=LW   hmif IDLE   hmif WAIT   hmif READY  lsu_rdata → MEM/WB
StallF   :  0           1           1           1           0
StallD   :  0           1           1           1           0
StallE   :  0           1           1           1           0
StallM   :  0           1           1           1           0
```

- **T0**: EX finishes ALU, drives ALU_ResultM (=address). At posedge, EX/MEM captures it.
- **T1**: MEM stage active. ls_unit sees valid request → `core_stall=1`. hmif enters SRAM_IDLE. hazard_unit asserts StallF/D/E/M.
- **T2**: hmif enters SRAM_WAIT. Stall continues.
- **T3**: hmif enters SRAM_READY. `core_stall→0`. At posedge T3, MEM/WB captures `lsu_core_rdata` (now valid). Stall releases.
- **T4**: Next instruction advances into EX.

**Net pipeline penalty: 2 cycles** for an SRAM load. Writes have 0 penalty.

---

## 6. Exception Propagation System

### 6.1 Overview: Five-Stage "Propagate-and-Commit"

Exceptions are **precise** — they propagate alongside the faulting instruction through the pipeline and are committed (cause PC redirect) only at the WB stage.

```
        IF          ID          EX          MEM         WB
exc   ┌─────┐    ┌─────┐    ┌─────┐    ┌─────┐    ┌──────────┐
bus   │     │    │     │    │     │    │     │    │ trap     │
───▶  │ det │───▶│ det │───▶│ det │───▶│ det │───▶│ commit?  │
      │     │    │     │    │     │    │     │    │ (wb_trap_ │
      └──┬──┘    └──┬──┘    └──┬──┘    └──┬──┘    │ mret_ctrl)│
         │          │          │          │       └──────────┘
         │   OR     │   OR     │   OR     │   OR
    prev_exc  prev_exc  prev_exc  prev_exc
         │          │          │          │
         ▼          ▼          ▼          ▼
     exc_valid_D  exc_valid_E  exc_valid_M  exc_valid_W
     exc_cause_D  exc_cause_E  exc_cause_M  exc_cause_W
     exc_tval_D   exc_tval_E   exc_tval_M   exc_tval_W
     exc_pc_D     exc_pc_E     exc_pc_M     exc_pc_W
```

Each stage has a 4-wire exception bundle: `{exc_valid, exc_cause[4:0], exc_tval[31:0], exc_pc[31:0]}`.

### 6.2 Per-Stage Exception Detection

#### IF Stage (fetch_cycle.v)

```verilog
assign exc_valid_F = (PC_next[1:0] != 2'b00);  // misaligned PC
assign exc_cause_F = 5'd0;                      // cause 0
assign exc_pc_F    = PC_next;
assign exc_tval_F  = PC_next;
```

Only misaligned instruction address (cause=0). The pipeline register captures this in the NORMAL transition (not during stall or flush).

#### ID Stage (decode_cycle.v)

```verilog
assign new_exc_valid_D = valid_D && (illegal_instr || is_ecall || is_ebreak);
assign new_exc_cause_D = (valid_D && illegal_instr) ? 5'd2 : 
                         (valid_D && is_ecall)      ? 5'd11 : 
                         (valid_D && is_ebreak)     ? 5'd3  : 5'd0;

// Merge with propagated (IF exception takes priority)
assign next_exc_valid_D = exc_valid_D | new_exc_valid_D;
assign next_exc_cause_D = exc_valid_D ? exc_cause_D : new_exc_cause_D;
```

- illegal_instr (cause=2) — gated by `valid_D`
- ecall (cause=11)
- ebreak (cause=3)

The "first wins" merge: a propagated IF exception override the locally detected one.

#### EX Stage (execute_cycle.v)

```verilog
assign new_exc_valid_E = branch_taken_raw & target_misaligned_E;
assign new_exc_cause_E = 5'b00000;   // cause 0: instruction-address-misaligned
assign new_exc_tval_E  = PCTargetE;

// Merge with propagated
assign next_exc_valid_E = exc_valid_E | new_exc_valid_E;
```

Misaligned branch/jump target (cause=0). Branch is suppressed (`PCSrcE=0` when target is misaligned).

#### MEM Stage (memory_cycle.v)

```verilog
wire misaligned_load  = is_load && (
    (lsunitM[2:0] == 3'b010 && ALU_ResultM[1:0] != 2'b00) || // LW
    (lsunitM[2:0] == 3'b001 && ALU_ResultM[0]   != 1'b0)  || // LH
    (lsunitM[2:0] == 3'b101 && ALU_ResultM[0]   != 1'b0)     // LHU  ← BUG
);

wire exc_valid_mem_local = (misaligned_load | misaligned_store | lsu_core_err) & valid_M;

wire [4:0] exc_cause_mem_local =
    misaligned_load  ? 5'd4 :      // Load address misaligned
    misaligned_store ? 5'd6 :      // Store address misaligned
    (lsu_core_err & is_load)  ? 5'd5 :  // Load access fault
    (lsu_core_err & is_store) ? 5'd7 :  // Store access fault
                    5'd0;

assign exc_valid_mem_final = exc_valid_M | exc_valid_mem_local;
```

The `lsu_core_err` signal comes from `hybrid_mem_interface.mem_err` which is OR of `addr_fault`, `axi_w_err`, `axi_r_err`.

### 6.3 Exception Commit (wb_trap_mret_commit_controller)

```verilog
assign trap_commit = valid_W & exc_valid_W;
assign mret_commit = valid_W & is_mret_W & ~exc_valid_W;

assign wb_trap_redirect_o = trap_commit | mret_commit | irq_commit;
assign trap_target_o = (trap_commit | irq_commit) ? {mtvec_i[31:2], 2'b00} : {mepc_i[31:2], 2'b00};
assign flush_pipeline_onehot_o = wb_trap_redirect_o ? 4'b1111 : 4'b0000;
```

On commit:
1. `wb_trap_redirect` goes high → fetch_cycle loads `trap_target` as PC_next
2. `flush_pipeline_onehot=1111` → all stages flushed (FlushD/E/M/W)
3. CSR regfile Port C writes: mepc ← exc_pc_W, mcause ← cause, mtval ← tval, mstatus updated

### 6.4 Special Case: Misaligned Load/Store

The interaction between stall and exception for misaligned loads is subtle:

```
Cycle    :  T0          T1          T2          T3
─────    :  ──          ──          ──          ──
MEM stage:  request     misalign    (exception  (commit at WB)
            LW @A       detected    captured)   
                        exc_valid   exc_valid
                        _mem_local  _mem_final
                        =1          =1
core_stall: 1           1           X           0
gated_req : 1           0 (suppress)0           0
core_stall_: 1          0 (bypass!) 0           0
gated
MEM→WB    : (hold)      (hold)      ← capture exc_valid=1
                                    ← capture exc_cause=4
```

**Key:** At T1, the misalignment is detected. `gated_mem_req` goes to 0 (no transaction sent to hmif). But `lsu_core_stall` could still be 1 from the previous cycle. The `core_stall_gated` signal KNOCKS OUT the stall so the MEM/WB register advances and captures the exception at the next posedge.

Without this bypass, the pipeline would deadlock: hmif keeps `mem_stall=1` because no transaction was started, but the MEM/WB reg can't advance to send the exception to WB.

### 6.5 Exception Priority Table

| Stage | Exception | Cause | Source |
|---|---|---|---|
| IF | Instruction address misaligned | 0 | `PC_next[1:0] != 00` |
| ID | Illegal instruction | 2 | `opcode_check` + `valid_D` |
| ID | ECALL | 11 | env call |
| ID | EBREAK | 3 | breakpoint |
| EX | Instruction address misaligned (branch) | 0 | `PCTarget_tentative[1:0] != 00` |
| MEM | Load address misaligned | 4 | address alignment check |
| MEM | Store address misaligned | 6 | address alignment check |
| MEM | Load access fault | 5 | `hmif.mem_err` + is_load |
| MEM | Store access fault | 7 | `hmif.mem_err` + is_store |

"First wins" per stage merge: if an earlier stage propagated an exception, later-stage detection is suppressed for that instruction.

---

## 7. Timing Diagrams

### 7.1 SRAM Load — Complete Transaction

```
clk      : ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐
           │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
cycle #   :  0   1   2   3   4   5   6   7
─────     : ──  ──  ──  ──  ──  ──  ──  ──
EX/MEM    : LW @A                    next
core_addr :  A   A   A   A   0   0
lsunit    : LW  LW  LW  LW  NOP NOP
core_stall:  0   1   1   1   0   0
hmif state: IDL IDL WAIT RDY IDL IDL
sram_en   :  0   1   1   1   0   0
sram_addr :  X   A   A   A   X   X
sram_rdata:  X   X   X   dA  dA  X
mem_rdata :  X   X   X   dA  dA  X
MEM/WB    :  (old)          (hold)   ←capture dA
valid_W   :  0   0   0   0   1   0
```

### 7.2 SRAM Store — No Stall

```
clk      : ┌─┐ ┌─┐ ┌─┐ ┌─┐
cycle #   :  0   1   2   3
EX/MEM    : SW @A        next
core_stall:  0   0   0   0
hmif state: IDL IDL IDL IDL  (bypass for write)
sram_en   :  0   1   0   0
sram_we   :  0   1   0   0
sram_addr :  X   A   A   X
DMEM write:      (write @posedge 1)
```

### 7.3 Exception Propagation — Full Path

```
Cycle    :  0      1      2      3      4      5      6
Stage
IF       :  instrA instrB instrC (flush) (trap) (refetch)
ID       :         instrA instrB (flush) (flush) (trap)
EX       :                instrA instrB (flush)
MEM      :                       instrA (exc_det) (mem_exc)
WB       :                              instrA (commit)
                                                    │
                                                    ├─▶ wb_trap_redirect=1
                                                    ├─▶ flush all stages
                                                    ├─▶ PC ← mtvec
                                                    └─▶ CSR: mepc=exc_pc, mcause=exc_cause
```

The faulting instruction `instrA` propagates from IF to WB (cycles 0-4). At cycle 4 in MEM, the exception is detected. At cycle 5 it reaches WB and commits. The redirect happens in cycle 5, and the trap handler is fetched in cycle 6.

### 7.4 AXI Read — Variable Latency

```
Cycle    :  T0    T1    T2    T3    T4    T5    T6
─────    :  ──    ──    ──    ──    ──    ──    ──
mem_req  :  1     0     0     0     0     0     0
mem_we   :  0     0     0     0     0     0     0
core_stall: 1     1     1     1     1     0     0
AXI FSM  : IDLE  W_RD  W_RD  W_RD  W_RD  IDLE
arvalid  :  1     0     0     0     0     0
arready  :  0     1     0     0     0     0    (slave accepts at T1)
rvalid   :  0     0     0     0     1     0    (slave responds at T4)
rdata    :  X     X     X     X    dA     X
```

AXI latency is unbounded — slave determines when to assert `arready` and `rvalid`. The core stalls for the full duration.
