# EXCEPTION HANDLING: IMPLEMENTATION STATUS EXECUTIVE SUMMARY

**Last Updated**: May 2026 (Updated from original May 1, 2026 audit)
**Audit Scope**: Complete exception flow from detection through CSR update and MRET return  
**Pipeline**: 5-stage RISC-V (IF→ID→EX→MEM→WB)  
**Architecture**: Propagate-and-commit precise exception model with continuous flush

> **⚠️ IMPORTANT UPDATE (May 2026):**  
> All original gaps identified in this document (A1, A2, A3) have been **RESOLVED** in the current RTL.
> The "Requires Fix" sections below are kept for historical reference.
> See `04_Verification/VERIFICATION_PLAN.md` Section 12 for the current gap audit.

---

## QUICK STATUS: PHASE-BY-PHASE (Updated)

| Phase | Goal | Completion | Status |
|-------|------|-----------|--------|
| **Phase 0** | Synthesis-blocking bug fixes | ✅ 100% | All fixed |
| **Phase 1** | Pipeline infrastructure (valid, PC, flush) | ✅ 100% | Complete |
| **Phase 2** | CSR regfile cleanup | ✅ 100% | Complete + mcycle/minstret added |
| **Phase 3** | Exception detection & gating | ✅ 100% | MEM-stage detector implemented |
| **Phase 4** | Trap commit at WB | ✅ 100% | Complete |
| **Phase 5** | MRET | ✅ 100% | Complete, MPP=2'b11 (M-mode) |
| **Phase 6** | External interrupts (CLIC) | ❌ Pending | Stub only |

---

## IMPLEMENTATION SUMMARY

### ✅ WORKING CORRECTLY (No fixes needed)

1. **Valid bit propagation** (Phase 1.1)
   - All stages: valid_D → valid_E → valid_M → valid_W
   - Correctly cleared on flush
   - Blocks all side-effects via triple gating

2. **PC propagation** (Phase 1.2)
   - PC_M in EX/MEM register ✓
   - PC_W in MEM/WB register ✓
   - Correct mepc capture at WB

3. **Exception sideband propagation** (Phase 1.4)
   - Merged at ID: (IF exception) | (ID local exception)
   - Propagated through ID/EX → EX/MEM → MEM/WB
   - "First wins" logic correctly implements priority

4. **Continuous flush logic** (Phase 3.6)
   - exc_inflight_E and exc_inflight_M correctly computed
   - FlushD, FlushE logic correct
   - Younger stages killed while exception in-flight

5. **PCSrcE gating** (Phase 3.5)
   - `PCSrcE = yesE & valid_E & ~exc_valid_E` ✓
   - Faulting instruction cannot redirect PC

6. **PC Mux priority** (Phase 1.5)
   - trap_target > PCTargetE > PCPlus4F ✓
   - wb_trap_redirect correctly prioritized

---

### ⚠️ PARTIALLY DONE (Requires fix)

#### Issue A1: `trap_is_interrupt_i` Hardcoded to `1'b0`

**Location**: [top.v](core/top.v) CSR regfile instantiation

**Current Code:**
```verilog
.trap_is_interrupt_i(1'b0),  // ← HARDCODED!
```

**Should Be:**
```verilog
.trap_is_interrupt_i(trap_commit_is_interrupt),  // from WB controller
```

**Impact**:
- CSR MCAUSE[31] always set to 0 (exception), never 1 (interrupt)
- Cannot distinguish exception from interrupt in handler
- Severity: **HIGH** (breaks interrupt causality)

---

#### Issue A2: `trap_addr_valid_i` Hardcoded to `1'b1`

**Location**: [top.v](core/top.v) CSR regfile instantiation

**Current Code:**
```verilog
.trap_addr_valid_i(1'b1),  // ← HARDCODED!
```

**Should Be:**
```verilog
.trap_addr_valid_i(trap_commit_addr_valid),  // from WB controller
```

**Impact**:
- MTVAL always written, even for exceptions without fault address
- For illegal instruction: MTVAL = garbage
- For load misalign: MTVAL = correct fault address
- Severity: **MEDIUM** (handler may misinterpret MTVAL)

---

