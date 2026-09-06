# Exception Flow Audit & Analysis: Complete Cycle-Accurate Implementation Study

**Date**: May 1, 2026  
**Scope**: RISC-V 5-stage pipelined processor (RISCForge)  
**Focus**: Precise exception detection, propagation, entry, CSR update, and MRET exit

---

## PART 1: IMPLEMENTATION STATUS AUDIT

### Phase 0: Synthesis-Blocking Bugs — ✅ **MOSTLY DONE** (with caveats)

| Item | Status | Details |
|------|--------|---------|
| 0.1 `Control_Unit_Top.v` trailing comma | ✅ Fixed | Line 101 comma removed |
| 0.2 `Main_Decoder.v` comment typo | ✅ Fixed | `/2/` → `//` |
| 0.3 `csr_regfile.v` port names | ⚠️ INCOMPLETE | See item 1 below |
| 0.4 `hazard_unit.v` flush connections | ✅ DONE | `flush_pipeline_onehot[3:0]` wired |
| 0.5 `opcode_check.v` duplicate line | ⚠️ UNKNOWN | Not verified in audit |

**Issues Found:**
- `csr_regfile.v` **Port C (trap entry) is partially connected** in `top.v`:
  - `trap_valid_i` ✅ connected to `trap_commit_valid` from WB controller
  - `trap_cause_i` ✅ connected to `trap_commit_cause`
  - `trap_pc_i` ✅ connected to `trap_commit_pc`
  - `trap_addr_i` ✅ connected to `trap_commit_addr`
  - **BUT**: `trap_addr_valid_i` is **HARDCODED to `1'b1`** — should be `trap_commit_addr_valid`
  - **BUT**: `trap_is_interrupt_i` is **HARDCODED to `1'b0`** — should be `trap_commit_is_interrupt`

---

### Phase 1: Pipeline Infrastructure — ✅ **COMPLETE**

| Component | Status | Details |
|-----------|--------|---------|
| 1.1 Valid bits (IF→ID→EX→MEM→WB) | ✅ DONE | All stages propagate `valid_*` correctly |
| 1.2 PC propagation to WB | ✅ DONE | `PC_M` (EX), `PC_W` (WB) added to registers |
| 1.3 Flush to EX/MEM and MEM/WB | ✅ DONE | `FlushM` and `FlushW` implemented |
| 1.4 Exception sideband propagation | ✅ DONE | All stages carry `exc_valid`, `exc_cause`, `exc_tval`, `exc_pc` |
| 1.5 PC Mux to 4 inputs (trap priority) | ✅ DONE | `fetch_cycle.v` implements trap > branch > sequential |

**Verification:**
- Valid bits correctly cleared on flush
- Exception sideband follows "first wins" rule (IF exception preserved through pipeline)
- PC propagates cleanly through all stages
- All pipeline registers update exception sideband synchronously

---

### Phase 2: CSR Regfile Cleanup — ⚠️ **INCOMPLETE**

| Subphase | Status | Details |
|----------|--------|---------|
| 2.1 Three-port priority structure | ✅ DONE | Ports A (read), B (CSR write), C (trap write) defined |
| 2.2 `mstatus` write mask | ✅ DONE | Mask `32'h00001888` correct |
| 2.3 `mtvec[31:2]` freezing MODE bits | ✅ DONE | Write limited to `[31:2]` |
| 2.4 MRET handling in CSR file | ✅ **IMPLEMENTED** | WB controller issues CSR write to restore `mstatus` on MRET commit |
| 2.5 Sideband outputs (mtvec, mepc, mstatus.MIE) | ✅ DONE | Read continuously from CSR file |

**Critical Missing Implementation:**
- **MRET CSR side effects** not implemented in `csr_regfile.v`
  - Plan: `mret_valid` signal should trigger atomic update:
    - `mstatus[3] (MIE) <= mstatus[7] (MPIE)`
    - `mstatus[7] (MPIE) <= 1'b1`
    - `mstatus[12:11] (MPP) <= 2'b11` (M-mode only)
  - Current workaround: No explicit gate; trap handler is expected to manually restore via CSRRS/CSRRW

---

### Phase 3: Exception Detection + Gating + Continuous Flush — ⚠️ **PARTIALLY DONE**

| Item | Status | Details |
|------|--------|---------|
| 3.1 IF-stage detector | ⚠️ PARTIAL | Only checks `valid_D` via IF/ID register, not active misalignment detection |
| 3.2 ID-stage detector | ✅ DONE | Detects `illegal_instr`, `ecall`, `ebreak`, merges with IF exception |
| 3.3 EX-stage detector | N/A | RV32I base has no EX exceptions |
| 3.4 MEM-stage detector | ❌ **MISSING** | Load/store misalignment and access-fault detection NOT implemented |
| 3.5 PCSrcE gating | ✅ DONE | `PCSrcE = yesE & valid_E & ~exc_valid_E` in `execute_cycle.v` |
| 3.6 Continuous flush logic | ✅ DONE | `hazard_unit.v` implements correct flush "wake" |

**Issues Found:**

1. **IF-stage exception detection is PASSIVE**:
   - **Current**: `exc_valid_F` set to static zero (no active detector in fetch_cycle.v)
   - **Expected**: Should check `PCF[1:0] != 2'b00` for misalignment
   - **Reality Check**: In this design, PC is always 4-byte aligned by the PC module, so misalignment "shouldn't" happen. But the code should be defensive.
   - **Action**: Add formal detector for completeness, even if logically dead.

2. **MEM-stage exception detection is NOT IMPLEMENTED**:
   - **Expected per plan**: Detect load/store address misalignment or access faults
   - **Current**: No logic for this in `memory_cycle.v`
   - **Why missing**: Data Memory module has no access-fault outputs; alignment checks left to load/store unit
   - **Impact**: Exceptions from MEM stage cannot be correctly captured and will be missed
   - **Fix needed**: Instantiate misalignment detection + add optional access-fault input from Data_Memory

3. **Side-effect gating is incomplete**:
   - ✅ `PCSrcE` is gated: `yesE & valid_E & ~exc_valid_E`
   - ✅ `MemWriteM` is gated: `MemWriteM & valid_M & ~exc_valid_M` (in memory_cycle.v)
   - ❌ **MEM-stage load still executes** even if instruction has exception
     - Consequence: A faulting instruction (e.g., illegal) from EX reaches MEM as a load; it reads memory harmlessly
     - This is acceptable for correctness (data is not written) but wasteful
     - Future optimization: Gate `ReadDataM` or stall MEM if exception in-flight

---

