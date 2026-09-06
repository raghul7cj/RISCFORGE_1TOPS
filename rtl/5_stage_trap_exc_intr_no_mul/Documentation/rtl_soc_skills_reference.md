# RTL & SoC Design Skills — AI Assistant Reference Guide

> **Scope**: Two active hardware projects sharing one developer.
> 1. **RISCFORGE 1TOPS** — 5-stage in-order RV32I core → bare-metal C + CLIC + SoC peripherals
> 2. **PBDE Ping-Pong** — AES accelerator with ping-pong buffering + coarse clock gating on PYNQ-Z2 (Zynq-7000)
>
> **Purpose**: Inject these skills as a system-level header so any model — regardless of capability tier — adheres to architectural discipline, avoids known RTL pitfalls, and produces code that integrates cleanly on the first attempt.
>
> **Usage**: Prepend the relevant skill block(s) to your prompt when delegating sub-tasks.

---

## Skill 1 — Architectural Thinking Before Code

**Rule**: Never write RTL until the datapath, control signals, and timing diagram for the feature are written down in prose or a table. Code is the *last* step.

### Mandatory Pre-Coding Checklist

1. **Draw the signal flow** — Which module produces the signal? Which module consumes it? Through how many pipeline registers does it pass?
2. **State the timing** — Is the signal combinational in the same cycle, or registered and available next cycle? Mis-timed signals cause silent data corruption.
3. **Identify the flush/stall interaction** — Every new signal that crosses a pipeline register must answer: *What happens to this signal when the stage is flushed? When the stage is stalled?*
4. **Write the port list first** — Define inputs, outputs, widths, and a one-line comment for each port before writing any logic. This is the contract.
5. **State acceptance criteria** — What waveform pattern or register value proves the feature works?

### Anti-Patterns

- ❌ Writing an entire module then trying to "wire it in" to `top.v` — guarantees port mismatches.
- ❌ Adding a signal to one pipeline stage but forgetting to propagate it through downstream registers.
- ❌ Assuming a signal is "ready" without checking which clock edge it settles on.

### Project-Specific Notes

| Project | Key Architectural Contract |
|---------|---------------------------|
| RISCFORGE | **Propagate-and-commit**: Exceptions travel as pipeline sideband. Trap fires combinationally at WB. No FSM. Continuous flush kills younger instructions. |
| PBDE | **Ping-pong overlap**: Buffer A drains while Buffer B fills. `drain_engine` owns AXI-Stream toward AES. `clk_gate_ctrl` uses synchronous registered enable — never async. |

---

## Skill 2 — Pipeline-Safe RTL Patterns (RISCFORGE-Specific)

**Rule**: Every pipeline register follows one canonical template. Deviating from it causes flush/stall bugs that are nearly impossible to debug from waveforms alone.

### Canonical Pipeline Register Template

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        signal_out <= RESET_VALUE;
    end else if (flush) begin
        signal_out <= FLUSH_VALUE;      // Usually same as RESET_VALUE
    end else if (!stall) begin          // Stall = hold current value
        signal_out <= signal_in;
    end
    // else: stall — implicit hold, no assignment
end
```

### Mandatory Invariants

| Invariant | Explanation |
|-----------|-------------|
| **Flush priority > Stall** | `if (flush) ... else if (!stall)`. Reversing this allows a stalled stage to ignore a flush — corrupt state persists. |
| **Valid bit follows the same template** | `valid_out <= flush ? 1'b0 : stall ? valid_out : valid_in;` |
| **Exception sideband cleared on flush** | `exc_valid_out <= flush ? 1'b0 : stall ? exc_valid_out : exc_valid_in;` — A flushed instruction's exception is discarded. |
| **Every field in the register must be flushed** | If you add `is_mret` to a pipeline register, it must be cleared on flush. Missing this lets ghost MRET signals fire traps. |
| **PC propagates through ALL stages** | `PCE` → `PC_M` → `PC_W`. Trap entry writes `mepc = exc_pc_W`. Missing `PC_W` means `mepc` gets garbage. |

