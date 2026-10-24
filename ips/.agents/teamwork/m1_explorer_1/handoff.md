# Milestone 1: Pipeline Monitors (Fetch, Retire, LSU) Exploration Report

**Agent**: `m1_explorer_1`  
**Working Directory**: `c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\m1_explorer_1`  
**Target Milestone**: M1 (Passive Protocol & Pipeline Monitors with Circular Freeze Buffers)  
**Date**: 2026-10-01T21:40:00Z  

---

## 1. Observation

### 1.1 Existing Implementations in `Verification/infrastructure/monitors/`

Direct inspection of `fetch_monitor.sv`, `retire_monitor.sv`, and `lsu_monitor.sv` revealed:

1. **`fetch_monitor.sv`** (`Verification/infrastructure/monitors/fetch_monitor.sv:1-61`):
   - Accepts ports: `clk`, `rst_n`, `freeze`, `pc_f` [31:0], `instr_f` [31:0], `imem_en`, `stall_f`.
   - Ring buffer: `fetch_txn_t ring_buffer [0:RING_BUFFER_DEPTH-1];` with `parameter RING_BUFFER_DEPTH = 64`.
   - Capture condition: `if (imem_en && !stall_f && !freeze)`.
   - Missing fields in `fetch_txn_t` assignment: Only `timestamp`, `pc`, `instr`, `valid` are assigned; fields `rel_cycle`, `seq`, `stall`, `branch_taken`, `pc_next`, `exc_valid`, `exc_cause`, `exc_tval`, `region` defined in `tb_pkg::fetch_txn_t` are left zero/uninitialized.
   - Missing shadow mapping: Does not maintain or export any PC-to-instruction shadow table for the retirement monitor.

2. **`retire_monitor.sv`** (`Verification/infrastructure/monitors/retire_monitor.sv:1-72`):
   - Accepts ports: `clk`, `rst_n`, `freeze`, `pc_w` [31:0], `instr_w` [31:0], `rd_addr_w` [4:0], `rd_wdata_w` [31:0], `reg_we_w`, `trap_w`.
   - Flawed retirement condition (Line 40):
     ```systemverilog
     if ((instr_w != 32'h0000_0000 || trap_w) && !freeze) begin
     ```
     - Core RTL in WB stage has **NO** `InstrW` signal (verified in `riscv_core/rtl/top.v` and `writeback_cycle.v`).
     - Real architectural commit occurs on `valid_W & ~exc_valid_W`.
     - Valid instructions with encoding `0x0000_0000` (illegal instruction / trap) or `0x0000_0013` (nop / addi x0, x0, 0) are mis-handled by `instr_w != 0`.
   - Counter naming discrepancy:
     - `retire_monitor.sv` declares `longint unsigned total_retired;` (Line 24).
     - `soc_tb_top.sv` line 514 references `u_retire_mon.total_retired_instr`. This will cause a compilation error.

3. **`lsu_monitor.sv`** (`Verification/infrastructure/monitors/lsu_monitor.sv:1-79`):
   - Accepts ports: `clk`, `rst_n`, `freeze`, `lsu_req`, `lsu_we`, `lsu_addr` [31:0], `lsu_wdata` [31:0], `lsu_be` [3:0], `lsu_rdata` [31:0], `lsu_stall`, `lsu_err`.
   - Missing ports required by PROJECT.md Feature 4: Does not accept `PC_M`, `lsunitM`, or `valid_M`.
   - Capture condition (Line 45): `if (lsu_req && !lsu_stall && !freeze)`. Correctly corresponds to transaction completion.

### 1.2 Pipeline Signal Taps in Core RTL (`riscv_core/rtl/`)

Direct inspection of `top.v`, `fetch_cycle.v`, `memory_cycle.v`, and `wb_trap_mret_commit_controller.v`:

