# Part 4: Verification & Testing Plan (Detailed)

This document defines a **structured, in-depth verification plan** for:
- Important RTL blocks (unit-level)
- Their combinations (integration)
- Full-core behavior (program-level)

It is written to match the current core architecture:
- 5-stage in-order RV32I pipeline (IF/ID/EX/MEM/WB)
- M-mode only
- **Propagate-and-commit** precise exceptions (exception sideband travels with the instruction)
- **Trap and MRET are committed at WB** using `utils/wb_trap_mret_commit_controller.v`
- **Continuous flush “wake”** in `utils/hazard_unit.v` ensures younger instructions cannot create side effects before trap commit

---

## 1) Verification Goals & Non-Goals

### 1.1 Primary correctness goals
1. **Functional RV32I correctness** for implemented instructions (ALU, loads/stores, branches/jumps, LUI/AUIPC).
2. **Pipeline correctness**: valid propagation, stall/flush rules, forwarding, load-use handling.
3. **Precise exceptions**:
     - Exception detection (IF + ID implemented today)
     - Sideband propagation to WB
     - Continuous younger-kill policy (“wake”)
     - Single-cycle trap commit at WB (CSR updates + redirect + pipeline empty)
4. **CSR correctness** for implemented CSRs and CSR instructions, including write masks.
5. **MRET correctness**: WB-boundary redirect to `mepc` and CSR restore behavior.

### 1.2 Explicit non-goals (as of current RTL)
- **Interrupt commit** is not integrated yet (CSR has inputs, but top-level ties are not used as a commit path).
- **MEM-local exception generation** (load/store misalignment/access-fault) is not implemented yet.
    - This means misaligned loads/stores will not trap and may perform incorrect memory updates.
    - The verification plan still includes those tests, but they are tracked as **expected-fail until implemented**.

---

## 2) Tooling, Environment, and Reproducibility

### 2.1 Simulator options
Minimum required capabilities:
- SystemVerilog/Verilog compilation
- Basic waveform dump
- Ability to run a testbench with cycle stepping

Recommended:
- **WSL** + Icarus Verilog (`iverilog`) + `vvp` + GTKWave
- **Verilator** (fast regression; needs a C++ harness)

**Current Windows status (verified in this repo)**:
- `iverilog` is not present on PATH (PowerShell reports “not recognized”).

### 2.2 Mandatory run controls (common across all tests)
Every test must define:
- Clock period (e.g., 10 ns)
- Reset behavior (active-low resets exist; note reset style varies across modules)
- A timeout (max cycles) to avoid dead simulations
- A clear pass/fail mechanism (assertion or signature write)

### 2.3 Determinism rules
To keep regressions stable:
- Avoid uninitialized memory dependence (initialize DMEM or write before read)
- Avoid X-propagation checks as “pass conditions” (use explicit initialization)
- Fix the reset sequence: hold reset low for N cycles, then release on a clock edge

---

## 3) Verification Methodology (Layered)

This plan is intentionally layered to isolate bugs quickly.

### Layer L0 — Static checks (compile/elaborate)
Purpose: detect syntax, missing ports, accidental implicit nets.
- Compile all RTL + TB
- Treat warnings as actionable (especially width mismatches)

### Layer L1 — Unit tests (module-level, no pipeline)
Purpose: validate leaf blocks in isolation with exhaustive corner cases.
- ALU, decode blocks, sign extension, load/store formatting, memories, regfile, PC

### Layer L2 — Stage tests (pipeline stage modules)
Purpose: validate each pipeline stage wrapper + its internal pipeline register behavior.
- fetch_cycle, decode_cycle, execute_cycle, memory_cycle, writeback_cycle

### Layer L3 — Control-plane tests (hazards, forwarding, flush)
Purpose: validate `hazard_unit.v` policies and corner interactions.
- load-use stall, CSR stall, redirect-stall override, continuous flush wake

### Layer L4 — Precise trap + MRET (commit-boundary correctness)
Purpose: validate the retirement-boundary semantics.
- `wb_trap_mret_commit_controller.v` correctness
- CSR trap entry correctness in `csr_regfile.v`
- Redirect priority over branches
- Pipeline emptying and side-effect suppression

### Layer L5 — Full-core program tests and trace checking
Purpose: end-to-end correctness.
- Directed assembly tests
- Randomized instruction streams (later)
- Golden reference comparison to Spike (when toolchain is available)

---

## 4) Testbench Architecture (Required for All Integration Tests)

