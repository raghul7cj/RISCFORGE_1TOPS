# IRQ Integration Plan — EX-Stage Acceptance into WB-Stage Commit

## Context & Goal

The current design has **no live interrupt path** — `irq_valid_i` and `irq_id_i` are tied to `1'b0`/`31'd0` in `top.v`, and `wb_trap_mret_commit_controller` already has dead logic for `irq_commit` at the WB stage.

The goal is to **move interrupt acceptance upstream to the Execute (EX) stage**, accept it only when the current instruction has no locally-detected exception, flush IF and ID immediately on acceptance, and then let the already-accepted "IRQ bubble" ride the pipeline naturally to the WB commit controller — exactly the same path as an exception already does.

---

## Design Rules (non-negotiable)

| Rule | Reason |
|---|---|
| Accept IRQ at **EX** only, not at WB | Gives two pipeline stages of draining time before commit |
| **Local exception priority** — if `new_exc_valid_E` fires in the same EX cycle, IRQ is blocked | Exceptions are precise; the faulting instruction must be serviced first |
| **Incoming (from-ID) exception passthrough** — if `exc_valid_E` is already set when the instruction enters EX, we still let it through; IRQ is only blocked when we detect a *new local* exception this cycle | Avoids killing already-precise exception state |
| On IRQ acceptance → **flush IF (F) and ID (D) immediately** | Kills the two speculative instructions behind the accepted one |
| IRQ acceptance result is encoded as a new `exc_valid` bundle in the EX/MEM register with `exc_cause` = IRQ ID and `trap_is_interrupt` flag set | Reuses the existing exception propagation datapath end-to-end |
| WB commit controller **removes its own local `irq_commit` logic** and simply acts on whatever arrives as `exc_valid_W` + `trap_is_interrupt_W` | Single commit point; no duplicate state |

---

## Step-by-Step Breakdown

### Step 1 — Surface CSR Interrupt Enables to `top.v`

**Where:** `csr_regfile.v` → `top.v`

The CSR file already outputs `mie_out_o`, `mip_out_o`, and `mstatus_mie_out_o`. These are currently unconnected in `top.v`.

**What to wire:**

```
wire [31:0] csr_mie_sb;        // mie register
wire [31:0] csr_mip_sb;        // mip (timer/ext assembled combinationally)
wire        csr_mstatus_mie_sb; // mstatus.MIE bit
```

Connect these from `csr_regfile` instance outputs `mie_out_o`, `mip_out_o`, `mstatus_mie_out_o` in `top.v`. These are already being driven by the CSR file — they just need wires declared and connected.

**No changes needed inside `csr_regfile.v`.**

---

### Step 2 — Compute `irq_pending` and `irq_id` in `top.v` (combinationally)

**Where:** `top.v` (new combinational logic block)

This is the standard RISC-V M-mode interrupt qualification:

```
irq_pending = mstatus.MIE AND (
                (mie[7]  AND mip[7])   // MTIP — timer
              | (mie[11] AND mip[11])  // MEIP — external
              | (mie[3]  AND mip[3])   // MSIP — software
              )

irq_id[30:0] = priority-selected cause code
               (MEIP=11, MTIP=7, MSIP=3  — standard M-mode priority)
```

Use a simple priority chain:

```verilog
wire irq_pending;
wire [30:0] irq_id;

wire meip = csr_mie_sb[11] & csr_mip_sb[11];
wire mtip = csr_mie_sb[7]  & csr_mip_sb[7];
wire msip = csr_mie_sb[3]  & csr_mip_sb[3];

assign irq_pending = csr_mstatus_mie_sb & (meip | mtip | msip);
assign irq_id      = meip ? 31'd11 :
                     mtip ? 31'd7  :
                     msip ? 31'd3  :
                            31'd0;
```

Route `irq_pending` and `irq_id` as new inputs into `execute_cycle`.

---

### Step 3 — Add IRQ Acceptance Logic to `execute_cycle.v`

**Where:** `execute_cycle.v` — new input ports + new combinational block + pipeline register changes

#### 3a. New Input Ports