### Cross-Check Before Committing

- [ ] Count: does every pipeline register in the file use `flush` and `stall` correctly?
- [ ] Count: does every new field added to a pipeline register appear in the flush clause?
- [ ] Verify: `valid` bits are 0 after reset and after flush, 1 only when a real instruction enters.

---

## Skill 3 — Exception Sideband Propagation & First-Wins Merge

**Rule**: Exceptions are metadata attached to an instruction, not global events. They propagate forward through pipeline registers and merge using "first wins" — an earlier-stage fault takes priority because it represents a more fundamental failure.

### Merge Logic (use verbatim)

```verilog
// At stage boundary (e.g., ID merging IF-propagated + ID-local):
wire exc_merged_valid = exc_from_prev | exc_local;
wire [4:0] exc_merged_cause = exc_from_prev ? cause_prev : cause_local;
wire [31:0] exc_merged_tval = exc_from_prev ? tval_prev  : tval_local;
wire [31:0] exc_merged_pc   = PC_current_stage; // Always this instruction's PC
```

### Detection Points (RISCFORGE)

| Stage | Exception | Cause Code | `tval` |
|-------|-----------|------------|--------|
| IF | Instruction address misaligned | 0 | Faulting PC |
| ID | Illegal instruction | 2 | Instruction encoding |
| ID | ECALL | 11 | 0 |
| ID | EBREAK | 3 | 0 |
| MEM | Load address misaligned | 4 | Faulting address |
| MEM | Store address misaligned | 6 | Faulting address |

### Anti-Patterns

- ❌ Overwriting an earlier exception with a later one (e.g., MEM misalignment overwrites ID illegal). Use `exc_from_prev ? prev : local`.
- ❌ Detecting a MEM exception on an instruction that already has `exc_valid` from ID — this instruction should never have issued a real memory access. The gating in Skill 4 prevents the write, but the detection logic must still use `~exc_valid_propagated` as a guard.
- ❌ Setting `exc_pc` to a different stage's PC. Always use the instruction's own PC at the stage where the sideband is assembled.

---

## Skill 4 — Side-Effect Gating (Zero-Leak Guarantee)

**Rule**: An instruction with `valid == 0` or `exc_valid == 1` must produce **zero** architectural side effects. No register write, no memory write, no CSR write, no PC redirect.

### Gating Equations (copy exactly)

```verilog
// EX stage — prevent faulting/flushed instruction from redirecting PC
assign PCSrcE = branch_taken_raw & valid_E & ~exc_valid_E;

// MEM stage — prevent faulting instruction from writing memory
// exc_valid_M_final includes SAME-CYCLE local detection (no circular dep)
wire exc_valid_M_final = exc_valid_M_propagated | exc_valid_mem_local;
assign MemWriteM = MemWriteM_raw & valid_M & ~exc_valid_M_final;

// WB stage — prevent faulting instruction from writing regfile or CSRs
assign RegWriteW    = RegWriteW_raw    & valid_W & ~exc_valid_W;
assign csr_write_en = csr_write_en_raw & valid_W & ~exc_valid_W;
```

### Why Same-Cycle MEM Gating Works

`MemWriteM_raw` comes from the EX/MEM pipeline register (registered last cycle). `exc_valid_mem_local` is combinational from the MEM-stage alignment check (this cycle). There is no circular dependency because the memory write enable depends on the exception, not the other way around. The store is suppressed in the same cycle it would have fired.

### Verification Check

Run a misaligned `sw` instruction. Confirm in waveform: `MemWriteM_raw = 1`, `exc_valid_M_final = 1`, therefore `MemWriteM = 0`. Memory content at the target address must be unchanged.

---

## Skill 5 — CSR Read-Modify-Write Correctness

**Rule**: CSR instructions are atomic read-modify-write operations. The read value goes to `rd`, the modified value goes back to the CSR. Both happen at WB commit.

### CSR Instruction Semantics