### 4.1 Top-level TB responsibilities
A single reusable TB should:
1. Drive clock + reset
2. Load IMEM contents per test (via `$readmemh`, or by editing `Instruction_Memory.v` program blocks)
3. Optionally pre-initialize DMEM
4. Provide an always-on set of checkers:
     - Architectural register scoreboard
     - Memory scoreboard (where deterministic)
     - Trap/MRET event logger

### 4.2 Required monitors (signals)
For debugging precise exceptions, the TB must capture:
- `valid_D/E/M/W`
- `exc_valid_*`, `exc_cause_*`, `exc_tval_*`, `exc_pc_*`
- `FlushD/E/M/W`, `StallF/D`, `PCSrcE`
- `wb_trap_redirect`, `trap_target`, `flush_pipeline_onehot`
- `mret_commit`

### 4.3 Commit event definition (core-level)
Define three WB-visible event types:
1. **Normal commit**: instruction retires and can update architectural state.
2. **Trap commit**: exception retires; architectural state is updated only via trap-entry CSR writes and redirect.
3. **MRET commit**: return retires; architectural state is updated only via CSR restore and redirect.

Suggested event qualification (matches current design intent):
- Normal commit occurs when `valid_W && !exc_valid_W && !mret_commit`
- Trap commit occurs when `valid_W && exc_valid_W`
- MRET commit occurs when `mret_commit` (which is already commit-qualified)

### 4.4 Golden-reference checking (Spike) strategy
When a RISC-V toolchain and Spike are available:
- Run the same program on Spike with commit logging
- Produce an RTL commit log from WB
- Compare traces (PC/instruction/rd/writeback value) for normal commits
- Compare trap events (mcause/mepc/mtval) against expected values

---

## 5) Detailed Block-Level Verification (Per Important RTL File)

This section defines what must be verified for each important file/module.
For each block:
- **Intent** (what it is supposed to do)
- **Directed tests** (minimum required)
- **Corner cases** (high-risk behaviors)
- **Pass criteria** (observable success)

### 5.1 core/top.v (integration)
Intent:
- Correct wiring between pipeline stages, hazard unit, CSR regfile, WB commit controller
- Correct gating at WB (no reg/CSR writes on exception or MRET)

Directed tests:
- TOP-1: “smoke” program (NOPs + a few ADDI) to confirm no X/unknowns after reset and stable PC.
- TOP-2: branch taken + WB redirect priority (force trap and ensure trap target wins over PCSrcE).

Corner cases:
- Trap redirect coincident with a taken branch (same cycle): verify fetch uses trap target.
- WB redirect coincident with `lwstall` or CSR stall: verify stalls are overridden and redirect takes effect.
- Reset style mismatch across modules (some async, some sync): verify a consistent TB reset sequence works.

Pass criteria:
- No architectural state updates occur on trap/mret except CSR trap entry/restore.
- PC redirect target matches mtvec/mepc alignment semantics (lower 2 bits cleared).

---

### 5.2 pipeline/fetch_cycle.v (IF + IF/ID register)
Intent:
- Compute next PC with priority: WB redirect > branch/jump target > PC+4
- Implement stall/flush behavior of IF/ID
- Emit IF-stage exception (instruction address misaligned)

Directed tests:
- IF-1: PC increments by 4 for sequential execution.
- IF-2: `StallF=1` freezes PC; `StallD=1` freezes IF/ID register.
- IF-3: `FlushD=1` clears IF/ID regs and forces `valid_D=0`.
- IF-4: redirect priority: assert `PCSrcE=1` and `wb_trap_redirect=1` together; verify next PC is `trap_target`.
- IF-5: instruction address misaligned exception: drive `PC_Next` to an unaligned value via a JALR target and check `exc_valid_D` becomes 1 (and remains with the instruction).

Corner cases:
- `FlushD=1` while `StallD=1`: flush must win (IF/ID becomes bubble).
- `wb_trap_redirect=1` while `StallF=1`: PC must still redirect (in this design, hazard unit overrides stalls on redirect; verify this end-to-end).
- Reset assertion/deassertion at arbitrary times: IF/ID outputs must be benign (Instr=0, valid=0).

Pass criteria:
- PC sequence matches expected priority.
- IF exception sideband fields are correct (`exc_pc=PCF`, `exc_tval=PCF`, `cause=0`).

---

### 5.3 pipeline/decode_cycle.v (ID + ID/EX register)
Intent:
- Decode control signals, read regfile, generate immediates
- Detect ID-local exceptions: illegal instruction, ECALL, EBREAK
- Merge IF exception sideband with ID-local exception (“first wins”)
- Pipeline CSR address/rd index and MRET flag