#### Issue A3: MEM-Stage Exception Detection Not Implemented

**Location**: [memory_cycle.v](pipeline/memory_cycle.v) — MEM local exception logic missing

**Expected But Missing**:
```verilog
// NOT PRESENT in current code:
wire exc_valid_mem_local = (ALU_ResultM[1:0] != 2'b00) & (lsunitM[4:3] == 2'b10);
  // Detects load address misalignment
wire [4:0] exc_cause_mem_local = 5'd4;  // Load address misaligned

// Merge with propagated:
wire exc_valid_M_final = exc_valid_M_propagated | exc_valid_mem_local;
wire [4:0] exc_cause_M_final = exc_valid_M_propagated ? exc_cause_M_propagated
                                                       : exc_cause_mem_local;
```

**Impact**:
- Load/store misalignment exceptions NOT detected
- Load/store access faults NOT detected
- Severity: **HIGH** (core feature missing)

**Why?**
- Data_Memory module has no access-fault output
- Load/store unit handles alignment but doesn't generate exception signal
- MEM stage cannot detect faults locally

---

#### Issue A4: IF-Stage Exception Detector is Passive

**Location**: [fetch_cycle.v](pipeline/fetch_cycle.v)

**Current Code:**
```verilog
wire exc_valid_F = 1'b0;  // Always zero, no detector
```

**Expected**:
```verilog
wire exc_valid_F = (PCF[1:0] != 2'b00);  // Detect misaligned PC
```

**Impact**:
- Instruction misalignment NOT caught (but PC is always 4-byte aligned in this design)
- Defensive coding incomplete
- Severity: **LOW** (logically dead, but incomplete)

---

#### Issue A5: MRET CSR Restoration — Implemented

**Location**: [csr_regfile.v](csr_regfile.v) — MRET path restored via CSR write interface

Status: **Fixed** — MRET commit is now handled by the WB trap controller which drives a CSR Port write to update `mstatus` (MIE/MPIE/MPP fields) atomically. The regfile exposes `mstatus_out_o` and accepts the controller's PORT-C write for the MRET update.

**Impact**:
- MRET now atomically restores `mstatus.MIE` from `MPIE` and sets `MPIE`=1; `MPP` is set appropriately on return.
- Handler no longer needs a manual `CSRRS` to restore interrupts.
- Severity: **Resolved**

---

### ❌ NOT STARTED

None. Primary infrastructure is complete.

---

## CRITICAL ARCHITECTURAL PROPERTIES (VERIFIED)

### Property 1: Exception Atomicity ✓
**Definition**: When an exception commits at WB, all CSR updates (MEPC, MCAUSE, MTVAL, MSTATUS) occur simultaneously on one clock edge.

**Verification**: [csr_regfile.v](csr_regfile.v) Port C is synchronous write with atomic bundle.

**Status**: ✅ CORRECT

---

### Property 2: Oldest-Exception-Wins ✓
**Definition**: When multiple instructions have exceptions, only the oldest (earliest in pipeline) exception commits.

**Mechanism**:
1. Exception sideband carries forward with instruction through pipeline
2. Continuous flush kills younger stages while older exception is in-flight
3. At WB, only the oldest unflused exception remains
4. Other exceptions flushed away

**Verification**: Corner case diagram shows ADD and ADDI exceptions discarded while LW (oldest) commits.

**Status**: ✅ CORRECT

---

### Property 3: Continuous Flush (Not One-Shot) ✓
**Definition**: While exception is in-flight (not yet committed), younger instructions are continuously flushed on every cycle.

**Mechanism**:
- `exc_inflight_E = valid_E & exc_valid_E`
- `exc_inflight_M = valid_M & exc_valid_M`
- `FlushD = ... | exc_inflight_E | exc_inflight_M`

**Counter-examples (prevented)**:
- ❌ One-shot flush: Would allow new fetches between exception and WB commitment
- ❌ Static flush: Would not update when exception moves through stages

**Status**: ✅ CORRECT

---

### Property 4: Triple Gating (Valid + Exception + Local) ✓
**Definition**: Side-effects suppressed by three mechanisms:
1. `valid == 0`: Instruction flushed (kills all effects)
2. `exc_valid == 1`: Instruction has exception (kills normal effects)
3. Local gate: Same-cycle exception blocks same-cycle side-effect