| Instruction | Operation | Read → rd | Write → CSR |
|-------------|-----------|-----------|-------------|
| CSRRW | Swap | old CSR value | rs1 |
| CSRRS | Set bits | old CSR value | old \| rs1 |
| CSRRC | Clear bits | old CSR value | old & ~rs1 |
| CSRRWI | Swap (imm) | old CSR value | zero_ext(imm) |
| CSRRSI | Set (imm) | old CSR value | old \| zero_ext(imm) |
| CSRRCI | Clear (imm) | old CSR value | old & ~zero_ext(imm) |

### Write Priority (RISCFORGE CSR Regfile)

Three write sources, strict priority:
1. **Trap entry** (highest) — writes `mepc`, `mcause`, `mtval`, modifies `mstatus`
2. **MRET** — restores `mstatus.MIE` from `mstatus.MPIE`
3. **CSR instruction** (lowest) — normal read-modify-write

If `wb_trap_commit` fires the same cycle a CSR instruction retires, the trap port wins and the CSR instruction's write is suppressed (already handled by Skill 4 gating since the faulting instruction has `exc_valid_W = 1`).

### Write Masks

Not all CSR bits are writable. Apply masks:
- `mstatus`: only bits `{MPP[12:11], MPIE[7], MIE[3]}` → mask `0x00001888`
- `mtvec`: bits `[31:2]` writable, `[1:0]` frozen to `00` (Direct mode)
- `mie`: only bits `{MEIE[11], MTIE[7], MSIE[3]}` → mask `0x00000888`
- `mcause`, `mepc`, `mtval`, `mscratch`: fully writable

### Anti-Patterns

- ❌ Reading CSR in EX but writing in WB without forwarding — stale read if back-to-back CSR instructions.
- ❌ Allowing CSR write when `exc_valid_W = 1` — corrupts machine state.
- ❌ Forgetting `mstatus` side effects on trap entry: `MIE → MPIE`, then `MIE ← 0`.

---

## Skill 6 — AXI-Stream Handshake Discipline (PBDE-Specific)

**Rule**: AXI-Stream handshake is `tvalid` / `tready` / `tlast`. A transfer occurs if and only if `tvalid & tready` on the rising clock edge. Violating handshake rules causes silent data loss or duplication.

### Mandatory Rules

| Rule | Description |
|------|-------------|
| **tvalid must not depend on tready** | A source asserts `tvalid` when it has data. It must NOT wait for `tready` before asserting `tvalid`. Deadlock otherwise. |
| **tvalid must hold until accepted** | Once `tvalid` is asserted, it must remain high (with stable `tdata`) until `tready` is seen. Dropping `tvalid` before handshake = lost beat. |
| **tlast marks final beat** | `drain_engine` must assert `tlast` on exactly the last beat of a 4KB drain (beat 31 of 32 for 128-bit width). |
| **Backpressure stalls, not drops** | If AES deasserts `tready`, `drain_engine` holds its current beat. Buffer B continues filling independently — this is the ping-pong advantage. |

### PBDE Data Path Widths

- AXI-Stream width: 128 bits (16 bytes per beat)
- 4KB buffer = 4096 / 16 = **256 beats** per buffer drain
- Each 512B packet = 32 beats of input

### Verification Check

In ILA or simulation: count beats between `tvalid & tready` assertions during a drain. Must equal exactly `drain_length / 16`. `tlast` must pulse high on the final beat only.

---

## Skill 7 — Clock Gating Safety (PBDE-Specific)

**Rule**: Coarse-grained clock gating must be provably glitch-free and must never gate the clock while the AES pipeline has in-flight data.

### Safe Gating Policy

```verilog
// clk_gate_ctrl.v — synchronous, registered enable
wire gate_request = ~drain_active & ~bufA_has_data & ~bufB_has_data & ~aes_inflight;
reg clk_en_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        clk_en_r <= 1'b1;        // Default: clock ON after reset
    else if (gate_request & hysteresis_done)
        clk_en_r <= 1'b0;        // Gate only when truly idle + hysteresis expired
    else if (~gate_request)
        clk_en_r <= 1'b1;        // Ungate immediately when work appears
end

// BUFGCE instantiation
BUFGCE u_aes_clk (.I(sys_clk), .CE(clk_en_r), .O(aes_clk));
```