Directed tests:
- ID-1: illegal instruction detection (`.word 0x00000000`) sets `exc_valid` and cause=2, tval=Instr.
- ID-2: ECALL (`0x00000073`) sets cause=11.
- ID-3: EBREAK (`0x00100073`) sets cause=3.
- ID-4: merge priority test: create an IF misaligned fetch for an instruction that is also illegal; verify IF-sideband wins (cause=0).
- ID-5: `FlushE=1` clears all ID/EX regs and `valid_E=0`.
- ID-6: regfile read correctness with same-cycle WB write forwarding (write x5 in WB; read x5 in ID same cycle).

Corner cases:
- CSR address pipelining: ensure `csr_raddr_E` matches the instruction in EX even across `FlushE`.
- `valid_D=0` input (bubble) must not create spurious exceptions; verify `valid_E` becomes 0 and exc fields clear.
- SYSTEM opcode that is not a CSR op (ECALL/EBREAK/MRET) must not corrupt CSR write paths (it may still assert RegWrite but rd=0; verify x0 stays 0).

Pass criteria:
- Exception merge logic matches spec:
    - `next_exc_valid = exc_valid_D || new_exc_valid_D`
    - If `exc_valid_D=1`, cause/tval must be preserved.

---

### 5.4 control/Main_Decoder.v, control/Control_Unit_Top.v, ALU/ALU_Decoder.v
Intent:
- Correct opcode-level control generation
- Correct ALUControl mapping for arithmetic and branch comparisons
- CSR decode correctness and MRET exact encoding detection

Directed tests:
- DEC-1: For each opcode class, verify control outputs:
    - Load: ResultSrc=01, ALUSrc=1, MemWrite=0
    - Store: MemWrite=1, ALUSrc=1, ResultSrc=00
    - Branch: Branch enable asserted
    - JAL/JALR: Jump asserted; ResultSrc=10
    - CSR: ResultSrc=11, csr_valid asserted
- DEC-2: Branch funct3 mapping drives correct ALUControl:
    - BEQ/BNE => SUB
    - BLT/BGE => SLT
    - BLTU/BGEU => SLTU
- DEC-3: MRET detection: only `0011000_00010_00000_000_00000_1110011` asserts `is_mret`.

Corner cases:
- “SYSTEM but not CSR”: ensure `csr_valid` is high for opcode 0x73, but `csr_op==00` for non-CSR funct3 patterns; verify no CSR write enable is generated downstream.
- SUB detection for R-type only: `{op_5, funct7_30}==2'b11` triggers SUB, not for ADDI.

Pass criteria:
- Control outputs match RV32I expectations for the implemented subset.

---

### 5.5 ALU/ALU.v
Intent:
- Implement ALU ops and Zero flag

Directed tests:
- ALU-1: ADD/SUB (including overflow wrap-around behavior).
- ALU-2: AND/OR/XOR.
- ALU-3: SLL/SRL/SRA with shift amounts 0, 1, 31.
- ALU-4: SLT/SLTU for negative vs positive comparisons.
- ALU-5: JALR op clears bit 0 of the sum.

Corner cases:
- Zero flag correctness for all operations (especially SLT/SLTU which return 0/1).
- SRA sign extension correctness for negative A.

Pass criteria:
- ALU outputs match a software reference model for a directed vector set.

---

### 5.6 utils/JB_unit.v
Intent:
- Convert branch/jump control buses + ALU Zero into `yes` and `JALR`

Directed tests:
- JB-1: BEQ/BNE with equal and non-equal operands (Zero=1/0).
- JB-2: BLT/BGE using SLT result (Result=1 => Zero=0 means taken for BLT).
- JB-3: BLTU/BGEU using SLTU result.
- JB-4: Jump always taken when Jump[1]=1.

Corner cases:
- Ensure branch enable B[3]=0 forces no branch regardless of funct3.
- Ensure unknown funct3 patterns do not incorrectly assert take.

Pass criteria:
- `yes` matches expected condition across all branch types.

---

### 5.7 pipeline/execute_cycle.v (EX + EX/MEM register)
Intent:
- Forwarding muxes and ALU execution
- Branch/jump target compute and taken decision
- Gate PC redirect when instruction is invalid or exception-tagged
- CSR read/modify/write computation and old CSR capture
- Correctly pipeline store data (`RD2_E`) and not forwarded operand