```verilog
input  wire        irq_pending_i,
input  wire [30:0] irq_id_i,
```

#### 3b. IRQ Acceptance Combinational Logic

The key decision: **accept IRQ only if no new local exception is being raised this cycle**.

```verilog
// Accept IRQ only if valid instruction, no NEW local exception this cycle.
// Incoming exc_valid_E (from ID) is not a blocker — we overwrite it.
wire irq_accept_E = valid_E & irq_pending_i & ~new_exc_valid_E;
```

`new_exc_valid_E` is already computed (misaligned branch target detection). This is the **local exception**. If `new_exc_valid_E` is 0, the IRQ wins. If it fires, the local exception wins and IRQ is blocked.

> **Note on incoming `exc_valid_E`:** The design intentionally allows overwrite. If an instruction arrived from ID with an exception already set (e.g., illegal instruction from decode), and IRQ also fires at the same EX cycle, the IRQ is accepted and overwrites the incoming exception. This is safe because the instruction with that prior exception hasn't committed yet — and the IRQ vector will be taken instead.

#### 3c. Compute the Final Exception Bundle at EX Egress

Replace the existing `next_exc_*` assignments with a three-way priority:

```
Priority 1: new local exception (new_exc_valid_E) — misaligned branch target
Priority 2: irq_accept_E                           — IRQ wins if no local exc
Priority 3: exc_valid_E propagated from ID         — passthrough
```

```verilog
assign next_exc_valid_E = new_exc_valid_E | irq_accept_E | exc_valid_E;

assign next_exc_cause_E = new_exc_valid_E ? {1'b0, 4'b0, new_exc_cause_E} :
                          irq_accept_E    ? irq_id_i[4:0]  /* cause code */ :
                                            exc_cause_E;

assign next_exc_tval_E  = new_exc_valid_E ? new_exc_tval_E :
                          irq_accept_E    ? 32'h0 :
                                            exc_tval_E;

assign next_exc_pc_E    = new_exc_valid_E ? new_exc_pc_E :
                          irq_accept_E    ? PCE :          /* mepc = this PC */
                                            exc_pc_E;
```

#### 3d. Add `trap_is_interrupt` propagation register

Add a new 1-bit field `is_interrupt_E` to carry forward whether this exception bundle is from an IRQ:

```verilog
reg is_interrupt_r;   // new EX/MEM pipeline register bit
```

In the reset/flush/stall/normal clause of the always block:
- reset / FlushM → `is_interrupt_r <= 1'b0`
- StallM → `is_interrupt_r <= is_interrupt_r`
- normal → `is_interrupt_r <= irq_accept_E & ~new_exc_valid_E`

Add output `is_interrupt_M` and wire it through MEM → WB → WB commit controller.

> **Why not reuse `exc_cause`'s MSB?** Keeping it a separate flag maintains clarity and avoids touching the 5-bit `exc_cause` bus width across all stages.

---

### Step 4 — Flush IF and ID on IRQ Accept in `execute_cycle.v`

**Where:** New output from `execute_cycle.v`; consumed by the hazard unit / flush demux in `top.v`.

When `irq_accept_E` is asserted:
- **Flush ID (FlushD)** — kill the instruction in the ID/EX register
- **Flush IF (FlushF)** — kill the instruction being fetched / held in IF/ID

These are a **separate flush event** from the branch redirect (`PCSrcE`) and the WB trap redirect (`wb_trap_redirect`).

#### Option — New output wire from EX:

```verilog
output wire irq_flush_frontend_o,  // new output port on execute_cycle
assign irq_flush_frontend_o = irq_accept_E;
```

In `top.v`, `OR` this into the existing `FlushD` and `FlushF` (StallF) signals:

```verilog
assign FlushD_final = FlushD | irq_flush_frontend_o;
assign FlushF_final = FlushF | irq_flush_frontend_o;
```

Pass `FlushD_final`/`FlushF_final` to the fetch and decode stages instead of the bare hazard unit outputs.