1. **Top-level Integration (`riscv_core/rtl/top.v`)**:
   - Instantiates `fetch_cycle` as `Fetch` (Line 295).
   - Instantiates `memory_cycle` as `Memory` (Line 446).
   - Instantiates `wb_trap_mret_commit_controller` as `wb_commit` (Line 515).
   - Internal signals:
     - `wire valid_W;` (Line 165) — WB stage valid.
     - `wire exc_valid_W;` (Line 184) — WB stage exception.
     - `wire [31:0] PC_W;` (Line 105) — Committing PC.
     - `wire [4:0] RDW;` (Line 82) — Committing destination register.
     - `wire [31:0] ResultW;` (Line 92) — Committing register write data.
     - `wire RegWriteW_gated;` (Line 266, 283): `assign RegWriteW_gated = RegWriteW & valid_W & ~exc_valid_W & ~mret_commit;`.
     - `wire trap_commit_valid;` (Line 246, 530) — Synchronous/asynchronous trap commit.
     - `wire trap_commit_is_interrupt;` (Line 252, 536) — 1 if interrupt, 0 if exception.
     - `wire [30:0] trap_commit_cause;` (Line 247, 531) — Trap cause code.
     - `wire mret_commit;` (Line 253, 542) — MRET commit strobe.
     - `wire is_mret_W;` (Line 190) — MRET opcode in WB.

2. **Fetch Stage Signals (`riscv_core/rtl/fetch_cycle.v`)**:
   - `PCF` [31:0] (Line 97) — Current registered PC (byte address).
   - `InstrF` [31:0] (Line 100) — Instruction word from `imem_controller` (gated with NOP during flush).
   - `PCPlus4F` [31:0] (Line 98) — `PCF + 4`.
   - `PC_next` [31:0] (Line 99, 119-121) — Next PC: `wb_trap_redirect ? trap_target : PCSrcE ? PCTargetE : PCPlus4F`.
   - `imem_sram_en` (Line 86) — Chip enable / fetch request.
   - `imem_stall` (Line 83) — 1-cycle drain stall.
   - `StallF` (Line 59) — Stall from hazard unit.

3. **Memory Stage Signals (`riscv_core/rtl/memory_cycle.v`)**:
   - `lsu_mem_req` (Line 70, 179): `lsu_raw_req & valid_M & ~(exc_valid_M | misaligned_load | misaligned_store)`.
   - `lsu_mem_we` (Line 71, 180): Store enable.
   - `lsu_mem_addr` [31:0] (Line 72, 169): Effective address.
   - `lsu_mem_wdata` [31:0] (Line 73, 170): Aligned store data.
   - `lsu_mem_be` [3:0] (Line 74, 171): Byte enables.
   - `lsu_mem_rdata` [31:0] (Line 75, 172): Read data.
   - `lsu_mem_stall` (Line 76, 173): Memory subsystem stall.
   - `lsu_mem_err` (Line 77, 174): Bus error.
   - `PC_M` [31:0] (Line 48) — MEM stage PC.
   - `lsunitM` [4:0] (Line 47) — LSU operation opcode (`[4]=req, [3]=is_store, [2:0]=funct3`).
   - `valid_M` (Line 50) — MEM stage valid.

4. **Hierarchical Instantiation in SoC Top (`RTL_SOC/riscforge_soc_subsystem.sv`)**:
   - Core instance is `i_riscv_core` (Line 1207: `top i_riscv_core (...)`).
   - In `soc_tb_top.sv`, lines 182-260 incorrectly referenced `dut.u_core.*` instead of `dut.i_riscv_core.*`.

5. **Disassembler Module**:
   - Located at `Verification/step4_checkers/step4_disasm.sv`.
   - Package `step4_disasm_pkg` exports `function automatic string disasm(input logic [31:0] i);`.

---

## 2. Logic Chain

```
[Observation 1.1: Core WB has no InstrW]
                │
                ▼
[Step 1: Raw instruction word is discarded after Decode stage in RTL]
                │
                ▼
[Observation 1.2: Fetch stage observes (PCF, InstrF)]
                │
                ▼
[Step 2: Shadow PC-to-Instruction tracking binds PCF -> InstrF on every valid fetch]
                │
                ▼
[Step 3: At Writeback commit, PC_W queries the shadow table to recover InstrW without touching RTL]
                │
                ▼
[Observation 1.2: top.v signals valid_W, exc_valid_W, mret_commit, RegWriteW_gated]
                │
                ▼
[Step 4: True instruction retirement is valid_W & ~exc_valid_W, NOT (instr_w != 0)]
                │
                ▼
[Observation 1.1: Ring buffer wraps every 64 entries]
                │
                ▼
[Step 5: Synchronous freeze locks head_ptr; modulo arithmetic indexes the last 64 events]
```