Directed tests:
- EX-1: Forwarding from MEM has priority over WB.
- EX-2: Load-use hazard sequence shows stall (validated in hazard tests) and correct operand values.
- EX-3: Taken branch flush: verify `PCSrcE=1` only when `valid_E=1` and `exc_valid_E=0`.
- EX-4: JALR target alignment: verify bit 0 cleared.
- EX-5: CSR operation compute:
    - csr_imm_mode selects uimm vs rs1
    - csr_write_en asserted only when csr_op != 00
    - old CSR value is captured for WB result path
- EX-6: Store data path: confirm `WriteDataM` equals original `RD2_E`, not a forwarded value.

Corner cases:
- A branch instruction that is exception-tagged in ID must not redirect PC in EX.
- `FlushM=1` must clear all EX/MEM registers, including CSR write bundle and exception sideband.
- Forwarding when destination is x0 must never occur.

Pass criteria:
- PC redirect is suppressed for invalid or exception-tagged instruction.
- EX/MEM register contents are correct across stalls/flushes.

---

### 5.8 utils/hazard_unit.v
Intent:
- Generate forwarding selects
- Detect load-use hazards and stall appropriately
- Detect CSR RAW hazards (CSR read in decode vs pending CSR writes)
- Implement continuous flush wake behind exception-tagged instruction
- Override stalls on WB redirect so fetch can take the redirect immediately