> **Key point:** Do NOT flush EX or MEM here. The instruction in EX is the one that accepted the IRQ — it needs to complete its EX→MEM→WB journey so the IRQ can be committed at WB. The instructions *behind* it (IF/ID) are the speculative ones that need to die.

---

### Step 5 — Thread `is_interrupt` Through MEM → WB

**Where:** `memory_cycle.v` and its WB-side register

`memory_cycle.v` already passes `exc_valid`, `exc_cause`, `exc_tval`, `exc_pc`, and `is_mret` from MEM to WB via its pipeline register. Add one more field:

- New input: `is_interrupt_M`
- New output: `is_interrupt_W`
- New MEM/WB pipeline register bit: `is_interrupt_r`

Same flush/stall/normal treatment as the other exception fields.

---

### Step 6 — Update `wb_trap_mret_commit_controller`

**Where:** `wb_trap_mret_commit_controller.v`

#### 6a. Remove the old `irq_commit` logic

Delete:
```verilog
input  wire        irq_valid_i,
input  wire [30:0] irq_id_i,
assign irq_commit  = valid_W & irq_valid_i & ~exc_valid_W & ~is_mret_W;
```

The controller no longer samples live IRQ signals. It only acts on what the pipeline has already committed to.

#### 6b. Add `is_interrupt_W` input

```verilog
input  wire        is_interrupt_W,
```

#### 6c. Update `trap_commit` and redirect logic

```verilog
assign trap_commit = valid_W & exc_valid_W;   // same as before

// Distinguish exception vs interrupt at commit
assign trap_target_o = trap_commit ? {mtvec_i[31:2], 2'b00} : {mepc_i[31:2], 2'b00};
// (mret redirect path unchanged)

assign trap_is_interrupt_o = is_interrupt_W & exc_valid_W;  // only meaningful when trap commits
assign trap_cause_o        = {26'b0, exc_cause_W};          // cause code already correct in pipeline
```

`trap_pc_o` (→ `mepc`) already uses `exc_pc_W`, which we set to `PCE` when accepting the IRQ in Step 3c. ✓

#### 6d. `irq_commit` → gone; `trap_commit` now covers both cases

`wb_trap_redirect_o` and `flush_pipeline_onehot_o` remain driven by `trap_commit | mret_commit` — no change needed.

---

### Step 7 — Update `top.v` Wiring

A summary of all new connections:

| Signal | From | To |
|---|---|---|
| `csr_mie_sb` | `csr_regfile.mie_out_o` | Step 2 logic |
| `csr_mip_sb` | `csr_regfile.mip_out_o` | Step 2 logic |
| `csr_mstatus_mie_sb` | `csr_regfile.mstatus_mie_out_o` | Step 2 logic |
| `irq_pending` | Step 2 combinational | `execute_cycle.irq_pending_i` |
| `irq_id[30:0]` | Step 2 combinational | `execute_cycle.irq_id_i` |
| `irq_flush_frontend_o` | `execute_cycle` | OR into `FlushD`, `FlushF` |
| `is_interrupt_M` | `execute_cycle.is_interrupt_M` | `memory_cycle` input |
| `is_interrupt_W` | `memory_cycle.is_interrupt_W` | `wb_trap_mret_commit_controller` |
| `irq_valid_i` / `irq_id_i` on `wb_commit` | — | **Remove** these ports and tie-offs |

---

## Data Flow Summary (end-to-end)