### Hysteresis

After ungating, hold `clk_en = 1` for a minimum of **10 µs** (configurable via AXI-Lite `timeout_us` register). This prevents rapid on/off chatter during sparse packet arrival. Implement as a down-counter loaded on ungate, blocking re-gate until zero.

### Anti-Patterns

- ❌ Combinational `clk_en` — glitches on the clock enable cause metastability inside the AES core.
- ❌ Gating while `aes_inflight > 0` — AES has 21-cycle latency; data in the pipeline is lost if clock stops.
- ❌ Using `BUFHCE` without verifying placement — `BUFGCE` is safer for initial bring-up; `BUFHCE` is a later optimization.

---

## Skill 8 — Verification Methodology

**Rule**: Every RTL change must be verified at three levels: (1) signal-level waveform check, (2) instruction-level trace comparison, (3) regression against existing passing tests.

### RISCFORGE Verification Stack

| Level | Tool | What It Catches |
|-------|------|-----------------|
| Elaboration | `iverilog -g2012` | Port mismatches, undeclared nets, syntax errors |
| Waveform | GTKWave | Timing bugs, flush/stall misorder, missing propagation |
| Golden reference | Spike (`--isa=rv32i -l`) | Functional correctness vs. ISA spec |
| Trace diff | `compare_traces.py` | Commit-by-commit PC + rd + value comparison |
| Regression | `run_test.sh` on all T*.S files | Non-regression of earlier phases |

### PBDE Verification Stack

| Level | Tool | What It Catches |
|-------|------|-----------------|
| RTL sim | Icarus / Vivado xsim | Functional correctness of ping-pong + drain |
| ILA | Vivado Hardware Manager | Real-hardware handshake, gating transitions |
| Throughput | `benchmark.py` on PYNQ | Performance regression |
| Power | `measure_power.py` + XADC | Gating effectiveness |

### Before Merging Any Change

- [ ] `iverilog` elaboration: zero errors, zero undeclared-net warnings
- [ ] Bubble sort regression: identical register dump as baseline
- [ ] New test for the new feature: passes with expected waveform
- [ ] No existing test regressed

---

## Skill 9 — Integration Partitioning & Port Contracts

**Rule**: Modules communicate through well-defined port contracts. `top.v` (or the block design) is the only place where modules connect. No module may reach into another module's internals.

### RISCFORGE Module Boundaries

```
top.v
 ├── fetch_cycle    (IF stage + IF/ID reg)
 ├── decode_cycle   (ID stage + ID/EX reg)
 ├── execute_cycle  (EX stage + EX/MEM reg)
 ├── memory_cycle   (MEM stage + MEM/WB reg)
 ├── writeback_cycle (WB mux)
 ├── Control_Unit_Top (decode control)
 ├── hazard_unit     (forwarding + stall + flush)
 ├── csr_regfile     (CSR storage, passive)
 ├── PC              (program counter register)
 └── [trap commit logic is combinational in top.v, NOT a separate module]
```

### PBDE Module Boundaries

```
Block Design (Vivado)
 ├── AXI DMA (MM2S + S2MM)
 ├── smart_pingpong   (A/B BRAM fill logic)
 ├── drain_engine     (BRAM read + AXI-Stream emit)
 ├── AES_IP           (existing validated core)
 ├── clk_gate_ctrl    (gating policy + BUFGCE)
 ├── output_fifo      (skid buffer, AES out → S2MM)
 └── AXI-Lite control (register map: 0x00–0x14)
```

### Port Contract Rules

1. Every port has a comment: `// [direction] [width] — purpose`
2. Unused outputs are left unconnected with a comment `// UNUSED`
3. Unused inputs are tied to a constant with a comment: `.port(32'h0) // PLACEHOLDER Phase N`
4. When a module's port list changes, update `top.v` instantiation **in the same commit**

---

## Skill 10 — Address Map & Memory Discipline

