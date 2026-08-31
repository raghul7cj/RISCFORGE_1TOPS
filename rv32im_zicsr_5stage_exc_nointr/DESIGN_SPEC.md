# RISCFORGE RV32IM_Zicsr — Core Design Specification & Parameters

## 1. Overview

5-stage in-order RISC-V CPU core (RV32IM + Zicsr).  
Active-low reset (`rst=0` = reset). PC boots to `0x80000000`.

| Feature | Status |
|---|---|
| RV32I Base ISA | Validated |
| M-Ext (Mul: 3-cycle Booth-Dadda, Div: 32-cycle non-restoring) | Validated |
| Zicsr (Machine-mode CSRs) | Validated |
| Precise traps (ecall, ebreak, illegal_instr, misaligned, access-fault) | Validated |
| Interrupts | Stubbed (CLIC dummy, timer_intr=1, ext_intr=0, msft_intr=0) |
| Load/Store unit | Validated (standalone TB) |

---

## 2. Pipeline Architecture

```
 IF  ──▶ ID  ──▶ EX  ──▶ MEM ──▶ WB
 │         │        │         │
 ├─imem    ├─rf     ├─alu     ├─ls_unit
 │         ├─ctrl   ├─m_ext   ├─hmif
 │         ├─imm    ├─jb      ├─dmem
 │         │        │         │
 └── hazard_unit (forwarding + stall/flush) ──┘
```

### 2.1 Stage Modules & Port Lists

#### `top.v` — Top-level integration
- Inputs: `clk`, `rst`
- Output: `PCSrcE1` (debug)
- Instantiates: Fetch → Decode → Execute → Memory → Writeback → wb_trap_mret_commit_controller → csr_regfile → hazard_unit

#### `fetch_cycle.v` — IF stage + IF/ID pipeline reg
- Inputs: `clk, rst, PCSrcE, wb_trap_redirect, StallF, StallD, FlushD, PCTargetE[31:0], trap_target[31:0]`
- Outputs: `InstrD[31:0], PCD[31:0], PCPlus4D[31:0], valid_D, exc_valid_D, exc_cause_D[4:0], exc_tval_D[31:0], exc_pc_D[31:0], imem_stall`
- Submodules: `PC`, `PC_Adder`, `imem_controller`, `Instruction_Memory_new`
- Exception: misaligned PC (cause=0) detected on `PC_next[1:0]!=00`

#### `decode_cycle.v` — ID stage + ID/EX pipeline reg
- Inputs: `clk, rst, FlushE, StallE, RegWriteW, RDW[4:0], ResultW[31:0], InstrD[31:0], PCD[31:0], PCPlus4D[31:0], valid_D, exc_*_D`
- Outputs: `RegWriteE, ALUSrcE, MemWriteE, ResultSrcE[1:0], JumpE[1:0], lsunitE[4:0], ALUControlE[3:0], BranchE[3:0], RD1_E[31:0], RD2_E[31:0], Imm_Ext_E[31:0], RD_E[4:0], RS1_E[4:0], RS2_E[4:0], PCE[31:0], PCPlus4E[31:0], LUISrcE, isLUIE, illegal_instr, csr_valid_E, csr_imm_mode_E, csr_op_E[1:0], csr_raddr_E[11:0], rd_index_E[4:0], is_mret_E, valid_E, exc_*_E, is_M_instruction_E, op_E[2:0]`
- Submodules: `Control_Unit_Top` (→ `Main_Decoder` + `ALU_Decoder` + `opcode_check`), `Register_File`, `Sign_Extend`
- Exceptions detected: illegal_instr (cause=2), ecall (cause=11), ebreak (cause=3)

#### `execute_cycle.v` — EX stage + EX/MEM pipeline reg
- Inputs: `clk, rst_n, FlushM, FlushE, StallM, RegWriteE, ALUSrcE, MemWriteE, LUISrcE, isLUIE, ResultSrcE[1:0], BranchE[3:0], ALUControlE[3:0], lsunitE[4:0], JumpE[1:0], RD1_E[31:0], RD2_E[31:0], Imm_Ext_E[31:0], RD_E[4:0], PCE[31:0], PCPlus4E[31:0], valid_E, exc_*_E, is_mret_E, ResultW[31:0], ForwardA_E[1:0], ForwardB_E[1:0], csr_*_E, csr_rs1_uimm_E[4:0], csr_addr_E[11:0], csr_rdata_i[31:0], is_M_instruction_E, op_E[2:0], StallM`
- Outputs: `PCSrcE, PCTargetE[31:0], csr_raddr_o[11:0], RegWriteM, MemWriteM, ResultSrcM[1:0], RD_M[4:0], PC_M[31:0], PCPlus4M[31:0], WriteDataM[31:0], ALU_ResultM[31:0], lsunitM[4:0], valid_M, exc_*_M, is_mret_M, csr_write_en_M, csr_addr_M[11:0], new_csr_M[31:0], old_csr_M[31:0], stallMUL`
- Submodules: `Mux_3_by_1` (×2 forwarding), `Mux2` (ALUSrc), `ALU`, `PC_Adder` (branch adder), `JB_unit`, `rv32m_unit` (→ `rv32m_mul` + `rv32m_div`)
- Exceptions: misaligned branch/jump target (cause=0)