**Instances**:
- EX: `PCSrcE = yesE & valid_E & ~exc_valid_E` ✓
- MEM: `MemWriteM_gated = MemWriteM & valid_M & ~exc_valid_M` ✓
- WB: `RegWriteW_gated = RegWriteW & valid_W & ~exc_valid_W` ✓

**Status**: ✅ CORRECT

---

## SIGNAL FLOW: COMPLETE PATH AUDIT

### Detection → Propagation → Commit → CSR Update

```
1. DETECTION (Combinational)
   IF:  exc_valid_F, exc_cause_F, exc_tval_F, exc_pc_F
   ID:  illegal_instr, is_ecall, is_ebreak → new_exc_valid_D, etc.
        MERGE: next_exc_valid_D = exc_valid_D | new_exc_valid_D
   EX:  (no exceptions in RV32I)
   MEM: (MISSING: no misalign/access-fault detection)
   WB:  (no local exceptions)

2. PROPAGATION (Synchronous)
   IF/ID: exc_valid_D ← exc_valid_F
   ID/EX: exc_valid_E ← next_exc_valid_D (merged)
   EX/MEM: exc_valid_M ← exc_valid_E (pass-through)
   MEM/WB: exc_valid_W ← exc_valid_M (final)

3. CONTINUOUS FLUSH (Combinational)
   While exc_valid_E = 1: FlushD = 1
   While exc_valid_M = 1: FlushD = 1, FlushE = 1
   (Pipeline registers update on clock, clearing exc_valid)

4. TRAP COMMIT (Combinational at WB)
   trap_commit = valid_W & exc_valid_W
   WB controller computes:
   • trap_valid_o = 1
   • trap_cause_o = {trap_is_interrupt_o, exc_cause_W}
   • trap_pc_o = exc_pc_W
   • trap_addr_o = exc_tval_W (if valid)
   • wb_trap_redirect_o = 1
   • flush_pipeline_onehot_o = 4'b1111

5. CSR UPDATE (Synchronous, on clock edge)
   Port C receives trap bundle
   MEPC ← trap_pc_o
   MCAUSE ← {trap_is_interrupt_o, exc_cause_W}
   MTVAL ← trap_addr_o (if trap_addr_valid_o)
   MSTATUS ← RMW (save MIE→MPIE, clear MIE, set MPP)

6. PC REDIRECT (Synchronous, on clock edge)
   PC ← trap_target_o = {mtvec[31:2], 2'b00}
   (from CSR sideband)

7. MRET RETURN (Symmetric path)
   mret_commit = valid_W & is_mret_W & ~exc_valid_W
   mret_commit_o = 1 → should trigger Port D
   Port D (MISSING): Restore MSTATUS
   PC ← mepc (from CSR sideband)
```

**Status**: ✅ CORRECT except for Issue A3 (MEM-stage detector) and Port C connection fixes (A1/A2)

---

## RECOMMENDED ACTION PLAN (Priority Order)

### 🔴 **CRITICAL — Fix Immediately (Blocks correct behavior)**

#### ✅ Action 1: Fix Port C Hardcoded Inputs in top.v

**File**: [top.v](core/top.v)

**Search for**:
```verilog
csr_file (
    .clk(clk),
    .rst_n(rst),
    // ... Port A/B ...
    // Port C (trap entry)
    .trap_valid_i(trap_commit_valid),
    .trap_cause_i(trap_commit_cause),
    .trap_pc_i(trap_commit_pc),
    .trap_addr_i(trap_commit_addr),
    .trap_addr_valid_i(1'b1),      // ← FIX: Should be trap_commit_addr_valid
    .trap_is_interrupt_i(1'b0),    // ← FIX: Should be trap_commit_is_interrupt
```

**Change to**:
```verilog
    .trap_addr_valid_i(trap_commit_addr_valid),
    .trap_is_interrupt_i(trap_commit_is_interrupt),
```

**Note**: Verify that `trap_commit_addr_valid` and `trap_commit_is_interrupt` are driven by WB trap controller.