```
External interrupt line (timer_intr_i / ext_intr_i)
        │
        ▼
csr_regfile ──► mip_out_o, mie_out_o, mstatus_mie_out_o
        │
        ▼
top.v irq_pending / irq_id (combinational)
        │
        ▼
execute_cycle  [irq_accept_E = valid_E & irq_pending & ~new_exc_valid_E]
   │                │
   │                ├── next_exc_valid_E   = 1
   │                ├── next_exc_pc_E      = PCE        (→ mepc)
   │                ├── next_exc_cause_E   = irq_id[4:0]
   │                └── is_interrupt_r     = 1
   │
   ▼  irq_flush_frontend_o = 1
FlushD ──► kills ID/EX register
FlushF ──► kills IF/ID register
   │
   ▼  (EX/MEM pipeline register latches the accepted-IRQ bubble)
memory_cycle   [exc_valid_M=1, is_interrupt_M=1, exc_pc_M=PCE_accepted]
        │
        ▼  (MEM/WB pipeline register)
writeback  [exc_valid_W=1, is_interrupt_W=1, exc_pc_W]
        │
        ▼
wb_trap_mret_commit_controller
   trap_commit = valid_W & exc_valid_W  → 1
   trap_is_interrupt_o = is_interrupt_W → 1
   trap_cause_o = irq_id_code
   trap_pc_o    = exc_pc_W              (→ mepc in CSR file)
   wb_trap_redirect_o = 1
   trap_target_o = mtvec                (→ redirect to handler)
        │
        ▼
csr_regfile  [mepc ← exc_pc_W, mcause ← {1, irq_id}, mstatus.MIE ← 0]
fetch_cycle  [PC ← mtvec — jumps to ISR]
```

---

## File Change Map

| File | Nature of Change |
|---|---|
| `top.v` | Wire `mie/mip/mstatus_mie` sidebands; add `irq_pending/id` logic; new `is_interrupt_M/W` wires; OR `irq_flush_frontend` into FlushD/FlushF; remove `irq_valid_i`/`irq_id_i` tie-offs on `wb_commit` |
| `execute_cycle.v` | Add `irq_pending_i`, `irq_id_i` inputs; `irq_accept_E` wire; update `next_exc_*` priority chain; add `is_interrupt_r` register + `is_interrupt_M` output; add `irq_flush_frontend_o` output |
| `memory_cycle.v` | Pass `is_interrupt` through MEM/WB register (new input + output + reg) |
| `wb_trap_mret_commit_controller.v` | Remove `irq_valid_i`, `irq_id_i` ports + dead `irq_commit` logic; add `is_interrupt_W` input; update `trap_is_interrupt_o` and `trap_cause_o` assignments |
| `csr_regfile.v` | **No changes needed** — outputs already exist |
| `fetch_cycle.v` / `decode_cycle.v` | **No changes needed** — they already respond to `FlushD`/`FlushF` |
| `hazard_unit.v` | Likely **no changes** — FlushD/FlushF OR is done in `top.v`; but review if hazard unit gates these |

---

## Important Corner Cases to Verify in Simulation

1. **IRQ fires same cycle as a branch taken (`PCSrcE=1`)** — Both `irq_accept_E` and `irq_flush_frontend` should fire. The branch-taken redirect kills the wrong-path fetch, and IRQ additionally kills ID. Verify no double-flush conflict.

2. **IRQ fires same cycle as local exception (`new_exc_valid_E=1`)** — `irq_accept_E` must be 0. Only the local exception bundle propagates. IRQ is deferred until the exception instruction retires and `mstatus.MIE` is restored by MRET.

3. **IRQ fires while MUL/DIV is stalling (`stallMUL=1`)** — The EX stage is stalled (instruction held). `irq_accept_E` fires on the cycle EX is not stalled. Verify the stall interaction: don't accept while stalled (instruction not advancing), or handle that the same instruction might see `irq_pending` for multiple cycles.

4. **mstatus.MIE = 0** — `irq_pending` is 0 by construction (gated by `csr_mstatus_mie_sb`). No interrupt accepted.

5. **Back-to-back interrupts** — After the first IRQ commits at WB and `mstatus.MIE` is cleared, a second IRQ cannot be accepted. Only after MRET restores MIE.

---

## Ordering of Implementation Work

1. Step 1+2 first (CSR sideband wiring + `irq_pending/id` in top) — purely additive, zero risk
2. Step 3 (EX stage changes) — core logic, test in isolation with a forced `irq_pending`
3. Step 4 (frontend flush) — connect and verify with waveform that IF/ID are killed correctly
4. Step 5 (MEM threading) — mechanical port addition, low risk
5. Step 6 (WB controller cleanup) — simplification; verify `trap_is_interrupt_o` correctness
6. Step 7 (top.v final wiring) — integration pass; run full regression