### Step 1: Why Shadow PC-to-Instruction WB Tracking Is Mandatory
In `riscv_core`, the 5-stage pipeline decodes instructions in the ID stage (`decode_cycle.v`). The 32-bit opcode is decoded into control signals (`ALUControlE`, `RegWriteE`, `MemWriteE`, `lsunitE`, etc.). Neither `execute_cycle.v` nor `memory_cycle.v` pipelines the 32-bit instruction word; only `PCE`, `PC_M`, and `PC_W` are propagated. Modifying RTL pipeline registers is prohibited. Therefore, a shadow association table (`pc_to_instr[PC]`) populated during Fetch is the only non-intrusive method to provide disassembly for retired instructions.

### Step 2: Shadow Table Architecture
Because RISCFORGE uses Harvard memory architecture (separate ISRAM at `0x0001_0000` and BootROM at `0x0000_0000`), instructions in memory do not change at runtime. An associative map `logic [31:0] shadow_pc_to_instr[logic [31:0]];` indexed by byte PC:
- On every valid fetch (`imem_sram_en && !stall_f && !freeze`), `shadow_pc_to_instr[pc_f] = instr_f;`.
- At retirement (`valid_W & ~exc_valid_W`), `retire_monitor` looks up `shadow_pc_to_instr[pc_w]`.
- Because instructions must be fetched before they can reach Writeback 4–5 cycles later, `shadow_pc_to_instr[pc_w]` is guaranteed to exist.
- Fallback: Backdoor read from `Instruction_Memory_new.mem_array[(pc_w - 32'h0001_0000) >> 2]` if ever missing.

### Step 3: Architectural Instruction Retirement Detection
In `wb_trap_mret_commit_controller.v`:
- `assign trap_commit = valid_W & exc_valid_W;`
- `assign mret_commit = valid_W & is_mret_W & ~exc_valid_W;`
- In `top.v`: `assign RegWriteW_gated = RegWriteW & valid_W & ~exc_valid_W & ~mret_commit;`.
Hence:
- **Normal instruction retirement**: `valid_W & ~exc_valid_W` (includes MRET commit and normal ALU/LSU/Branch/CSR commit).
- **Trap / exception commit**: `valid_W & exc_valid_W` (commits trap handler redirection).
- Replacing `(instr_w != 32'h0 || trap_w)` with `((valid_w && ~exc_valid_w) || trap_w)` aligns the monitor with true architectural commit semantics.

### Step 4: 64-Entry Circular Ring Buffer Architecture
To fulfill R1 ("64-entry non-intrusive circular history ring buffers across Fetch, Retire (RVFI), LSU"):
- Array: `ring_buffer[0:63]`.
- Counter: `head_ptr` (range 0..63) and monotonic `total_count`.
- Write side:
  ```systemverilog
  if (!freeze && txn_valid) begin
    ring_buffer[head_ptr] <= txn;
    head_ptr <= (head_ptr == 63) ? 0 : head_ptr + 1;
    total_count <= total_count + 1;
  end
  ```
- Dump traversal (newest first or oldest first):
  - Retained count $M = \min(\text{total\_count}, 64)$.
  - Entry at rank $k$ ($0 \le k < M$, where $k=0$ is newest):
    `idx = (head_ptr - 1 - k + 64*2) % 64;`

### Step 5: Freeze Input Semantics
When `freeze == 1'b1`:
- Write pointer increment is gated: `head_ptr <= head_ptr;`.
- Ring buffer contents are frozen and cannot be overwritten by subsequent simulation cycles.
- Cycle at freeze is recorded: `frozen_at <= cycle_cnt;`.
- All 6 monitors share the same `freeze` net from `failure_reporter.freeze_monitors`.

---

## 3. Caveats

1. **Self-Modifying Code**: The shadow PC map assumes code is static (not self-modifying). This holds true for all RISCFORGE baremetal C test suites where ISRAM is write-protected for non-privileged code.
2. **Dual Monitor Stacks**: The repository contains both standalone module monitors (`fetch_monitor.sv`, etc.) and class monitors (`rf_monitors.sv`, etc.). `soc_tb_top.sv` instantiates the module monitors. The Worker must ensure the module monitors in `Verification/infrastructure/monitors/` are fully upgraded and that `soc_tb_top.sv` hierarchy taps are corrected.
3. **Disassembler Scope**: `step4_disasm.sv` decodes RV32IM and Zicsr (MRET, ECALL, CSRRW, etc.). Compressed instructions (RVC) are not present in this core configuration.

---