**Rule**: Every byte in the address space has a defined owner. Accesses outside defined regions must produce a bus error or be silently ignored (documented which). Never leave address ranges undefined.

### RISCFORGE Address Map (Bare-Metal C Target)

| Base | End | Size | Owner | Access |
|------|-----|------|-------|--------|
| `0x0000_0000` | `0x0000_FFFF` | 64 KB | RAM (instr + data + stack) | RW |
| `0x0200_0000` | `0x0200_FFFF` | 64 KB | CLINT (mtime, mtimecmp, msip) | RW |
| `0x1000_0000` | `0x1000_000F` | 16 B | UART (TX/RX) | RW |

### PBDE Register Map (AXI-Lite)

| Offset | Name | Width | Access | Description |
|--------|------|-------|--------|-------------|
| 0x00 | control | 32 | RW | `[0]` enable ping-pong, `[1]` enable gating |
| 0x04 | timeout_us | 32 | RW | Hysteresis timeout in microseconds |
| 0x08 | occupancy_A | 32 | RO | Current fill level of buffer A |
| 0x0C | occupancy_B | 32 | RO | Current fill level of buffer B |
| 0x10 | drain_length | 32 | RW | Drain burst length in bytes |
| 0x14 | status | 32 | RO | `[0]` draining_A, `[1]` draining_B, `[2]` idle |

### Linker Script Alignment (RISCFORGE)

```ld
MEMORY {
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}
SECTIONS {
    .text   : { *(.text.init) *(.text) } > RAM
    .rodata : { *(.rodata) } > RAM
    .data   : { *(.data) } > RAM
    .bss    : { *(.bss) *(COMMON) } > RAM
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
```

Boot code must: `la sp, _stack_top` then `csrw mtvec, _trap_handler` before calling `main`.

---

## Skill 11 — Signal Naming & Coding Conventions

**Rule**: Consistent naming prevents wiring bugs — the most common class of RTL errors.

### RISCFORGE Naming Convention

| Suffix | Meaning | Example |
|--------|---------|---------|
| `_F` | IF stage | `PCF`, `InstrF` |
| `_D` | ID stage | `InstrD`, `valid_D`, `PCD` |
| `_E` | EX stage | `ALU_ResultE`, `PCE`, `valid_E` |
| `_M` | MEM stage | `ALU_ResultM`, `PC_M`, `valid_M` |
| `_W` | WB stage | `ResultW`, `PC_W`, `valid_W` |
| `_raw` | Pre-gating value | `RegWriteW_raw` |
| `_gated` | Post-gating value | `RegWriteW_gated` |
| `exc_` | Exception sideband | `exc_valid_E`, `exc_cause_M` |
| `wb_*_commit` | WB-stage commit pulse | `wb_trap_commit`, `wb_mret_commit` |

### PBDE Naming Convention

| Prefix/Suffix | Meaning | Example |
|---------------|---------|---------|
| `buf_a_*` / `buf_b_*` | Buffer A/B signals | `buf_a_full`, `buf_b_wr_ptr` |
| `drain_*` | Drain engine signals | `drain_active`, `drain_beat_cnt` |
| `aes_s_*` | AES input stream | `aes_s_axis_tvalid` |
| `aes_m_*` | AES output stream | `aes_m_axis_tready` |
| `clk_en` | Clock enable to BUFGCE | `clk_en_r` (registered) |

### Coding Rules (Both Projects)

1. **No latches** — every `always @(*)` block must have a default assignment or complete `case`/`if-else` coverage.
2. **No multi-driven nets** — only one `always` block or one `assign` drives a given signal.
3. **Use `always_ff` / `always_comb`** in SystemVerilog files; `always @(posedge clk)` / `always @(*)` in Verilog files. Do not mix.
4. **Parameters over hardcoded widths** — `parameter DATA_W = 128;` not `[127:0]` scattered everywhere.
5. **One module per file** — filename matches module name exactly.

---

## Skill 12 — Risk-Aware Phased Delivery

**Rule**: Hardware projects fail when too many untested changes accumulate. Each phase must be independently testable and must not break earlier phases.

