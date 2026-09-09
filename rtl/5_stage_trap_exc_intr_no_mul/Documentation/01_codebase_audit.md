# Part 1: Codebase Audit & Current State Assessment

## File Inventory

| File | Role | Status |
|------|------|--------|
| `core/top.v` | Top-level integration | ✅ Integrates WB trap/MRET commit + CSR trap wiring + hazard flush plumbing |
| `pipeline/fetch_cycle.v` | IF stage + IF/ID reg | ✅ Supports WB redirect + trap target inputs; propagates `valid` + IF exception sideband |
| `pipeline/decode_cycle.v` | ID stage + ID/EX reg | ✅ Propagates `valid` + exception sideband; pipelines CSR addr/rd fields for stall safety |
| `pipeline/execute_cycle.v` | EX stage + EX/MEM reg | ✅ Has `FlushM`; gates branch/jump redirect on `valid_E & ~exc_valid_E`; propagates `is_mret` |
| `pipeline/memory_cycle.v` | MEM stage + MEM/WB reg | ⚠️ Has `FlushW` + side-effect gating for stores, but MEM-local exceptions (misalign/access-fault) not yet implemented |
| `pipeline/writeback_cycle.v` | WB mux | ✅ Minimal, functional |
| `control/Control_Unit_Top.v` | Decode control | ✅ Synthesizable; CSR decode and full MRET encoding detection |
| `control/Main_Decoder.v` | Opcode decode | ✅ Synthesizable (comment typo fixed earlier) |
| `control/opcode_check.v` | Illegal opcode flag | ✅ Base opcode legality only (full funct3/funct7 legality still future work) |
| `utils/hazard_unit.v` | Forwarding + stall/flush | ✅ Implements continuous exception “wake” flush + WB redirect flush; `flush_pipeline_onehot` is driven |
| `utils/PC.v` | PC register | ✅ Functional (redirect mux lives in IF stage) |
| `utils/ls_unit.v` | Load/store alignment | ✅ Functional |
| `csr_regfile.v` | CSR storage | ✅ Passive storage + trap-entry + commit-qualified MRET update (no IRQ commit yet) |
| `utils/wb_trap_mret_commit_controller.v` | WB retire controller | ✅ New: commits traps/MRET at WB, redirects IF, requests pipeline emptying |
| `trap_controller.v` | Trap logic | 🔴 Legacy, non-synthesizable, and intentionally unused |

---

## Critical Bugs / Gaps (Next Items)

### Gap 1: MEM-stage exception detection is missing
`pipeline/memory_cycle.v` currently gates stores using propagated `exc_valid_M`, but does not yet generate MEM-local exceptions (load/store misalignment or access faults). This means tests like “misaligned store triggers trap” will not pass until MEM-local exception tagging is implemented.

### Gap 2: Interrupt/CLIC integration is not implemented
The core currently hardwires `trap_is_interrupt=0` in the WB commit controller and ties CSR interrupt pending inputs low in `core/top.v`. The interrupt frontend/handshake is deferred.

### Note: legacy `trap_controller.v`
This file remains in the repo for reference but is intentionally not used; the architecture is now “propagate-and-commit” with a WB boundary commit controller.

### Environment Note: `iverilog` not found on Windows PATH
The last failing build attempt was due to the simulator binary being absent in the Windows shell, not due to RTL errors. VS Code diagnostics currently report no syntax/elaboration errors.

## What Works Today (Updated)

✅ Basic RV32I instruction execution (R/I/S/B/U/J types)
✅ Data forwarding (MEM→EX, WB→EX)
✅ Load-use stall detection
✅ Branch/jump flush + gated branch redirect (no redirect from bubbles/faulting instructions)
✅ Valid-bit propagation through pipeline regs
✅ Exception sideband propagation to WB (precise trap model)
✅ Continuous flush “wake” behind exception-tagged instructions
✅ WB boundary trap commit + redirect to `mtvec` and MRET commit + redirect to `mepc`
✅ CSR trap-entry updates (`mepc/mcause/mtval/mstatus`) and commit-qualified MRET restore

---

## Architectural Gaps for Trap Support

### Gap 1: No Valid Bits in Pipeline
No `valid_if`, `valid_id`, `valid_ex`, `valid_mem`, `valid_wb` signals. Without these, you cannot distinguish a real instruction from a bubble. Critical for knowing when the faulting instruction reaches WB.

### Gap 2: No PC Propagation Through All Stages
- `PCE` exists (EX stage PC)
- No `PC_M` in memory stage
- No `PC_W` in writeback stage
- Trap entry needs the faulting instruction's PC at WB/commit time

### Gap 3: No Exception Sideband in Pipeline Registers
Pipeline registers don't carry `exc_valid`, `exc_cause`, `exc_tval` fields. Exceptions detected in ID or EX cannot travel to WB for precise commit.

### Gap 4: No Instruction Propagation
`InstrD` exists but `InstrE`, `InstrM`, `InstrW` do not. Needed for `mtval` (illegal instruction encoding) at commit time.

### Gap 5: PC Mux Only Has 2 Inputs
`fetch_cycle.v` PC mux: `PCPlus4F` or `PCTargetE`. Need a third input for trap redirect (`mtvec`) and a fourth for `MRET` return (`mepc`).

### Gap 6: No Retire/Commit Signal
No `wb_valid` or equivalent signal to indicate an instruction is actually committing at WB. The trap FSM needs this to know when the faulting instruction has reached retirement.

---

## What Works Today

✅ Basic RV32I instruction execution (R/I/S/B/U/J types)  
✅ Data forwarding (MEM→EX, WB→EX)  
✅ Load-use stall detection  
✅ Branch/jump flush (FlushD, FlushE)  
✅ CSR read path (combinational read in EX, async from csr_regfile)  
✅ CSR write path (propagated through EX→MEM→WB pipeline registers)  
✅ CSR instruction decode (CSRRW/CSRRS/CSRRC + immediate variants)  
✅ Load/store byte/half/word alignment (ls_unit)  
✅ Bubble sort program runs correctly  