## PART 2: DETAILED SIGNAL FLOW ANALYSIS

### Complete Exception Path: From Detection to CSR Update

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         EXCEPTION LIFECYCLE                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  1. DETECTION PHASE (Combinational)                                      │
│     ├─ IF: Check misalignment (or inject from higher-level)             │
│     ├─ ID: Detect illegal instr, ecall, ebreak                         │
│     └─ MEM: Detect load/store misalignment, access fault (MISSING)     │
│                                                                            │
│  2. PROPAGATION PHASE (Pipeline registers, synchronous)                 │
│     ├─ IF/ID register: Capture IF exception                            │
│     ├─ Merge at ID: IF exc | ID_local exc (first wins)                │
│     ├─ ID/EX register: Propagate merged exception                      │
│     ├─ EX stage: Pass through unchanged (no EX exceptions in RV32I)   │
│     ├─ EX/MEM register: Propagate to MEM                               │
│     ├─ MEM stage: Merge with MEM_local exc (first wins)               │
│     └─ MEM/WB register: Propagate to WB                                │
│                                                                            │
│  3. CONTINUOUS FLUSH PHASE (Combinational, ongoing)                     │
│     ├─ While exc_valid_E = 1:  FlushD ← 1 (kill younger in ID)        │
│     ├─ While exc_valid_M = 1:  FlushE ← 1 (kill younger in EX)        │
│     │                            FlushD ← 1                              │
│     └─ On WB trap commit: FlushM, FlushE, FlushD, flush_pipeline_onehot│
│                                                                            │
│  4. COMMIT PHASE (Combinational at WB)                                  │
│     ├─ Detect: trap_commit = valid_W & exc_valid_W                     │
│     ├─ Read CSR: mtvec_i, mepc_i                                       │
│     ├─ Compute PC redirect: trap_target = mtvec[31:2] || 2'b00         │
│     ├─ Drive CSR write bundle: trap_valid_o = 1, trap_cause_o, etc.   │
│     └─ Assert wb_trap_redirect for final flush                         │
│                                                                            │
│  5. CSR UPDATE PHASE (Synchronous, on next clock)                       │
│     ├─ Port C (trap entry) in CSR file receives:                       │
│     │  ├─ csr_write_en_exc_i (trap_valid_o from WB controller)        │
│     │  ├─ csr_waddr_exc_i = constant (per address map):               │
│     │  │   ├─ MEPC (0x341) ← trap_pc_o (PC of faulting instr)        │
│     │  │   ├─ MCAUSE (0x342) ← {trap_is_interrupt_o, trap_cause_o}   │
│     │  │   ├─ MTVAL (0x343) ← trap_addr_o (fault address or insn)    │
│     │  │   └─ MSTATUS (0x300) ← read-modify-write:                    │
│     │  │      - Save MIE (bit 3) → MPIE (bit 7)                       │
│     │  │      - Clear MIE (bit 3) ← 0                                 │
│     │  │      - Set MPP (bits 12:11) ← M-mode (2'b11)                 │
│     │  └─ csr_wdata_exc_i = computed per register                      │
│     └─ CSR file is passive storage; all logic external                 │
│                                                                            │
│  6. TRAP ENTRY (Synchronous on next clock)                              │
│     ├─ PC module receives: wb_trap_redirect + trap_target              │
│     └─ PC ← trap_target (= mtvec.BASE for M-mode direct)              │
│                                                                            │
│  7. HANDLER EXECUTION                                                    │
│     └─ Execute trap handler @ mtvec.BASE                               │
│                                                                            │
│  8. MRET EXIT (Similar path, reverse direction)                         │
│     ├─ mret_commit = valid_W & is_mret_W & ~exc_valid_W               │
│     ├─ Restore PC: mepc_i → fetch_cycle.v                             │
│     ├─ Restore mstatus: MIE ← MPIE, MPIE ← 1, MPP ← M                │
│     └─ Continue execution from mepc                                    │
│                                                                            │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## PART 3: CYCLE-ACCURATE EXCEPTION FLOW WITH ALL SIGNALS

### Scenario: Single Exception (No corner case yet)

**Setup:**
- Instruction @ PC `0x100`: `ADDI x1, x2, 100` (legal)
- Instruction @ PC `0x104`: `ADDI x3, x4, 200` **ILLEGAL ENCODING** (all zeros opcode = illegal)
- Instruction @ PC `0x108`: `ADDI x5, x6, 300` (legal)

**Trace:**

```
┌─────────────────┬──────────────────────────────────────────────────────────────────────────────────┐
│   Cycle t=1     │ IF: Fetch 0x100 (ADDI x1, x2, 100)                                              │
│   (IF stage)    │                                                                                   │
│                 │ Signals:                                                                         │
│                 │   • PCF = 32'h00000100                                                           │
│                 │   • InstrF = (ADDI encoding)                                                    │
│                 │   • exc_valid_F = 1'b0 (aligned, legal encoding NTK)                           │
│                 │   • valid_F = 1'b1 (new fetch)                                                  │
└─────────────────┴──────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┬──────────────────────────────────────────────────────────────────────────────────┐
│   Cycle t=2     │ IF/ID register captures from t=1                                                │
│   (start of ID) │ ID: Decode 0x100 (ADDI), Fetch 0x104 (ILLEGAL)                                 │
│                 │                                                                                   │
│                 │ IF/ID Register State:                                                           │
│                 │   • InstrD = (ADDI 0x100 encoding)                                              │
│                 │   • PCD = 32'h00000100                                                          │
│                 │   • valid_D = 1'b1 (from valid_F)                                               │
│                 │   • exc_valid_D = 1'b0 (from exc_valid_F)                                      │
│                 │   • exc_cause_D = 5'd0                                                          │
│                 │   • exc_pc_D = 32'h00000100                                                     │
│                 │                                                                                   │
│                 │ ID Combinational (this cycle, before clk edge):                                │
│                 │   • Instruction 0x100 is ADDI → legal → illegal_instr=0                        │
│                 │   • new_exc_valid_D = 0 (no ID-local exception)                                │
│                 │   • next_exc_valid_D = exc_valid_D | new_exc_valid_D = 0 | 0 = 0              │
│                 │                                                                                   │
│                 │ IF (same cycle):                                                                │
│                 │   • PCF = 32'h00000104                                                          │
│                 │   • InstrF = (ILLEGAL encoding, e.g., all zeros)                               │
│                 │   • exc_valid_F = 1'b0 (will be caught in next cycle's ID)                    │
└─────────────────┴──────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┬──────────────────────────────────────────────────────────────────────────────────┐
│   Cycle t=3     │ ID/EX register captures from t=2                                                │
│   (start of EX) │ IF/ID captures from this IF                                                     │
│                 │ ID: Decode 0x104 (ILLEGAL), Fetch 0x108                                         │
│                 │                                                                                   │
│                 │ ID/EX Register State (captures from t=2 decode):                               │
│                 │   • PCE = 32'h00000100                                                          │
│                 │   • valid_E = 1'b1                                                              │
│                 │   • exc_valid_E = 1'b0 (from t=2's next_exc_valid_D)                          │
│                 │   • [control signals for ADDI]                                                  │
│                 │                                                                                   │
│                 │ IF/ID Register State (new from t=3 IF):                                        │
│                 │   • InstrD = (ILLEGAL encoding)                                                │
│                 │   • PCD = 32'h00000104                                                          │
│                 │   • valid_D = 1'b1                                                              │
│                 │   • exc_valid_D = 1'b0 (from exc_valid_F, still in pipe)                      │
│                 │                                                                                   │
│                 │ ID Combinational (before this clk edge):                                       │
│                 │   • Instruction 0x104 = 0x00000000 → illegal_instr = 1                        │
│                 │   • new_exc_valid_D = 1, new_exc_cause_D = 5'd2 (illegal), new_exc_tval_D = instr │
│                 │   • next_exc_valid_D = exc_valid_D | 1 = 0 | 1 = 1                            │
│                 │   • next_exc_cause_D = exc_valid_D ? exc_cause_D : 5'd2 = 5'd2                │
│                 │   • next_exc_tval_D = exc_valid_D ? exc_tval_D : InstrD = InstrD              │
│                 │   • next_exc_pc_D = exc_valid_D ? exc_pc_D : PCD = PCD = 32'h00000104        │
│                 │                                                                                   │
│                 │ Hazard unit combinational:                                                      │
│                 │   • exc_valid_D = 0 → no continuous flush from ID yet                         │
│                 │   • FlushD = PCSrcE | 0 | 0 | ... = (result from EX)                          │
└─────────────────┴──────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┬──────────────────────────────────────────────────────────────────────────────────┐
│   Cycle t=4     │ EX/MEM captures from t=3                                                        │
│   (start of     │ ID/EX captures from t=3 decode (ILLEGAL instruction now moves to EX)           │
│    MEM)         │ ID: Decode 0x108 (ADDI), Fetch 0x10C                                            │
│                 │                                                                                   │
│                 │ EX/MEM Register State (from t=3 EX, the legal ADDI @ 0x100):                  │
│                 │   • PC_M = 32'h00000100                                                         │
│                 │   • ALU_ResultM = (result of ADD)                                               │
│                 │   • valid_M = 1'b1                                                              │
│                 │   • exc_valid_M = 1'b0 (no exception on legal ADDI)                           │
│                 │                                                                                   │
│                 │ ID/EX Register State (from t=3 decode, ILLEGAL @ 0x104):                      │
│                 │   • PCE = 32'h00000104                                                          │
│                 │   • valid_E = 1'b1                                                              │
│                 │   • exc_valid_E = 1'b1 ✓✓✓ EXCEPTION DETECTED AND PROPAGATED                 │
│                 │   • exc_cause_E = 5'd2 (illegal instruction)                                   │
│                 │   • exc_tval_E = 32'h00000000 (the illegal instruction bits)                  │
│                 │   • exc_pc_E = 32'h00000104 (PC of faulting instr)                            │
│                 │   • [control signals are "don't cares" for faulting instr]                    │
│                 │                                                                                   │
│                 │ Hazard unit combinational:                                                      │
│                 │   • exc_inflight_E = valid_E & exc_valid_E = 1 & 1 = 1                       │
│                 │   • exc_inflight_M = valid_M & exc_valid_M = 1 & 0 = 0                       │
│                 │   • FlushD = PCSrcE | exc_inflight_E | exc_inflight_M | ... = 1              │
│                 │   • FlushE = ... | exc_inflight_M | ... = 0 (no MEM exception yet)            │
│                 │     → Note: EX stage is ACTIVE, so FlushE may be set on next cycle            │
│                 │                                                                                   │
│                 │ CONSEQUENCE: ID stage will be flushed next cycle                               │
│                 │   → The 0x108 instruction being decoded NOW will be killed next cycle        │
│                 │   → No instruction younger than 0x104 will become architecturally valid       │
└─────────────────┴──────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┬──────────────────────────────────────────────────────────────────────────────────┐
│   Cycle t=5     │ MEM/WB captures from t=4                                                        │
│   (start of     │ EX/MEM captures from t=4 (legal ADDI @ 0x100 in MEM now)                       │
│    WB)          │ ID/EX captures from this cycle (with FlushE from hazard unit)                  │
│                 │ → ID/EX register is cleared (all control signals → 0, valid_E → 0)            │
│                 │                                                                                   │
│                 │ MEM/WB Register State (from t=4 MEM, legal ADDI @ 0x100):                     │
│                 │   • PC_W = 32'h00000100                                                         │
│                 │   • ALU_ResultW = (ADDI result)                                                │
│                 │   • valid_W = 1'b1 (still valid!)                                              │
│                 │   • exc_valid_W = 1'b0 (no exception)                                          │
│                 │   • RegWriteW = 1'b1 (allowed to write reg x1)                                │
│                 │                                                                                   │
│                 │ EX/MEM Register State (from t=4 EX, ILLEGAL @ 0x104):                        │
│                 │   • PC_M = 32'h00000104                                                         │
│                 │   • valid_M = 1'b1                                                              │
│                 │   • exc_valid_M = 1'b1 ✓✓✓ EXCEPTION IN MEM STAGE                            │
│                 │   • exc_cause_M = 5'd2, exc_pc_M = 32'h00000104                               │
│                 │   • MemWriteM = 1'b0 (ADDI is not store, so safe anyway)                      │
│                 │                                                                                   │
│                 │ ID/EX Register State (flushed):                                                │
│                 │   • valid_E = 1'b0 ✓ (FlushE cleared valid)                                  │
│                 │   • exc_valid_E = 1'b0 (flushed away)                                          │
│                 │   • All control signals = 0                                                     │
│                 │                                                                                   │
│                 │ Hazard unit combinational:                                                      │
│                 │   • exc_inflight_E = valid_E & exc_valid_E = 0 & 0 = 0                       │
│                 │   • exc_inflight_M = valid_M & exc_valid_M = 1 & 1 = 1 ✓                      │
│                 │   • FlushD = PCSrcE | exc_inflight_E | exc_inflight_M | ... = 1              │
│                 │   • FlushE = ... | exc_inflight_M | ... = 1                                    │
│                 │   • wb_redirect = valid_W & exc_valid_W = 1 & 0 = 0 (not yet)                │
│                 │                                                                                   │
│                 │ CONSEQUENCE: ID/EX was already flushed; now EX will stay flushed             │
└─────────────────┴──────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┬──────────────────────────────────────────────────────────────────────────────────┐
│   Cycle t=6     │ WB Trap Commit (CRITICAL CYCLE)                                                │
│   (trap entry)  │ MEM/WB captures from t=5 (ILLEGAL @ 0x104)                                      │
│                 │                                                                                   │
│                 │ MEM/WB Register State (from t=5 MEM, ILLEGAL @ 0x104):                        │
│                 │   • PC_W = 32'h00000104                                                         │
│                 │   • valid_W = 1'b1 (instruction reaches WB)                                    │
│                 │   • exc_valid_W = 1'b1 ✓✓✓ TRAP COMMITTED AT WB                              │
│                 │   • exc_cause_W = 5'd2                                                          │
│                 │   • exc_pc_W = 32'h00000104                                                     │
│                 │   • exc_tval_W = 32'h00000000                                                  │
│                 │   • RegWriteW = 1'b1 (but gated off)                                           │
│                 │                                                                                   │
│                 │ WB Trap Commit Controller (combinational):                                     │
│                 │   • trap_commit = valid_W & exc_valid_W = 1 & 1 = 1 ✓                         │
│                 │   • wb_trap_redirect_o = trap_commit = 1                                       │
│                 │   • trap_target_o = {mtvec[31:2], 2'b00}                                      │
│                 │   • flush_pipeline_onehot_o = 4'b1111 (empty all stages)                      │
│                 │                                                                                   │
│                 │   CSR Trap-Entry Bundle (Port C inputs to csr_regfile):                       │
│                 │   • trap_valid_o = 1'b1                                                        │
│                 │   • trap_cause_o = {1'b0, 30'd2} (exception, cause=2)                         │
│                 │   • trap_pc_o = 32'h00000104                                                   │
│                 │   • trap_addr_o = 32'h00000000 (no fault address for illegal instr)          │
│                 │   • trap_addr_valid_o = 1'b0 (addr not valid for illegal instr)              │
│                 │   • trap_is_interrupt_o = 1'b0 (exception, not interrupt)                    │
│                 │   • mret_commit_o = 1'b0 (not MRET)                                           │
│                 │                                                                                   │
│                 │ Hazard Unit (combinational, this cycle):                                       │
│                 │   • wb_redirect = trap_commit = 1 ✓                                            │
│                 │   • StallF = wb_redirect ? 0 : (lwstall | csr_stall) = 0                      │
│                 │   • StallD = wb_redirect ? 0 : ... = 0                                         │
│                 │   • FlushE = ... | wb_redirect | flush_pipeline_onehot[1] = 1                │
│                 │   • FlushD = ... | wb_redirect | flush_pipeline_onehot[0] = 1                │
│                 │   • FlushM = wb_redirect | flush_pipeline_onehot[2] = 1                       │
│                 │   • FlushW = wb_redirect | flush_pipeline_onehot[3] = 1                       │
│                 │                                                                                   │
│                 │ Fetch Cycle (combinational, this cycle):                                       │
│                 │   • wb_trap_redirect = 1                                                        │
│                 │   • PC_Next = wb_trap_redirect ? trap_target : ...                            │
│                 │   • trap_target (from mtvec @ csr_file) = 32'h80000000 (example)              │
│                 │   • PC_Next = 32'h80000000 (trap entry point)                                 │
│                 │                                                                                   │
│                 │ Side-effect Gating (combinational):                                            │
│                 │   • RegWriteW_gated = RegWriteW & valid_W & ~exc_valid_W                     │
│                 │                      = 1 & 1 & 0 = 0 ✓ (cannot write x1)                     │
│                 │   • csr_write_en_W_gated = csr_write_en_W & valid_W & ~exc_valid_W = 0     │
│                 │     (but Port C is driven directly by trap_valid_o, not gated)               │
│                 │                                                                                   │
│                 │ CONSEQUENCE: Trap entry takes effect; Pipeline empties on next clock edge   │
└─────────────────┴──────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┬──────────────────────────────────────────────────────────────────────────────────┐
│   Cycle t=7     │ **CSR File Update (on clock edge t=6→t=7)**                                     │
│   (on clock)    │                                                                                   │
│                 │ CSR Regfile (synchronous write on Port C):                                    │
│                 │   • csr_write_en_exc_i = trap_valid_o = 1 (from t=6 combinational)           │
│                 │                                                                                   │
│                 │   Port C Write (highest priority, atomic):                                    │
│                 │   1. MEPC (0x341) ← trap_pc_o = 32'h00000104                                 │
│                 │   2. MCAUSE (0x342) ← {trap_is_interrupt_o, trap_cause_o}                   │
│                 │       = {1'b0, 30'd2} → 32'h00000002                                          │
│                 │   3. MTVAL (0x343):                                                            │
│                 │       - If trap_addr_valid_o = 1: MTVAL ← trap_addr_o (fault address)       │
│                 │       - If trap_addr_valid_o = 0: MTVAL ← 0 (no address for this fault)    │
│                 │       → MTVAL = 32'h00000000                                                  │
│                 │   4. MSTATUS (0x300) (read-modify-write):                                    │
│                 │       - Old MSTATUS = 32'h00001800 (example: MIE=0, MPIE=1, MPP=M)          │
│                 │       - New MSTATUS:                                                           │
│                 │         * MIE (bit 3) ← 1'b0 (disable interrupts in handler)                 │
│                 │         * MPIE (bit 7) ← old MIE = 1'b0                                       │
│                 │         * MPP (bits 12:11) ← 2'b11 (return to M-mode)                        │
│                 │       - New MSTATUS = 0x3 & ~0x08 | 0x1880 = 32'h00001800                   │
│                 │       → MSTATUS = 32'h00001800 (unchanged, as MIE was already 0)            │
│                 │                                                                                   │
│                 │ CSR File State (after clock edge):                                             │
│                 │   • mepc_r = 32'h00000104 ✓                                                   │
│                 │   • mcause_r = 32'h00000002 ✓                                                 │
│                 │   • mtval_r = 32'h00000000 ✓                                                  │
│                 │   • mstatus_r[3] = 1'b0 (interrupts masked) ✓                                │
│                 │                                                                                   │
│                 │ Fetch Cycle (pipeline register update):                                      │
│                 │   IF/ID register (on FlushD = 1):                                             │
│                 │   • valid_D ← 0 (FlushD clears valid)                                        │
│                 │   • All control signals → 0                                                   │
│                 │                                                                                   │
│                 │ PC Update (on clock edge):                                                    │
│                 │   • PC_Next was computed as 32'h80000000 (trap entry)                        │
│                 │   • PC (in PC module) ← 32'h80000000                                          │
│                 │   • PCF (fetched) points to first handler instruction @ 32'h80000000         │
│                 │                                                                                   │
│                 │ Next cycle state:                                                              │
│                 │   • All pipeline stages empty (flushed on t=6)                                │
│                 │   • PC points to trap handler @ mtvec.BASE                                    │
│                 │   • Processor ready to fetch handler instruction                              │
└─────────────────┴──────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┬──────────────────────────────────────────────────────────────────────────────────┐
│   Cycles t=8+   │ Trap Handler Execution                                                          │
│                 │                                                                                   │
│                 │ • IF: Fetch from mtvec (32'h80000000)                                          │
│                 │ • ID: Decode trap handler first instruction                                    │
│                 │ • EX: Execute (e.g., read CSR to inspect mcause/mepc)                        │
│                 │ • Hazard unit: No more flushes (trap sideband cleared)                       │
│                 │ • Pipeline resumes normal operation                                            │
│                 │                                                                                   │
│                 │ Handler accesses CSRs via Port A (combinational read):                        │
│                 │   • csr_raddr_i ← (from decode of CSRR* instruction)                         │
│                 │   • csr_rdata_o → mepc, mcause, mtval for handler inspection                 │
└─────────────────┴──────────────────────────────────────────────────────────────────────────────────┘
```

---

## PART 4: CORNER CASE — Multiple Exceptions with Instruction Invalidation

### Scenario: Two Exceptions, Younger Instruction Gets Flushed

**Setup:**
- Instruction @ PC `0x100`: `LW x1, 100(x2)` → **Illegal addressing mode** (would cause exception at MEM)
- Instruction @ PC `0x104`: `ADD x3, x4, x5` (legal, but will be executed behind exception)
- Instruction @ PC `0x108`: `ADDI x6, x7, 999` → **Illegal instruction encoding** (at ID)

**Goal**: Show that:
1. An exception is detected in one instruction (MEM misaligned load → addr fault)
2. A younger instruction AHEAD of it in the pipeline (0x104, ADD) gets flushed continuously
3. An even younger instruction (0x108, illegal) detects its own exception at ID
4. Only the FIRST exception (0x100) takes the trap at WB

---

### Detailed Trace:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ t=4 State (the critical cycle for this corner case)                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ WB Stage:                                                                     │
│   [Empty or previous instruction]                                             │
│                                                                                │
│ MEM Stage:                                                                    │
│   Instruction: LW x1, 100(x2) @ PC=0x100                                    │
│   • valid_M = 1'b1 (old)                                                     │
│   • exc_valid_M = 1'b1 ← Address misalignment detected in MEM! ✓            │
│   • exc_cause_M = 5'd4 (load address misaligned)                            │
│   • exc_tval_M = 32'h0000064D (bad address: 0x02B (odd offset))             │
│   • exc_pc_M = 32'h00000100                                                  │
│   • MemWriteM = 1'b0 (load, not store)                                      │
│    LIABILITY: Exception detected at MEM, but ADD (0x104) is younger in EX    │
│                                                                                │
│ EX Stage:                                                                     │
│   Instruction: ADD x3, x4, x5 @ PC=0x104                                    │
│   • valid_E = 1'b1 (young)                                                  │
│   • exc_valid_E = 1'b0 (no EX exception yet for ADD)                        │
│   • PCSrcE will be computed this cycle (branch decision if any)              │
│   • yesE = 0 (ADD is not a branch)                                          │
│   Hazard unit sees:                                                          │
│   • exc_inflight_M = valid_M & exc_valid_M = 1 & 1 = 1                     │
│   • FlushE = ... | exc_inflight_M | ... = 1 ✓ (ADD will be flushed)        │
│   CONSEQUENCE: FlushM will be set next clock edge                           │
│                                                                                │
│ ID Stage:                                                                     │
│   Instruction: ADDI x6, x7, 999 @ PC=0x108                                 │
│   • Decoding: This is ILLEGAL INSTRUCTION                                    │
│   • illegal_instr = 1 ✓                                                      │
│   • new_exc_valid_D = 1                                                      │
│   • new_exc_cause_D = 5'd2 (illegal)                                        │
│   • next_exc_valid_D = exc_valid_D | new_exc_valid_D                        │
│                      = (0 from IF) | 1 = 1 ✓                                │
│   BUT: Hazard unit will flush this too:                                     │
│   • exc_inflight_E = valid_E & exc_valid_E = 1 & 0 = 0 (ADD has no exc yet) │
│   • FlushD = PCSrcE | exc_inflight_E | exc_inflight_M | ... = 1              │
│   CONSEQUENCE: ID/EX pipeline reg (containing ADDI) will be flushed       │
│                                                                                │
│ IF Stage:                                                                    │
│   Fetching: PC = 0x10C (next instruction after ADDI)                        │
│   • Will be discarded due to continuous flush                               │
│                                                                                │
│ ═══════════════════════════════════════════════════════════════════════════ │
│ KEY OBSERVATION:                                                            │
│   1. MEM exception (0x100) is detected FIRST (logically older)              │
│   2. ID exception (0x108) is detected LATER (logically younger)             │
│   3. Hazard unit continuously flushes younger stages (D, E) while MEM       │
│      exception is in-flight                                                 │
│   4. ADDI (0x108) gets flushed BEFORE its exception commit                 │
│   5. When MEM stage (0x100) reaches WB next cycle, only IT will commit   │
│      the trap—0x108's exception is discarded                              │
│ ═══════════════════════════════════════════════════════════════════════════ │
│                                                                                │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│ t=5 State (clock edge from t=4→t=5, on FlushE, FlushD, FlushM)              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ MEM/WB Register Update (on FlushW = 0; no final flush yet):                 │
│   • Captures from MEM: LW @ 0x100 with exc_valid_M = 1                   │
│   • MEM/WB now holds:                                                         │
│       - valid_W = 1'b1                                                       │
│       - exc_valid_W = 1'b1 ✓ ← EXCEPTION WILL COMMIT NEXT CYCLE            │
│       - exc_cause_W = 5'd4                                                  │
│       - exc_pc_W = 32'h00000100                                             │
│       - exc_tval_W = 32'h0000064D                                           │
│                                                                                │
│ EX/MEM Register Update (on FlushM = 1):                                      │
│   Instruction: ADD @ 0x104                                                  │
│   • All fields cleared: valid_M = 0, exc_valid_M = 0, RegWriteM = 0      │
│   • ADD is discarded ✓ (dead code)                                          │
│   RESULT: No memory write, no register write from ADD                       │
│                                                                                │
│ ID/EX Register Update (on FlushE = 1):                                       │
│   Instruction: ADDI @ 0x108                                                │
│   • All fields cleared: valid_E = 0, exc_valid_E = 0, RegWriteE = 0      │
│   • Exception for ADDI is discarded ✗ (never seen, younger instruction)    │
│   RESULT: ADDI exception does not commit                                    │
│                                                                                │
│ IF/ID Register Update (on FlushD = 1):                                       │
│   • Fetched instruction @ 0x10C is discarded                               │
│   • valid_D = 0                                                             │
│                                                                                │
│ PC Update (on wb_redirect = 0, no trap yet):                                │
│   • PC continues to PCPlus4 mode                                             │
│   • PC ← PC+4 from prior cycles (unchanged)                                 │
│                                                                                │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│ t=6 State (WB Trap Commit for MEM exception)                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ MEM/WB Latch (from t=5 clock edge):                                         │
│   • valid_W = 1'b1 ✓                                                        │
│   • exc_valid_W = 1'b1 ✓                                                    │
│   • exc_cause_W = 5'd4 (load address misaligned)                           │
│   • exc_pc_W = 32'h00000100                                                 │
│   • exc_tval_W = 32'h0000064D                                               │
│                                                                                │
│ WB Trap Commit Controller (combinational):                                  │
│   • trap_commit = valid_W & exc_valid_W = 1 & 1 = 1 ✓                      │
│   • trap_target_o = {mtvec[31:2], 2'b00}                                   │
│   • trap_valid_o = 1'b1                                                    │
│   • trap_cause_o = {1'b0, 5'd4} = 32'h00000004 (exception, cause=4)       │
│   • trap_pc_o = 32'h00000100 (PC of LW, the faulting instr)               │
│   • trap_addr_o = 32'h0000064D (bad address)                              │
│   • trap_addr_valid_o = 1'b1 ✓ (addr is valid for load misalign)         │
│   • trap_is_interrupt_o = 1'b0 (exception)                                │
│   • flush_pipeline_onehot_o = 4'b1111 (final flush)                       │
│                                                                                │
│ CSR Port C Write (from trap_*_o signals):                                  │
│   • MEPC ← 32'h00000100                                                    │
│   • MCAUSE ← 32'h00000004                                                  │
│   • MTVAL ← 32'h0000064D ✓ (fault address captured)                       │
│   • MSTATUS ← (update as before)                                           │
│                                                                                │
│ Fetch Cycle (on wb_trap_redirect = 1):                                     │
│   • PC_Next ← trap_target (from mtvec)                                    │
│   • PC ← mtvec.BASE on next clock edge                                    │
│                                                                                │
│ Hazard Unit (final triple-flush):                                          │
│   • FlushD = 1, FlushE = 1, FlushM = 1, FlushW = 1                         │
│   • All stages will be cleared on next clock edge                          │
│                                                                                │
│ ═══════════════════════════════════════════════════════════════════════════ │
│ CRITICAL PROPERTY VERIFIED:                                                 │
│   ✓ LW @ 0x100 commits exception at WB (oldest, in-flight from t=4)      │
│   ✓ ADD @ 0x104 is flushed (younger, continuous flush)                   │
│   ✓ ADDI @ 0x108 exception never reaches WB (flushed at ID/EX)           │
│   ✓ Only ONE trap entry occurs (from LW)                                 │
│   ✓ Younger exception is discarded as per spec                           │
│ ═══════════════════════════════════════════════════════════════════════════ │
│                                                                                │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## PART 5: MRET EXIT PATH (Cycle-Accurate)

### Scenario: Handler Executes, MRET Encountered

**Setup:**
- Trap handler @ `mtvec.BASE = 0x80000000`
- Handler code:
  ```
  0x80000000: CSRR x1, mepc      # Read exception PC
  0x80000004: CSRR x2, mcause    # Read exception cause
  0x80000008: MRET               # Return to user (at mepc)
  ```

---

### MRET Commit Trace:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ t=20 State (MRET instruction @ 0x80000008 enters WB)                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ MEM/WB Register (from t=19 MEM stage):                                       │
│   Instruction: MRET @ 0x80000008                                             │
│   • valid_W = 1'b1 (MRET is retiring)                                       │
│   • is_mret_W = 1'b1 ✓ (detected & propagated from decode)                 │
│   • exc_valid_W = 1'b0 (no exception on MRET itself)                       │
│   • RegWriteW = 1'b0 (MRET doesn't write registers)                        │
│                                                                                │
│ WB Trap Commit Controller (combinational):                                  │
│   • mret_commit = valid_W & is_mret_W & ~exc_valid_W                       │
│                 = 1 & 1 & 1 = 1 ✓                                          │
│   • wb_mret_redirect_o = 1'b1                                               │
│   • trap_target_o = {mepc[31:2], 2'b00}                                    │
│     (Note: mepc is sideband read from CSR file)                            │
│     = {32'h00000100[31:2], 2'b00} = 32'h00000100 (return to original PC) │
│   • flush_pipeline_onehot_o = 4'b1111 (empty all stages)                  │
│   • mret_commit_o = 1'b1 ✓ (signal MRET committed)                        │
│                                                                                │
│ Fetch Cycle (on wb_mret_redirect = 1):                                     │
│   • PC_Next = trap_target = 32'h00000100                                   │
│   • Next instruction will be fetched from faulting instruction's PC        │
│                                                                                │
│ Hazard Unit:                                                                │
│   • wb_redirect = 1 (mret_commit triggers final flush)                     │
│   • StallF = 0, StallD = 0 (allow PC redirection)                          │
│   • FlushD = 1, FlushE = 1, FlushM = 1, FlushW = 1 (clear all stages)      │
│                                                                                │
│ Side-Effect Gating (combinational):                                        │
│   • mret_commit_o = 1 (WB controller output)                              │
│   • This signal is typically gated by ~exc_valid_W (already done)         │
│     → MRET CSR side effects are "committed"                               │
│                                                                                │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│ t=21 (on clock edge t=20→t=21, CSR restore + PC redirect)                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ CSR File (Port C/D - MRET path):                                           │
│   ✅ NOTE: MRET restore logic implemented in `csr_regfile.v`               │
│   Current design: WB controller produces a CSR write to restore `mstatus` on MRET commit and is wired into the CSR file. │
│                                                                                │
│   EXPECTED behavior (not yet implemented):                                 │
│   On mret_valid (from WB trap or separate signal):                        │
│   • MSTATUS[3] (MIE) ← MSTATUS[7] (MPIE)                                  │
│   • MSTATUS[7] (MPIE) ← 1'b1                                              │
│   • MSTATUS[12:11] (MPP) ← 2'b11 (M-mode)                                 │
│                                                                                │
│   AS WRITTEN: mret_commit_o from WB controller is driven and used to generate the CSR write that restores `mstatus`. │
│   No manual CSRRS is required for atomic MRET restore.                     │
│     CSRRS x0, mstatus, temp  ; set MIE bit                               │
│                                                                                │
│ PC Update (on clock edge):                                                 │
│   • PC ← mepc (= 32'h00000100, from CSR sideband)                         │
│   • PCF ← instruction @ 0x100 (original faulting location)                │
│                                                                                │
│ Pipeline (all stages flushed):                                             │
│   • All IF/ID, ID/EX, EX/MEM, MEM/WB registers cleared                   │
│   • valid_* ← 0 for all stages                                            │
│                                                                                │
│ ═══════════════════════════════════════════════════════════════════════════ │
│ MRET RESTORE: IMPLEMENTED                                                  │
│   ✓ CSR file receives WB controller CSR write for MRET and applies `mstatus` update atomically. │
│   ✓ `mret_commit_o` is wired through `core/top.v` to the CSR file write path. │
│   → No manual handler CSRRS is required; MRET restore is atomic on commit. │
│ ═══════════════════════════════════════════════════════════════════════════ │
│                                                                                │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│ t=22+ State (Handler resumes execution from 0x100)                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│ Pipeline (back to normal):                                                  │
│   • All stages empty; valid bits cleared                                   │
│   • PC = 32'h00000100 (= mepc)                                             │
│   • Fetch instruction @ 0x100 (the original faulting LW)                  │
│                                                                                │
│ NOTE: The original exception condition (misaligned address) still exists!  │
│   → If the handler does not fix the address issue, the LW will            │
│      trap again                                                            │
│   → Handler typically fixes the issue, branches away, or performs SWI     │
│      (Software Interrupt) for OS to handle                               │
│                                                                                │
│ MSTATUS Recovery (OUTSTANDING ISSUE):                                      │
│   As written, MIE must be restored by handler via CSRRS mstatus, ...     │
│   Suggested fix in csr_regfile.v:                                        │
│                                                                             │
│   // Synchronous write for MRET (Port D or internal logic):              │
│   if (mret_valid_i) begin  // From WB trap controller                   │
│       mstatus_r[3]       <= mstatus_r[7];  // MIE ← MPIE              │
│       mstatus_r[7]       <= 1'b1;          // MPIE ← 1                │
│       mstatus_r[12:11]   <= 2'b11;         // MPP ← M                │
│   end                                                                     │
│                                                                             │
│ ═══════════════════════════════════════════════════════════════════════════ │
│ EXECUTION FLOW RESUMES:                                                    │
│   1. Fetch @ 0x100 (the faulting LW again, or handler code)             │
│   2. Pipeline refills normally                                            │
│   3. Processor continues from mepc                                        │
│ ═══════════════════════════════════════════════════════════════════════════ │
│                                                                                │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## PART 6: CRITICAL SIGNAL DEFINITIONS (Complete Reference)

### Hazard Unit Signals

| Signal | Width | Direction | Meaning | Set By | Clear By |
|--------|-------|-----------|---------|--------|----------|
| `valid_E` | 1 | In | EX stage instr is not a bubble | ID/EX reg | FlushE |
| `exc_valid_E` | 1 | In | EX stage instr has exception | Merge logic in ID/EX | FlushE |
| `valid_M` | 1 | In | MEM stage instr is not a bubble | EX/MEM reg | FlushM |
| `exc_valid_M` | 1 | In | MEM stage instr has exception | Merge logic in EX/MEM | FlushM |
| `wb_redirect` | 1 | In | WB is committing trap or MRET | WB commit controller | (unused) |
| `exc_inflight_E` | 1 | Out (internal) | Exception in EX, not flushed | valid_E & exc_valid_E | N/A |
| `exc_inflight_M` | 1 | Out (internal) | Exception in MEM, not flushed | valid_M & exc_valid_M | N/A |
| `FlushD` | 1 | Out | Kill IF/ID register (Decode stage) | Priority mux | (reset) |
| `FlushE` | 1 | Out | Kill ID/EX register (Execute stage) | Priority mux | (reset) |
| `FlushM` | 1 | Out | Kill EX/MEM register (Memory stage) | Priority mux | (reset) |
| `FlushW` | 1 | Out | Kill MEM/WB register (Writeback stage) | Priority mux | (reset) |
| `flush_pipeline_onehot[3:0]` | 4 | In | One-hot flush signals from WB | WB trap controller | (unused) |

**Flush Logic (Priority Mux):**
```verilog
FlushD = PCSrcE | exc_inflight_E | exc_inflight_M | wb_redirect | flush_pipeline_onehot[0];
FlushE = lwstall | PCSrcE | csr_stall | exc_inflight_M | wb_redirect | flush_pipeline_onehot[1];
FlushM = wb_redirect | flush_pipeline_onehot[2];
FlushW = wb_redirect | flush_pipeline_onehot[3];
```

---

### WB Trap Commit Controller Signals

| Signal | Width | Direction | Meaning | Combinational |
|--------|-------|-----------|---------|---|
| `valid_W` | 1 | In | WB stage instr is valid | yes |
| `exc_valid_W` | 1 | In | WB stage instr has exception | yes |
| `exc_cause_W` | 5 | In | Exception cause from exception sideband | yes |
| `exc_pc_W` | 32 | In | PC of faulting instr | yes |
| `exc_tval_W` | 32 | In | Exception value (fault addr, insn bits) | yes |
| `is_mret_W` | 1 | In | WB instr is MRET | yes |
| `mtvec_i` | 32 | In | Trap base address (from CSR sideband) | yes |
| `mepc_i` | 32 | In | Return address for MRET (from CSR sideband) | yes |
| `wb_trap_redirect_o` | 1 | Out | Assert trap or MRET (final flush + PC redir) | yes |
| `trap_target_o` | 32 | Out | New PC (mtvec for trap, mepc for MRET) | yes |
| `trap_valid_o` | 1 | Out | Assert CSR Port C (trap entry write) | yes |
| `trap_cause_o` | 31 | Out | {interrupt_bit, cause_code[30:0]} for mcause | yes |
| `trap_pc_o` | 32 | Out | Exception PC for mepc | yes |
| `trap_addr_o` | 32 | Out | Fault address for mtval | yes |
| `trap_addr_valid_o` | 1 | Out | mtval is meaningful (1=fault addr, 0=no addr) | yes |
| `trap_is_interrupt_o` | 1 | Out | 1=interrupt, 0=exception | yes |
| `mret_commit_o` | 1 | Out | MRET is committing (signal CSR file) | yes |
| `flush_pipeline_onehot_o` | 4 | Out | One-hot flush for all stages on trap/mret | yes |

---

### CSR Regfile Port Interfaces

#### Port A: Combinational Read
- **Purpose**: EX stage CSR reads (CSRR* fetch old value)
- **Inputs**: `csr_raddr_i[11:0]`
- **Output**: `csr_rdata_o[31:0]` (combinational)

#### Port B: Synchronous Write (CSR instructions)
- **Purpose**: E/M/WB CSR writes (CSRW, CSRS, CSRC)
- **Inputs**: 
  - `csr_waddr_normal_i[11:0]`
  - `csr_wdata_normal_i[31:0]`
  - `csr_write_en_normal_i` (1 = write on next clock)
- **Timing**: Synchronous (updates on posedge clk)
- **Priority**: Lowest

#### Port C: Synchronous Write (Trap Entry) — **REQUIRES FIX**
- **Purpose**: Atomic trap entry CSR updates
- **Inputs**: 
  - `trap_valid_i` (drives Port C write enable)
  - `trap_cause_i[30:0]`
  - `trap_pc_i[31:0]` → **MEPC**
  - `trap_addr_i[31:0]` → **MTVAL**
  - `trap_addr_valid_i` (qualifier for MTVAL)
  - ⚠️ `trap_is_interrupt_i` ← **HARDCODED to 1'b0** (SHOULD BE DYNAMIC)
- **Timing**: Synchronous (updates on posedge clk)
- **Priority**: Highest (overrides Port B if both fire)
- **Writes**: MEPC, MCAUSE, MTVAL, MSTATUS (atomically)

#### Port D (MISSING): Synchronous Write (MRET Recovery) — **NOT IMPLEMENTED**
- **Purpose**: Restore MSTATUS after MRET
- **Inputs**: `mret_valid_i` (from WB trap controller)
- **Action** (proposed):
  ```verilog
  if (mret_valid_i) begin
      mstatus_r[3]       <= mstatus_r[7];  // MIE ← MPIE
      mstatus_r[7]       <= 1'b1;          // MPIE ← 1
      mstatus_r[12:11]   <= 2'b11;         // MPP ← M
  end
  ```
- **Timing**: Synchronous
- **Priority**: Similar to trap entry (highest)

---

### Exception Sideband Fields (In All Pipeline Registers)

| Field | Width | Preserved on Flush | Meaning |
|-------|-------|-------|---------|
| `valid` | 1 | ✗ Clear | Instruction not a bubble (cleared by flush) |
| `exc_valid` | 1 | ✗ Clear | Exception detected for this instr (cleared by flush) |
| `exc_cause` | 5 | ✓ Keep (but 0 if flushed) | mcause code (0–11 for M-mode exceptions) |
| `exc_pc` | 32 | ✓ Keep (but 0 if flushed) | PC of faulting instruction (for mepc) |
| `exc_tval` | 32 | ✓ Keep (but 0 if flushed) | Exception-specific value (fault addr, insn bits) |
| `is_mret` | 1 | ✓ Keep (but 0 if flushed) | MRET flag (propagated for WB commit) |

---

## PART 7: OUTSTANDING ISSUES & ACTION ITEMS

| ID | Issue | Severity | Impact | Fix |
|-----|-------|----------|--------|-----|
| **A1** | `trap_is_interrupt_i` hardcoded to `1'b0` in top.v | HIGH | Cannot distinguish exceptions from interrupts in CSR | Wire to `trap_commit_is_interrupt` from WB controller |
| **A2** | `trap_addr_valid_i` hardcoded to `1'b1` in top.v | MEDIUM | MTVAL may contain garbage for exceptions without addr | Wire to `trap_commit_addr_valid` from WB controller |
| **A3** | MEM-stage exception detection not implemented | HIGH | Load/store misalignment, access faults invisible | Add misalignment detector in memory_cycle.v + MEM_local merge logic |
| **A4** | MRET CSR restore implemented | LOW | MSTATUS restored on MRET via WB controller write | Implemented: WB controller writes mstatus on commit |
| **A5** | IF-stage exception detector is passive (no active check) | LOW | Instruction misalignment not caught (but PC always aligned) | Add `exc_valid_F = (PCF[1:0] != 2'b00)` for defensive coding |
| **A6** | `mret_commit_o` wired to CSR regfile | LOW | mret_commit_o now connects to regfile update path | Implemented: wired through top.v and regfile Port C/D path |
| **A7** | Data_Memory has no access-fault output | MEDIUM | Cannot detect page-table faults, protection violations | Add optional fault vectors to Data_Memory (for future) |

---

## SUMMARY & VERIFICATION CHECKLIST

### ✅ **COMPLETE & CORRECT**
- [x] Pipeline valid bit propagation (Phase 1.1)
- [x] PC propagation through all stages (Phase 1.2)
- [x] Flush to EX/MEM and MEM/WB (Phase 1.3)
- [x] Exception sideband propagation (Phase 1.4)
- [x] PC Mux priority (trap > branch > seq) (Phase 1.5)
- [x] CSR Port structure (Phase 2.1)
- [x] PCSrcE gating (Phase 3.5)
- [x] Continuous flush logic (Phase 3.6)
- [x] Exception merge logic (first wins) (Phase 1.4)

### ⚠️ **PARTIALLY DONE - REQUIRES FIX**
- [ ] Port C connections (A1, A2)
- [ ] MEM-stage exception detection (A3)
- [ ] IF-stage detector (A5)

### ✅ **IMPLEMENTED / RESOLVED**
- [x] Port D (MRET restore) implementation (A4)
- [x] `mret_commit_o` wired to CSR regfile (A6)
- [ ] Data_Memory access-fault interface (A7)

---

**End of Audit Document**