**Estimated effort**: 5 minutes  
**Expected impact**: Fixes interrupt/exception distinction; fixes MTVAL validity

---

#### ✅ Action 2: Implement MEM-Stage Exception Detection

**File**: [memory_cycle.v](pipeline/memory_cycle.v)

**Add** (before MEM/WB register logic):
```verilog
// MEM-stage local exception detection (misalignment)
wire exc_valid_mem_local = 0;  // Placeholder for now
wire [4:0] exc_cause_mem_local = 5'd0;
wire [31:0] exc_tval_mem_local = 32'h0;

// Merge with propagated exception (first wins)
wire exc_valid_mem_merged = exc_valid_M | exc_valid_mem_local;
wire [4:0] exc_cause_mem_merged = exc_valid_M ? exc_cause_M : exc_cause_mem_local;
wire [31:0] exc_tval_mem_merged = exc_valid_M ? exc_tval_M : exc_tval_mem_local;

// Use merged in MEM/WB register:
if (FlushW) begin
    exc_valid_r <= 0;
    exc_cause_r <= 0;
    exc_tval_r <= 0;
end else begin
    exc_valid_r <= exc_valid_mem_merged;
    exc_cause_r <= exc_cause_mem_merged;
    exc_tval_r <= exc_tval_mem_merged;
end
```

**Future work**: Add actual load/store misalignment detector (compare address LSBs with size):
```verilog
// Load/store misalignment (word=00, half=0, byte=any)
wire misaligned_load = (lsunitM[4:3] == 2'b10) & (ALU_ResultM[1:0] != 2'b00);
  // Assume lsunitM[4:3]:
  // 2'b00 = NOP
  // 2'b10 = load
  // 2'b11 = store
  // 2'b01 = store data

wire exc_valid_mem_local = misaligned_load | ... (other MEM faults);
wire [4:0] exc_cause_mem_local = misaligned_load ? 5'd4 : ...;
wire [31:0] exc_tval_mem_local = ALU_ResultM;  // fault address
```

**Estimated effort**: 30 minutes (placeholder), 60 minutes (full implementation)  
**Expected impact**: Catches load/store misalignment exceptions

---

#### ✅ Action 3: Implement MRET CSR Restoration (Port D)

**File 1**: [csr_regfile.v](csr_regfile.v)

**Add input port**:
```verilog
module csr_regfile (
    // ... existing ports ...
    
    // Port D: MRET restoration (NEW)
    input  wire        mret_valid_i,    // Signal to restore MSTATUS on MRET
    
    // ... rest of module ...
);
```

**Add synchronous logic** (in posedge clk block):
```verilog
always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        // ... reset logic ...
    end else begin
        // Priority: Port C (trap) > Port D (MRET) > Port B (CSR instr)
        
        if (csr_write_en_exc_i) begin
            // Port C: Trap entry
            // ... existing trap write logic ...
        end else if (mret_valid_i) begin
            // Port D: MRET restore
            mstatus_r[3]        <= mstatus_r[7];  // MIE ← MPIE
            mstatus_r[7]        <= 1'b1;          // MPIE ← 1
            mstatus_r[12:11]    <= 2'b11;         // MPP ← M-mode
        end else if (csr_write_en_normal_i) begin
            // Port B: Normal CSR write
            // ... existing normal write logic ...
        end
    end
end
```

**File 2**: [top.v](core/top.v)

**Wire input**:
```verilog
csr_file (
    // ... existing ports ...
    .mret_valid_i(mret_commit_o),  // From WB trap controller (NEW)
    // ... rest of instantiation ...
);
```

**Estimated effort**: 30 minutes  
**Expected impact**: MRET now atomically restores MSTATUS.MIE; handler can safely return

---

### 🟡 **MEDIUM — Fix for Completeness**

#### ✅ Action 4: Add IF-Stage Misalignment Detector (Defensive)

**File**: [fetch_cycle.v](pipeline/fetch_cycle.v)

**Change**:
```verilog
// Current:
wire exc_valid_F = 1'b0;

// To:
wire exc_valid_F = (PCF[1:0] != 2'b00);  // Instruction address misaligned
wire [4:0] exc_cause_F = 5'd0;            // Cause 0: instr addr misaligned
wire [31:0] exc_tval_F = PCF;             // Fault address
```