#### `memory_cycle.v` — MEM stage + MEM/WB pipeline reg
- Inputs: `clk, rst, FlushW, RegWriteM, MemWriteM, ResultSrcM[1:0], RD_M[4:0], lsunitM[4:0], PC_M[31:0], PCPlus4M[31:0], valid_M, exc_*_M, is_mret_M, WriteDataM[31:0], ALU_ResultM[31:0], csr_write_en_M, csr_addr_M[11:0], new_csr_M[31:0], old_csr_M[31:0]`
- AXI4-Lite master ports: `m_axi_{awaddr,awvalid,awready,wdata,wstrb,wvalid,wready,bresp,bvalid,bready,araddr,arvalid,arready,rdata,rresp,rvalid,rready}`
- Outputs: `mem_stall_out, RegWriteW, ResultSrcW[1:0], RD_W[4:0], PC_W[31:0], PCPlus4W[31:0], ALU_ResultW[31:0], ReadDataW[31:0], valid_W, exc_*_W, is_mret_W, csr_write_en_W, csr_addr_W[11:0], new_csr_W[31:0], old_csr_W[31:0]`
- Submodules: `ls_unit`, `hybrid_mem_interface`, `Data_Memory`
- Exceptions: misaligned load (cause=4), misaligned store (cause=6), load access fault (cause=5), store access fault (cause=7)


#### `writeback_cycle.v` — WB stage (combinational mux)
- Inputs: `ResultSrcW[1:0], PCPlus4W[31:0], ALU_ResultW[31:0], ReadDataW[31:0], old_csr_W[31:0]`
- Output: `ResultW[31:0]`
- Mux: `00=ALU_ResultW, 01=ReadDataW, 10=PCPlus4W, 11=old_csr_W`

### 2.2 Support Modules

#### `hazard_unit.v`
- Forwarding: MEM→EX (priority 1), WB→EX (priority 2)
- Stall sources: load-use (lwstall), CSR-to-CSR (csr_stall), CSR-use-GPR (csr_gpr_stall), M-extension (stallMUL), mem stall (mem_stall_i)
- Flush sources: PCSrcE, exc_inflight, wb_redirect, flush_pipeline_onehot, stallMUL, lwstall, csr_stall, csr_gpr_stall
- WB redirect overrides all stalls (StallF/D/E/M=0 when wb_redirect=1)

#### `csr_regfile.v` (parameter XLEN=32)
- Machine-mode CSRs: `mstatus (0x300)`, `mie (0x304)`, `mtvec (0x305)`, `mscratch (0x340)`, `mepc (0x341)`, `mcause (0x342)`, `mtval (0x343)`, `mip (0x344)`
- Performance counters: `mcycle (0xB00)`, `minstret (0xB02)`, `mcycleh (0xB80)`, `minstreth (0xB82)`
- Port A: combinational read. Port B: sync write (normal CSR instr). Port C: sync write (trap/mret, priority over B)
- mstatus WARL mask: `0x188A` (bits: sie[1], mie[3], mpie[7], mpp[12:11])
- Counter increments: mcycle every cycle, minstret on `valid_W & ~exc_valid_W`
- Interrupt pending (`mip`): `msip_r` stored, MTIP=`timer_intr_i` (1'b1), MEIP=`ext_intr_i` (1'b0)

#### `wb_trap_mret_commit_controller.v`
- Trap commit: `valid_W & exc_valid_W` → redirect to `mtvec`, flush pipeline, write mepc/mcause/mtval
- MRET commit: `valid_W & is_mret_W & ~exc_valid_W` → redirect to `mepc`, flush pipeline, restore mstatus
- Interrupt commit: `valid_W & irq_valid_i & ~exc_valid_W & ~is_mret_W` (irq_valid_i tied to 0)