### RISCFORGE Phase Gate Checklist

| Phase | Gate Criteria | Risk if Skipped |
|-------|--------------|-----------------|
| 0: Bug fixes | `iverilog` clean + bubble sort passes | Everything else fails to elaborate |
| 1: Pipeline infra | Valid bits propagate, PC reaches WB, flush works | Traps fire on wrong instruction or wrong PC |
| 2: CSR cleanup | All 6 CSR instructions read/write correctly | Trap entry writes garbage to `mepc`/`mcause` |
| 3: Exception detect | `exc_valid` + `exc_cause` correct at each stage, side effects gated | Silent memory corruption on misaligned stores |
| 4: Trap commit | ECALL → handler → MRET → resume | Cannot run any trap handler |
| 5: MRET | `mstatus` restored, PC returns to `mepc` | Interrupts stay permanently disabled after first trap |
| 6: Interrupts | Timer fires, handler runs, `mret` resumes | No async event support, no bare-metal C timer |
| 7: Memory system | Unified address space, `$readmemh`, linker script | Cannot load C programs |

### PBDE Phase Gate Checklist

| Day | Gate Criteria | Risk if Skipped |
|-----|--------------|-----------------|
| 1 | Spec + register map signed off | Integration mismatches on Day 6 |
| 2–3 | Ping-pong fill sim passes | No aggregation — AES gets raw small packets |
| 4 | Drain + TLAST correct in sim | Data corruption or AES hang on wrong packet boundaries |
| 5 | Output FIFO + gating sim passes | Backpressure stalls entire datapath; gating cuts clock mid-computation |
| 6 | Bitstream builds, ILA captures work | No hardware validation possible |
| 8 | Timeout + hysteresis validated | Sparse traffic never drains; gating chatters |
| 10 | 100K-packet stability test passes | Demo fails during presentation |

### Escalation Rules

- If any phase gate fails after 2 attempts → stop, re-read the spec, and re-derive the signal flow from scratch. Do not patch forward.
- If integration between Member R and Member V artifacts fails on Day 6 → fall back to register-level `clk_en` emulation and document the trade-off.
- If `iverilog` elaboration produces port mismatch errors → fix the port list first, then re-run. Never comment out ports to "get it to compile."

---

## Quick-Reference: Which Skills Apply Where

| Task | Skills to Load |
|------|----------------|
| Adding a new pipeline signal (RISCFORGE) | 1, 2, 3, 9, 11 |
| Implementing exception detection (RISCFORGE) | 1, 3, 4, 8 |
| Writing CSR instruction logic (RISCFORGE) | 5, 4, 8 |
| Building `drain_engine.v` (PBDE) | 1, 6, 9, 11 |
| Implementing clock gating (PBDE) | 7, 6, 8 |
| Integrating into `top.v` or block design | 9, 10, 11, 12 |
| Writing or running tests | 8, 12 |
| Starting any new phase | 1, 12 |

---

## Canonical References

| Resource | Use For |
|----------|---------|
| RISC-V Privileged Spec v1.12 (§3 Machine-Level ISA) | CSR addresses, `mcause` codes, `mstatus` bit fields, trap entry/exit rules |
| RISC-V Unprivileged Spec v20191213 (§2.8 CSR Instructions) | CSRRW/RS/RC semantics, zero-register special cases |
| ARM AMBA AXI-Stream Protocol Spec (IHI 0051B) | `tvalid`/`tready`/`tlast` handshake rules |
| Xilinx UG472 (7 Series Clocking Resources) | BUFGCE/BUFHCE usage, clock enable timing |
| Xilinx UG585 (Zynq-7000 TRM) | PS-PL interface, AXI interconnect, DMA |
| Patterson & Hennessy (COD, RISC-V Edition) Ch. 4 | 5-stage pipeline hazards, forwarding, stalls |

> **Final Rule**: When in doubt, re-read the relevant spec section. Never guess at CSR bit positions, AXI handshake timing, or exception cause codes. A single wrong bit in `mstatus` or a single dropped `tready` cycle can cause hours of debug.