Directed tests:
- HAZ-1: ForwardAE/ForwardBE cases:
    - MEM forward (2'b10)
    - WB forward (2'b01)
    - none (2'b00)
- HAZ-2: Load-use stall triggers StallF/StallD and FlushE.
- HAZ-3: CSR hazard stall triggers StallF/StallD and FlushE.
- HAZ-4: Taken branch flush behavior: FlushD and FlushE asserted.
- HAZ-5: Continuous flush wake:
    - Create an ID exception (ECALL) and place a store right after it.
    - Verify younger instructions are continuously flushed until trap commit.
    - Verify no store reaches MEM with `valid_M=1`.
- HAZ-6: WB redirect overrides stalls:
    - Force a lwstall and simultaneously commit a trap/mret; verify StallF/StallD deassert and PC redirects.

Corner cases:
- Exception in EX vs MEM: ensure correct wake behavior with `exc_inflight_E` and `exc_inflight_M`.
- `flush_pipeline_onehot` must empty the whole pipeline on redirect.
- Ensure `illegal_instr` is not used as a flush source here (it must propagate as an exception sideband).

Pass criteria:
- No younger instruction can commit architectural state while an exception-tagged instruction is in flight.

---

### 5.9 pipeline/memory_cycle.v and utils/ls_unit.v
Intent:
- Provide data memory access, load formatting, store alignment/strobes
- Gate stores using `valid_M` and `~exc_valid_M`
- Pipeline all WB-facing fields including exception sideband and is_mret

Directed tests:
- MEM-1: Store types SB/SH/SW generate correct WSTRB and aligned WD.
- MEM-2: Load types LB/LH/LW/LBU/LHU produce correct sign/zero extension.
- MEM-3: Store followed by load same address (1 cycle later) returns stored value.
- MEM-4: `FlushW=1` clears MEM/WB regs and `valid_W=0`.

Corner cases:
- Address lane selection correctness for LB/LBU (byte lanes 0..3).
- Halfword lane selection correctness for LH/LHU (address[1]).
- Partial store merging behavior: SB then LB to same byte.

Known gap (expected-fail tests until implemented):
- MEM-X1: Misaligned load/store traps (mcause=4/6 and mtval=fault address) are not generated today.
    - Track these as pending.

Pass criteria:
- For aligned accesses, load/store results match a software reference.
- Store writes are suppressed when `exc_valid_M=1` or `valid_M=0`.

---

### 5.10 memory/Data_Memory.v and memory/Instruction_Memory.v
Intent:
- Provide simple memories for simulation

Directed tests:
- IMEM-1: instruction fetch returns expected words for a known program image.
- DMEM-1: each WSTRB bit correctly updates a single byte lane.

Corner cases:
- DMEM read-during-write same address: define the expected behavior in TB (since this memory is not a true synchronous RAM model).
- Reset behavior:
    - DMEM outputs 0 when reset asserted (as coded)
    - IMEM outputs 0 when reset asserted

Pass criteria:
- Memory models behave consistently with TB expectations.

---

### 5.11 memory/Register_File.v
Intent:
- 2 async read ports, 1 sync write
- x0 hardwired to zero
- same-cycle write-forwarding for reads

Directed tests:
- RF-1: write/read each register x1..x31.
- RF-2: writes to x0 are ignored; x0 always reads 0.
- RF-3: same-cycle forwarding: write xN and read xN same cycle returns WD3.

Corner cases:
- Simultaneous reads of the write address on both ports.
- Reset asserted: reads forced to 0.

Pass criteria:
- All behaviors match a simple golden model.

---

### 5.12 csr_regfile.v and utils/wb_trap_mret_commit_controller.v

Intent:
- CSR file behaves as passive storage with:
  - combinational reads
  - priority: trap entry > MRET restore > exc-port writes > normal writes
- WB commit controller decides trap/MRET commit and drives redirect + pipeline flush

Directed tests:

**CSR Functionality:**
- CSR-1: read/write mscratch (fully writable).
- CSR-2: mstatus write mask: only [3]=MIE, [7]=MPIE, [12:11]=MPP writable.
- CSR-3: mtvec write mask: [31:2]=BASE, [1:0] frozen to 00 (Direct mode only).

**Trap Entry (must be atomic on clock edge):**
- CSR-4a: mepc correctly captures trap_pc (PC of faulting instruction)
- CSR-4b: mcause captures {interrupt_bit, cause} (bit [31] = 0 for exceptions, 1 for interrupts)
- CSR-4c: mtval captures trap_addr when trap_addr_valid=1, else 0
- CSR-4d: mstatus[3] (MIE) clears to 0 on trap entry
- CSR-4e: mstatus[7] (MPIE) captures previous MIE on trap entry
- CSR-4f: mstatus[12:11] (MPP) set to 2'b11 (Machine mode) on trap entry

**MRET Restore (must be atomic on clock edge):**
- CSR-5a: mstatus[3] (MIE) restored from mstatus[7] (MPIE)
- CSR-5b: mstatus[7] (MPIE) set to 1 after MRET
- CSR-5c: mstatus[12:11] (MPP) set to 2'b00 after MRET
  - **NOTE**: RIPrepare spec ambiguity—for M-mode-only core, this is conservative (returns to User, not Machine)
- CSR-5d: **MRET commit-qualified**: normal register writes suppressed when mret_commit=1
- CSR-5e: **MRET commit-qualified**: normal CSR writes suppressed when mret_commit=1 (only restore happens)

**WB Trap/MRET Controller Logic (combinational, atomic commit):**
- WBCTRL-1: trap_commit = valid_W & exc_valid_W
- WBCTRL-2: mret_commit = valid_W & is_mret_W & ~exc_valid_W (MRET only commits if no exception)
- WBCTRL-3: wb_redirect = trap_commit | mret_commit
- WBCTRL-4: trap_target alignment:
  - For trap: {mtvec[31:2], 2'b00}
  - For MRET: {mepc[31:2], 2'b00}
- WBCTRL-5: flush_pipeline_onehot = 4'b1111 when wb_redirect asserted

Corner cases:
- Trap while MRET bit set: trap takes priority (exception beats control transfer)
- Normal CSR write same cycle as trap: trap write priority (Port C > Port B in CSR regfile)
- MRET with exception pending: MRET commit is blocked (mret_commit ANDed with ~exc_valid_W)
---

## 6) Cross-Block Integration Tests (Most Important)

These are “high value” tests that validate interactions, not just blocks.

### I-1: Load-use hazard (stall correctness)
Sequence:
1. `lw x1, 0(x0)`
2. `add x2, x1, x3`
Checks:
- `StallF=1`, `StallD=1`, `FlushE=1` for the hazard window
- x2 matches expected value

### I-2: Forwarding priority
Sequence:
1. produce a value in MEM
2. use it immediately in EX (needs forward from MEM)
3. also have WB writing same register in the same cycle
Checks:
- Forward select chooses MEM over WB

### I-3: CSR hazard (back-to-back CSR on same address)
Sequence:
1. `csrw mscratch, x5`
2. `csrr x6, mscratch`
Checks:
- hazard unit stalls so x6 sees updated mscratch

### I-4: Precise exception wake (side-effect suppression) — CRITICAL TEST
**Sequence:**
1. `addi x5, x0, 0x1000`  (setup address)
2. `ecall`                 (exception in IF/ID stage)
3. `sw x10, 0(x5)`        (store in immediately following instruction slot)
4. Handler reads memory at address 0x1000

**Expected behavior:**
- While ECALL flows from ID → EX → MEM → WB, the store instruction enters decode
- Since `exc_inflight_E = valid_E & exc_valid_E`, decode is continuously flushed
- When ECALL commits at WB, `flush_pipeline_onehot = 4'b1111` empties all remaining stages
- **Store write never occurs** (MemWriteM is gated by its `~exc_valid_M`, or the store is flushed before reaching MEM)

**What this validates:**
- Continuous flush (not one-shot) prevents younger instruction side effects
- No architectural state corruption even when younger instruction reaches execute/memory stages
- Exception "wake" creates a bubble zone protecting trap integrity

### I-5: Trap commit + pipeline emptying
Checks (waveform-based):
- On trap commit, `wb_trap_redirect=1` and `flush_pipeline_onehot=1111`
- Within a bounded number of cycles, `valid_D/E/M/W` all become 0 (pipeline drained/emptied)

### I-6: MRET commit behavior
Sequence:
1. trap to handler
2. set mepc to skip faulting instruction
3. execute mret
Checks:
- redirect occurs only at WB boundary
- `mret_commit=1` for one cycle
- no regwrite/csr normal write occurs in the mret commit cycle

---

## 7) Program-Level Directed Tests (Assembly)

These programs should be small and single-purpose. For each program:
- define a signature region in DMEM to store results
- halt by jumping to a self-loop

Minimum program set:
- P-ALU: arithmetic + shifts + comparisons
- P-BR: branches taken/not taken + JAL/JALR
- P-LS: SB/SH/SW and LB/LH/LW/LBU/LHU
- P-CSR: CSRRW/CSRRS/CSRRC and immediate variants
- P-TRAP: ECALL trap entry + handler modifies mepc + MRET return
- P-ILL: illegal instruction trap

Expected-fail (until implemented):
- P-MISALIGN: misaligned load/store traps

---

## 8) Corner Case Checklist (Quick Index)

This is a compact checklist to ensure no critical corner is missed:

1. **Reset behavior**: all stage valids cleared, pipeline registers zeroed
2. **Stall + flush same cycle**: When both StallD and FlushE asserted simultaneously, flush must win (line 264 in decode_cycle.v)
3. **WB redirect + stall same cycle**: When StallF would stall, but wb_trap_redirect asserts, stall must be overridden so IF can take redirect immediately (line 162 in hazard_unit.v)
4. **Branch + trap redirect same cycle**: WB trap/MRET redirect has priority over PCSrcE branch redirect (PC_F priority mux in fetch_cycle.v)
5. **Illegal instruction followed by load**: Illegal instr. sets exc_valid_D, younger load enters decode while illegal is in EX, load does not write register (RegWriteW gated by ~exc_valid_W)
6. **Exception in EX while store in MEM** (CRITICAL):
   - ECALL in EX-stage while store instruction is simultaneously in MEM
   - `MemWriteM_gated = MemWriteM & valid_M & ~exc_valid_M`
   - Store write must be suppressed when its own exc_valid_M is set (propagated exception from older instruction)
   - **OR** store is flushed by continuous `FlushM = ... | exc_inflight_E | ...`
7. **CSR back-to-back same address**: ID-stage CSR read while EX-stage CSR write to same address triggers CSR hazard stall (hazard_unit.v line 150)
8. **Load-use hazard**: LW in EX, ADD reading same register in ID triggers stall, forwarding cannot bypass load result
9. **Partial stores** (SB/SH): WSTRB byte lanes correctly generated for misaligned bytes (ls_unit.v)
10. **Signed vs unsigned branches**: BLT uses SLT (signed comparison), BLTU uses SLTU (unsigned) via ALU result
11. **JALR target not word-aligned**: ALU operation (bit 0 cleared) ensures JALR target is always even address when executed
12. **MRET commit-gates writes**: When mret_commit=1 (at WB), RegWriteW and normal csr_write_en are suppressed (top.v line 186–187)

---

## 9) Regression & Coverage (Practical)

### 9.1 Regression cadence
- Run L0-L2 on every RTL change
- Run L3-L5 nightly (or when adding control-path features)

### 9.2 Functional coverage targets (minimum)
- Every opcode class exercised
- Every branch type taken and not taken
- Every load/store width and lane exercised
- Every CSR op type exercised (RW/RS/RC, reg and immediate)
- Trap entry + mret return exercised

### 9.3 Debug workflow
When a test fails:
1. Check commit log around the first mismatch
2. Inspect `valid_*` and flush/stall signals
3. Inspect exception sideband for the failing instruction
4. Confirm whether failure is due to a known gap (misalign/interrupt) vs real bug