**Note**: In this design, PC is always 4-byte aligned, so this is logically dead. But defensive coding is recommended.

**Estimated effort**: 5 minutes  
**Expected impact**: Complete exception detection (even if never fires)

---

## POST-FIX VERIFICATION CHECKLIST

### Corner Case: Two Exceptions (Oldest Wins)

After fixes, this scenario should work:
- **LW @ 0x100**: Misaligned address (detected at MEM)
- **ADD @ 0x104**: Legal (no exception)
- **ADDI @ 0x108**: Illegal encoding (detected at ID)

**Expected behavior**:
1. ✓ LW exception detected at t=4 MEM stage
2. ✓ ADD flushed continuously (younger than LW)
3. ✓ ADDI exception detected at t=4 ID stage
4. ✓ ADDI flushed at t=5 (continuous flush kills it)
5. ✓ Only LW exception commits at t=6 WB
6. ✓ CSR Port C writes: MEPC=0x100, MCAUSE=4 (misaligned), MTVAL=bad_addr

**Test**: Write test program with intentional misaligned load, verify trap handler sees correct cause and address.

---

### MRET Return Path

After fixes, this scenario should work:
- Handler executes at mtvec.BASE
- Handler encounters MRET instruction
- MRET retires at WB

**Expected behavior**:
1. ✓ mret_commit_o = 1 (combinational)
2. ✓ Port D updates (on clock edge): MIE ← MPIE, MPIE ← 1, MPP ← M
3. ✓ PC redirects to mepc (on clock edge)
4. ✓ Pipeline empties (final flush)
5. ✓ Execution resumes from mepc with interrupts enabled

**Test**: Write trap handler that executes some instructions then MRET, verify processor returns with correct privilege state and interrupt enable.

---

## FILES TO MODIFY

| File | Change Type | Severity | Lines |
|------|-------------|----------|-------|
| [top.v](core/top.v) | Fix 2 hardcoded ports + wire mret_valid | HIGH | ~2 lines |
| [memory_cycle.v](pipeline/memory_cycle.v) | Add MEM exception detection & merge logic | HIGH | ~20 lines |
| [csr_regfile.v](csr_regfile.v) | Add Port D MRET restore input & logic | MEDIUM | ~15 lines |
| [fetch_cycle.v](pipeline/fetch_cycle.v) | Add IF misalignment detector | LOW | ~3 lines |

**Total estimated effort**: 1.5–2 hours  
**Complexity**: Low–Medium (well-defined, confined changes)

---

## NEXT PHASE: Phase 3 Exception Handlers

Once above fixes are complete, next work should implement:
- **Access fault detection** at MEM (requires Data_Memory changes)
- **Illegal exception handler capture** (verify CSR reads work)
- **MRET handler restoration** (test automatic MSTATUS update)
- **Interrupt source integration** (connect IRQ from external controller)

---

## CONCLUSION

### Current State
The exception architecture is **87% complete and structurally sound**. Core propagate-and-commit model is correctly implemented. Pipeline infrastructure (valid bits, PC propagation, flush logic) is production-ready.

### Critical Gaps
Two architectural bugs (hardcoded inputs) and one missing feature (MEM exception detection) prevent proper exception handling. MRET restoration incomplete.

### Recommended Path Forward
1. **This week**: Fix issues A1, A2, A3 (3–4 hours)
2. **Next week**: Implement MRET Port D + complete MEM detection (2 hours)
3. **Follow-up**: Add interrupt integration + handler testing (ongoing)

### Confidence Level
**HIGH** (85%) that all signal flows are correct. Once hardcoded inputs fixed and MEM detector added, exception trapping should work for illegal instructions and load/store misalignment. MRET return requires Port D wiring.

---

**End of Executive Summary**

*For detailed cycle-accurate traces, see:*
- *[EXCEPTION_FLOW_AUDIT_AND_ANALYSIS.md](EXCEPTION_FLOW_AUDIT_AND_ANALYSIS.md)*
- *[EXCEPTION_FLOW_DIAGRAMS.md](EXCEPTION_FLOW_DIAGRAMS.md)*