## 4. Conclusion & Complete Implementation Plan for the Worker

The Worker should apply the following precise implementations:

### 4.1 Update `tb_pkg.sv` (Add Shared Shadow PC Map & Types)
Add thread-safe package functions to `tb_pkg.sv`:
```systemverilog
// In tb_pkg.sv:
logic [31:0] shadow_pc_imem [logic [31:0]];

function automatic void shadow_record_fetch(logic [31:0] pc, logic [31:0] instr);
  shadow_pc_imem[pc] = instr;
endfunction

function automatic logic [31:0] shadow_lookup_instr(logic [31:0] pc);
  if (shadow_pc_imem.exists(pc))
    return shadow_pc_imem[pc];
  return 32'h0000_0000;
endfunction
```

### 4.2 Upgrade `fetch_monitor.sv`
1. **Ports**:
   - `clk`, `rst_n`, `freeze`
   - `pc_f` [31:0] (connect to `dut.i_riscv_core.Fetch.PCF`)
   - `instr_f` [31:0] (connect to `dut.i_riscv_core.Fetch.InstrF`)
   - `imem_en` (connect to `dut.i_riscv_core.imem_sram_en`)
   - `stall_f` (connect to `dut.i_riscv_core.Fetch.imem_stall | dut.i_riscv_core.StallF`)
   - `pc_next` [31:0] (connect to `dut.i_riscv_core.Fetch.PC_next`)
2. **Behavior**:
   - On `(imem_en && !stall_f && !freeze)`:
     - Push transaction into 64-entry `ring_buffer[head_ptr]`.
     - Register `shadow_record_fetch(pc_f, instr_f);`.
     - Advance `head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;`.
     - Increment `total_fetches <= total_fetches + 1;`.
   - Provide `dump_recent_fetches(int count = 10)` formatting timestamp, PC, instruction, and branch tag.

### 4.3 Upgrade `retire_monitor.sv`
1. **Ports**:
   - `clk`, `rst_n`, `freeze`
   - `valid_w` (connect to `dut.i_riscv_core.valid_W`)
   - `exc_valid_w` (connect to `dut.i_riscv_core.exc_valid_W`)
   - `pc_w` [31:0] (connect to `dut.i_riscv_core.PC_W`)
   - `rd_addr_w` [4:0] (connect to `dut.i_riscv_core.RDW`)
   - `rd_wdata_w` [31:0] (connect to `dut.i_riscv_core.ResultW`)
   - `reg_we_w` (connect to `dut.i_riscv_core.RegWriteW_gated`)
   - `trap_w` (connect to `dut.i_riscv_core.trap_commit_valid`)
   - `trap_is_interrupt` (connect to `dut.i_riscv_core.trap_commit_is_interrupt`)
   - `trap_cause` [30:0] (connect to `dut.i_riscv_core.trap_commit_cause`)
   - `is_mret_w` (connect to `dut.i_riscv_core.is_mret_W | dut.i_riscv_core.mret_commit`)
   - Optional `instr_w` [31:0] (default 0).
2. **Behavior**:
   - Condition: `wire retire_fire = (valid_w && ~exc_valid_w);`
   - Condition: `wire trap_fire   = trap_w;`
   - Total count: Maintain `total_retired_instr` (incremented on `retire_fire && !freeze`).
   - Instruction resolution:
     ```systemverilog
     logic [31:0] resolved_instr;
     resolved_instr = (instr_w != 32'h0) ? instr_w : shadow_lookup_instr(pc_w);
     ```
   - On `((retire_fire || trap_fire) && !freeze)`:
     - Push transaction into 64-entry `ring_buffer[head_ptr]`.
     - Advance `head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;`.
   - Provide `dump_recent_retires(int count = 10)` with instruction disassembly via `step4_disasm_pkg::disasm(ring_buffer[idx].instr)`.

### 4.4 Upgrade `lsu_monitor.sv`
1. **Ports**:
   - `clk`, `rst_n`, `freeze`
   - `lsu_req`, `lsu_we`, `lsu_addr` [31:0], `lsu_wdata` [31:0], `lsu_be` [3:0], `lsu_rdata` [31:0], `lsu_stall`, `lsu_err`
   - `pc_m` [31:0] (connect to `dut.i_riscv_core.PC_M`)
   - `lsunit_m` [4:0] (connect to `dut.i_riscv_core.lsunitM`)
   - `valid_m` (connect to `dut.i_riscv_core.valid_M`)