#### `imem_controller.v`
- SRAM address: `stall_in ? PC[31:2] : PC_next[31:2]`
- spec_tag: registered `instruction_is_branch`, gates wrong-path data to NOP for 1 drain cycle
- Branch penalty: 2 cycles

### 2.3 Utility Modules

| Module | Function |
|---|---|
| `PC.v` | PC register, resets to `0x80000000`, stalls on `StallF` |
| `PC_Adder.v` | 32-bit adder (PC+4, branch target computation) |
| `ALU.v` | 32-bit ALU: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU, JALR |
| `ALU_Decoder.v` | Decodes ALUControl from ALUOp + funct3 + funct7[5] + op[5] |
| `Main_Decoder.v` | Opcode-level decode: RegWrite, ImmSrc, ALUSrc, MemWrite, ResultSrc, Branch, Jump, ALUOp, LUISrcE, isLUIE, csr_valid |
| `Control_Unit_Top.v` | Wraps Main_Decoder + ALU_Decoder, assembles lsunit[4:0], Branch[3:0], Jump[1:0] buses |
| `opcode_check.v` | Valid opcode detection (illegal_instr = not any known opcode) |
| `Sign_Extend.v` | I/S/B/J/U/shift immediate generation |
| `JB_unit.v` | Branch condition evaluation: BEQ, BNE, BLT, BGE, BLTU, BGEU |
| `Register_File.v` | 32×32, async read, sync write, x0=0, same-cycle write forwarding |
| `Mux_3_by_1.v` | 3:1 32-bit mux (forwarding mux) |
| `Mux2.v` | 2:1 32-bit mux |
| `rv32m_mul.v` | Booth-encoded Dadda multiplier, 3-cycle |
| `rv32m_div.v` | Non-restoring divider, 32-cycle |
| `rv32m_unit.v` | Wraps mul+div, stall arbitration (mul: 2 extra cycles, div: variable) |
| `booth_enc.v` | Booth encoding for multiplier |
| `csa.v` | Carry-save adder for multiplier |
| `pp_gen.v` | Partial product generation for multiplier |

---

## 3. Memory System

### 3.1 Instruction Memory
| Parameter | Simulation | Synthesis |
|---|---|---|
| Size | 4 MB (1M × 32) | 16 KB (4K × 32) |
| Base | `0x80000000` | `0x80000000` |
| Read latency | 1 cycle (registered addr) | same |
| Init | `$readmemh("imem.hex")` | — |

### 3.2 Data Memory
| Parameter | Simulation | Synthesis |
|---|---|---|
| Size | 4 MB (1M × 32) | 16 KB (4K × 32) |
| Base (after subtract) | `0x80001000` → word addr `0x20000400` | same |
| Read latency | 1 cycle (registered addr + registered enables) | same |
| Init | `$readmemh("dmem.hex")` | — |


### 3.3 Hybrid Memory Interface (`hybrid_mem_interface.v`)
- Address decode:
  - `0x8000_0000 – 0x8040_0000` → native SRAM (DMEM)
  - `0x4000_0000 – 0x4000_FFFF` → AXI4-Lite bus
  - Else → `mem_err=1` (access fault)
- SRAM read FSM: IDLE → WAIT → READY → IDLE (2-cycle total, stall=1 during IDLE+WAIT)
- SRAM writes: 1 cycle, no stall
- AXI write FSM: IDLE → WAIT_ADDR/WAIT_DATA → WAIT_RESP → IDLE (variable cycles)
- AXI read FSM: IDLE → WAIT_READ → IDLE (variable cycles)

---

## 4. Parameters

| Parameter | Value | Description |
|---|---|---|
| XLEN | 32 | RISC-V data width |
| SRAM_BASE | `0x8000_0000` | DMEM base address |
| SRAM_LIMIT | `0x8040_0000` | DMEM end address |
| MMIO_BASE | `0x4000_0000` | AXI-Lite peripheral base |
| MMIO_LIMIT | `0x4000_FFFF` | AXI-Lite peripheral end |
| DMEM_BASE (word) | `0x2000_0000` | DMEM base after `>>2` (actual `0x8000_1000>>2`) |
| IMEM_BASE (word) | `0x2000_0000` | IMEM base after `>>2` (`0x8000_0000>>2`) |
| mstatus WARL mask | `0x0000188A` | SAIL-verified WARL mask |
| PC reset value | `0x8000_0000` | Boot address |
| NOP encoding | `0x00000013` | ADDI x0, x0, 0 |
| Branch penalty | 2 cycles | Speculative drain + refetch |
| DMEM read latency | 1 cycle | Native SRAM (extra cycle in hmif = 2 total) |