2. **Behavior**:
   - Completion condition: `(lsu_req && !lsu_stall && !freeze)`.
   - Populate `lsu_txn_t` including decoded region, expected APB slot (`get_expected_apb_slot(lsu_addr)`), and operation (`op = rf_lsu_op_e'(lsunit_m[2:0])`).
   - Push into 64-entry `ring_buffer[head_ptr]`.
   - Provide `dump_recent_lsu(int count = 10)`.

### 4.5 Correct `soc_tb_top.sv` Instantiations
Replace lines 178–213 in `Verification/infrastructure/tb/soc_tb_top.sv` with:
```systemverilog
  // Passive Protocol & Pipeline Monitors
  fetch_monitor u_fetch_mon (
    .clk      (clk),
    .rst_n    (hard_rst_n),
    .freeze   (freeze_monitors),
    .pc_f     (dut.i_riscv_core.Fetch.PCF),
    .instr_f  (dut.i_riscv_core.Fetch.InstrF),
    .imem_en  (dut.i_riscv_core.imem_sram_en),
    .stall_f  (dut.i_riscv_core.Fetch.imem_stall | dut.i_riscv_core.StallF),
    .pc_next  (dut.i_riscv_core.Fetch.PC_next)
  );

  retire_monitor u_retire_mon (
    .clk               (clk),
    .rst_n             (hard_rst_n),
    .freeze            (freeze_monitors),
    .valid_w           (dut.i_riscv_core.valid_W),
    .exc_valid_w       (dut.i_riscv_core.exc_valid_W),
    .pc_w              (dut.i_riscv_core.PC_W),
    .rd_addr_w         (dut.i_riscv_core.RDW),
    .rd_wdata_w        (dut.i_riscv_core.ResultW),
    .reg_we_w          (dut.i_riscv_core.RegWriteW_gated),
    .trap_w            (dut.i_riscv_core.trap_commit_valid),
    .trap_is_interrupt (dut.i_riscv_core.trap_commit_is_interrupt),
    .trap_cause        (dut.i_riscv_core.trap_commit_cause),
    .is_mret_w         (dut.i_riscv_core.is_mret_W | dut.i_riscv_core.mret_commit),
    .instr_w           (32'h0) // Shadow table resolves from PC
  );

  lsu_monitor u_lsu_mon (
    .clk       (clk),
    .rst_n     (hard_rst_n),
    .freeze    (freeze_monitors),
    .lsu_req   (dut.i_riscv_core.lsu_mem_req),
    .lsu_we    (dut.i_riscv_core.lsu_mem_we),
    .lsu_addr  (dut.i_riscv_core.lsu_mem_addr),
    .lsu_wdata (dut.i_riscv_core.lsu_mem_wdata),
    .lsu_be    (dut.i_riscv_core.lsu_mem_be),
    .lsu_rdata (dut.i_riscv_core.lsu_mem_rdata),
    .lsu_stall (dut.i_riscv_core.lsu_mem_stall),
    .lsu_err   (dut.i_riscv_core.lsu_mem_err),
    .pc_m      (dut.i_riscv_core.PC_M),
    .lsunit_m  (dut.i_riscv_core.lsunitM),
    .valid_m   (dut.i_riscv_core.valid_M)
  );
```

---

## 5. Verification Method

To independently verify the implementation:

1. **Compilation Check (Vivado XSim)**:
   ```powershell
   cd "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\Verification\infrastructure"
   xvlog --sv -f soc_verification.prj
   xelab soc_tb_top -s soc_sim
   ```
   - **Pass condition**: Zero syntax errors, zero unresolved hierarchical reference errors (`dut.i_riscv_core.*`).

2. **Monitor Smoke Test**:
   ```powershell
   cd "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\Verification\infrastructure"
   .\run_rf_mon_smoke.ps1
   ```
   - **Pass condition**: Output confirms `SMOKE TEST PASSED` with all checks (M1–M6, A1–A5, R1–R3, F1–F2) green.

3. **Retire & LSU Count Verification**:
   - Inspect `u_retire_mon.total_retired_instr > 0` on stage 1 test (`CMD_PASS`).
   - Trigger freeze via `failure_reporter.report_failure` and verify `u_retire_mon.dump_recent_retires(10)` outputs the last 10 instructions with accurate disassembly matching the compiled firmware assembly listing.
