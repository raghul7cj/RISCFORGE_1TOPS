# Exception Flow Cycle-Accurate Diagrams & Signal Maps

## DIAGRAM 1: Complete Exception & Flush Signal Flow (Single Exception Scenario)

This diagram shows how all signals interact from detection through CSR update:

```
                    ┌─────────────────────────────────────────────────────┐
                    │      EXCEPTION DETECTION (Combinational)             │
                    └─────────────────────────────────────────────────────┘
                                        │
        ┌───────────────────────┬───────┘───────┬──────────────────────┐
        │                       │               │                      │
        ▼                       ▼               ▼                      ▼
     IF Stage              ID Stage         EX Stage            MEM Stage
   (misalign chk)      (illegal instr)      (N/A for            (load/store
                       (ecall/ebreak)       RV32I)              misalign)
        │                       │               │                      │
        └──────────┬────────────┴───────────────┴──────────────────────┘
                   │
        ┌──────────▼──────────┐
        │  Exception Sideband  │ (exc_valid, exc_cause, exc_pc, exc_tval)
        │   Propagation Path   │
        └──────────┬──────────┘
                   │
        IF/ID ─────┼─────► ID/EX ─────┼─────► EX/MEM ─────┼─────► MEM/WB
        Register   │       Register   │       Register   │       Register
                   │                  │                  │
                ┌──▼───┐          ┌───▼──┐            ┌──▼───┐
                │Merge  │          │Merge │            │Merge │
                │(IF|ID)│          │Pass  │            │(merge)│
                └──┬───┘          └───┬──┘            └──┬───┘
                   │                  │                  │
        ┌──────────▼──────────────────▼──────────────────▼────────────┐
        │                  CONTINUOUS FLUSH PHASE                     │
        │  (While exc_valid_E=1 or exc_valid_M=1, flush younger stages)│
        │                                                               │
        │  exc_inflight_E = valid_E & exc_valid_E                    │
        │  exc_inflight_M = valid_M & exc_valid_M                    │
        │                                                               │
        │  Priority Mux:                                              │
        │    FlushD = PCSrcE | exc_inflight_E | exc_inflight_M | ... │
        │    FlushE = lwstall | PCSrcE | exc_inflight_M | ...        │
        │    FlushM = wb_redirect | ...                               │
        │    FlushW = wb_redirect | ...                               │
        └──────────┬─────────────────────────────────────────────────┘
                   │
        ┌──────────▼──────────────────────────────────────────┐
        │         WRITEBACK STAGE (Synchronous FIRST,          │
        │         Combinational COMMIT LOGIC)                  │
        │                                                      │
        │  Trap Commit Condition:                            │
        │  trap_commit = valid_W & exc_valid_W               │
        │                                                      │
        │  WB Trap Commit Controller Outputs:               │
        │  • wb_trap_redirect_o = trap_commit | mret_commit  │
        │  • trap_target_o = mtvec (from CSR sideband)       │
        │  • trap_valid_o = trap_commit  ──────────┐         │
        │  • trap_cause_o = {interrupt, cause[30:0]}        │
        │  • trap_pc_o = exc_pc_W (for mepc)               │
        │  • trap_addr_o = exc_tval_W (for mtval)          │
        │  • trap_addr_valid_o = indicates mtval validity    │
        │  • trap_is_interrupt_o = exception vs interrupt    │
        │  • flush_pipeline_onehot_o = 4'b1111             │
        │  • mret_commit_o = mret_commit  ─────────┐        │
        └──────────┬──────────────────────────────┼─────────┘
                   │                              │
                   │         (on clock edge)      │
        ┌──────────▼──────────────────────────────▼─────────┐
        │      CSR REGFILE (Synchronous Write)             │
        │                                                    │
        │  Port C (Trap Entry) — Highest Priority:         │
        │  ├── csr_write_en_exc_i = trap_valid_o           │
        │  │                                                 │
        │  ├── Write MEPC (0x341) ← trap_pc_o              │
        │  ├── Write MCAUSE (0x342) ← {trap_is_interrupt_o,│
        │  │                            trap_cause_o}       │
        │  ├── Write MTVAL (0x343) ← trap_addr_o (if valid)│
        │  └── Write MSTATUS (0x300, read-modify-write):   │
        │      ├─ MIE (bit 3) ← 0 (disable interrupts)     │
        │      ├─ MPIE (bit 7) ← old MIE (save state)      │
        │      └─ MPP (bits 12:11) ← 2'b11 (M-mode)       │
        │                                                    │
        │  Port D (MRET Restore) — IMPLEMENTED:            │
        │  ├── mret_valid_i = mret_commit_o (from WB ctrl) │
        │  └── On MRET / MRET-commit:                       │
        │      ├─ MIE ← MPIE                               │
        │      ├─ MPIE ← 1'b1                              │
        │      └─ MPP ← 2'b11                              │
        └──────────┬──────────────────────────────────────┘
                   │
        ┌──────────▼──────────────────────────────────────┐
        │     FETCH STAGE (PC Redirect on Next Cycle)      │
        │                                                   │
        │  PC Selection Mux (Priority):                   │
        │  1. (highest) wb_trap_redirect ? trap_target   │
        │  2.                PCSrcE ? PCTargetE          │
        │  3. (lowest)                PCPlus4F          │
        │                                                   │
        │  On trap_commit=1 or mret_commit=1:             │
        │  • PC ← trap_target (= mtvec for trap)         │
        │  •           or mepc for mret                   │
        └──────────┬──────────────────────────────────────┘
                   │
        ┌──────────▼──────────────────────────────────────┐
        │      NEXT CYCLE: Pipeline Execution Resumes      │
        │                                                   │
        │  • All stages empty (FlushD/E/M/W all set)       │
        │  • PC = mtvec.BASE (handler) or mepc (MRET)      │
        │  • Fetch next instruction from new PC             │
        │  • No young instructions committed               │
        └──────────────────────────────────────────────────┘
```

---

## DIAGRAM 2: Hazard Unit & Continuous Flush Logic

```
                 ┌──────────────────────────────────────────────┐
                 │   Hazard Unit Continuous Flush Path          │
                 └──────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
                    ▼               ▼               ▼
            FROM EX STAGE:    FROM MEM STAGE:   FROM WB STAGE:
            • valid_E          • valid_M         • wb_redirect
            • exc_valid_E      • exc_valid_M     • (from trap/mret
                                                     commit logic)

            │                   │                  │
            │ Combinational     │                  │ (combinational)
            │ Merge:            │                  │
            ▼                   ▼                  ▼

    ┌──────────────────┬──────────────────┬────────────────────┐
    │  exc_inflight_E  │  exc_inflight_M  │   wb_redirect      │
    │  = valid_E &     │  = valid_M &     │   = (WB trap or    │
    │    exc_valid_E   │    exc_valid_M   │      MRET commit)  │
    └────────┬─────────┴────────┬─────────┴─────────┬──────────┘
             │                  │                   │
             │                  │                   │
             │    ┌─────────────┴───────────┬───────┘
             │    │  Priority Signal Merge  │
             │    └────────────┬────────────┘
             │                 │
             │                 ▼
    ┌────────────────────────────────────────────────┐
    │         TARGET STAGE FLUSH SIGNALS             │
    ├────────────────────────────────────────────────┤
    │                                                 │
    │  FlushD = PCSrcE | exc_inflight_E             │
    │           | exc_inflight_M | wb_redirect      │
    │           | flush_pipeline_onehot[0]          │
    │                                                 │
    │  → Flush IF/ID register (ID stage victims)    │
    │                                                 │
    ├────────────────────────────────────────────────┤
    │                                                 │
    │  FlushE = lwstall | PCSrcE | csr_stall       │
    │           | exc_inflight_M                     │
    │           | wb_redirect |flush_pipeline_onehot[1]
    │                                                 │
    │  → Flush ID/EX register (EX stage victims)    │
    │                                                 │
    ├────────────────────────────────────────────────┤
    │                                                 │
    │  FlushM = wb_redirect |flush_pipeline_onehot[2]
    │                                                 │
    │  → Flush EX/MEM register (MEM stage victims)  │
    │                                                 │
    ├────────────────────────────────────────────────┤
    │                                                 │
    │  FlushW = wb_redirect | flush_pipeline_onehot[3]
    │                                                 │
    │  → Flush MEM/WB register (WB stage victims)   │
    │                                                 │
    └────────────────────────────────────────────────┘
             │        │        │         │
             │        │        │         │
    Pipeline │        │        │         │ Registers
    Register │        │        │         │ Capture
    Clearing │        │        │         │ & Update
             │        │        │         │
             ▼        ▼        ▼         ▼
    ┌──────────────────────────────────────────────┐
    │  On (posedge clk):                          │
    │                                              │
    │  if (FlushD) valid_D <= 0; // kill IF/ID   │
    │  if (FlushE) valid_E <= 0; // kill ID/EX   │
    │  if (FlushM) valid_M <= 0; // kill EX/MEM  │
    │  if (FlushW) valid_W <= 0; // kill MEM/WB  │
    │                                              │
    │  if (!FlushD && !StallD) {                  │
    │      IF/ID reg <= (updated from IF stage) │
    │  }                                          │
    │                                              │
    └──────────────────────────────────────────────┘
             │
             │ Next cycle
             ▼
    ┌──────────────────────────────────────────────┐
    │  Pipeline continues OR trap entry redirection│
    │  (if wb_redirect asserted, PC redirects too) │
    └──────────────────────────────────────────────┘
```

---

## DIAGRAM 3: Exception Sideband Merging at Each Stage

```
┌─────────────────────────────────────────────────────────────────┐
│           EXCEPTION SIDEBAND MERGING "FIRST WINS"              │
├─────────────────────────────────────────────────────────────────┤

   At Decode (ID stage):
   ─────────────────────
                               IF Exception
                          (from IF/ID register)
                                    │
                         exc_valid_D, exc_cause_D,
                         exc_tval_D, exc_pc_D
                                    │
                         ┌──────────┴───────┐
                         │                  │
                  are_there? ────no───────► Use as-is
                         │
                        yes
                         │
                  ┌──────▼──────┐
                  │ ID-local    │
                  │ exception?  │
                  │ (illegal,   │
                  │  ecall,     │
                  │  ebreak)    │
                  └──────┬──────┘
                         │
          ┌──────────────┼──────────────┐
          │              │              │
         yes             no           (ignored)
          │              │
          ▼              ▼
   ┌─────────────┐ ┌────────────┐
   │Keep IF exc  │ │Pass ID exc │
   │(FirstWins)  │ │(or no exc) │
   └─────┬───────┘ └────────┬───┘
         │                  │
         └──────────┬───────┘
                    │
         next_exc_valid_D = exc_valid_D | new_exc_valid_D
         next_exc_cause_D = exc_valid_D ? exc_cause_D : new_exc_cause_D
         next_exc_tval_D  = exc_valid_D ? exc_tval_D : new_exc_tval_D
         next_exc_pc_D    = exc_valid_D ? exc_pc_D : new_exc_pc_D
                    │
                    ▼
            (on clock edge)
          ID/EX pipeline register
            updates with merged

   At Execute (EX stage):
   ──────────────────────
   • RV32I base: NO exceptions in EX
   • Exception sideband passed through unchanged
   • exc_valid_E ← exc_valid (from ID/EX reg)
   • All exception fields propagate unchanged

   At Memory (MEM stage):
   ─────────────────────
            Propagated Exception
          (from EX/MEM register)
                    │
         exc_valid_M, exc_cause_M, etc.
                    │
          ┌─────────┴────────┐
          │                  │
       are_there? ────no─────► Use as-is
          │
         yes
          │
   ┌──────▼──────────┐
   │MEM-local exc?   │
   │(load/store      │
   │ misalign,       │
   │ access fault)   │
   └────────┬────────┘
            │
    ┌───────┴───────┐
    │               │
   yes              no
    │               │
    ▼               ▼
┌─────────┐   ┌─────────────┐
│Keep     │   │Pass MEM exc │
│Prop exc │   │(or no exc)  │
│(First)  │   └──────┬──────┘
└────┬────┘         │
     └──────┬───────┘
            │
  exc_valid_M_final = exc_valid_M_propagated | exc_valid_mem_local
  (Merge with OR, but first-wins in selector)
            │
            ▼
    (on clock edge)
  MEM/WB pipeline register
    updates with final merged

   At Writeback (WB stage):
   ──────────────────────
   • Exception sideband arrives as:
     - valid_W, exc_valid_W, exc_cause_W, exc_pc_W, exc_tval_W
   • This is the final, resolved exception
   • WB trap commit controller examines exc_valid_W
   • If exc_valid_W = 1, trap_commit = 1
   • CSR Port C receives trap bundle

   ╔════════════════════════════════════════════════════════════╗
   ║ KEY INVARIANT: "FIRST WINS"                              ║
   ║ ─────────────────────────────────────────────────────────║
   ║ If exception detected in stage N, and stage N+k detects  ║
   ║ a different exception, stage N's exception is preserved  ║
   ║ because exc_valid is already set.                        ║
   ║                                                           ║
   ║ This ensures that the most fundamental fault (earliest   ║
   ║ stage) is what the handler sees.                         ║
   ║                                                           ║
   ║ Examples:                                                ║
   ║  • Fetch error (IF) blocks ID-detected illegal instr    ║
   ║  • Illegal instr (ID) blocks MEM-detected misalign     ║
   ║                                                           ║
   ║ When flushed (FlushX=1), exc_valid is CLEARED, so the  ║
   ║ exception is discarded along with the instruction.      ║
   ╚════════════════════════════════════════════════════════════╝
```

---

## DIAGRAM 4: CSR Port Priority & Atomic Trap Entry

```
┌──────────────────────────────────────────────────────────────────┐
│              CSR FILE: Port Write Priority & Atomicity           │
├──────────────────────────────────────────────────────────────────┤

Three write sources compete for access to CSR storage:

Priority Order (Collision Handling):
──────────────────────────────────

   ┌──────────────────────────────────────────────────────────┐
   │ PORT C (TRAP ENTRY) — HIGHEST PRIORITY                │
   │ ────────────────────────────────────────────────────── │
   │ Source: WB trap commit controller                       │
   │ Trigger: csr_write_en_exc_i = trap_valid_o             │
   │                                                           │
   │ Atomic Multi-Register Update (all-or-nothing):        │
   │                                                           │
   │ ┌─────────────────────────────────────────────────────┐ │
   │ │ Register │ Address │ Source         │ On Exception  │ │
   │ │────────────────────────────────────────────────── │ │
   │ │ MEPC     │ 0x341   │ trap_pc_o      │ = PC of fault│ │
   │ │ MCAUSE   │ 0x342   │ {trap_is_int,  │ = {int,cause}│ │
   │ │          │         │  trap_cause_o} │              │ │
   │ │ MTVAL    │ 0x343   │ trap_addr_o    │ = fault addr │ │
   │ │ MSTATUS  │ 0x300   │ RMW masked     │ See below    │ │
   │ └─────────────────────────────────────────────────────┘ │
   │                                                           │
   │ MSTATUS Write Details (Mask: 32'h00001888):          │
   │ ┌─────────────────────────────────────────────────────┐ │
   │ │ Bit  │ Field │ New Value          │ Operation      │ │
   │ ├──────┼───────┼────────────────────┼──────────────┤ │
   │ │  3   │ MIE   │ 1'b0 (disable)     │ = 0          │ │
   │ │  7   │ MPIE  │ old MIE (bit 3)    │ RMW save     │ │
   │ │ 12:11│ MPP   │ 2'b11 (M-mode)     │ = M-mode     │ │
   │ │ others│ ─     │ unchanged          │ mask blocks  │ │
   │ └─────────────────────────────────────────────────────┘ │
   │                                                           │
   │ Happens: On (posedge clk), if trap_valid_o=1        │
   └──────────────────────────────────────────────────────────┘
            │
            │ (overrides Port B if both active)
            │
   ┌────────▼────────────────────────────────────────────────┐
   │ PORT B (CSR INSTRUCTIONS) — MIDDLE PRIORITY           │
   │ ──────────────────────────────────────────────────── │
   │ Source: WB stage CSR instruction (CSRRW, CSRRS, etc) │
   │ Trigger: csr_write_en_normal_i = 1                   │
   │                                                          │
   │ Single Register Write (not atomic):                    │
   │ • Each CSR instruction writes one register             │
   │ • CSR address decoded from instruction                  │
   │ • Data: Computed per CSR opcode (W/S/C variant)       │
   │                                                          │
   │ Happens: On (posedge clk), if csr_write_en_normal=1  │
   │ ⚠️ Skipped if Port C active in same cycle             │
   └──────────────────────────────────────────────────────────┘
            │
            │ (overrides Port A if both active)
            │
   ┌────────▼────────────────────────────────────────────────┐
   │ PORT A (COMBINATIONAL READ) — NO WRITE                │
   │ ──────────────────────────────────────────────────── │
   │ Source: EX stage (CSRR* instruction fetch old value) │
   │                                                          │
   │ • Purely combinational (zero latency)                  │
   │ • Reads current CSR value (before any write)          │
   │ • No conflicts with writes (A is read-only)            │
   │ • Output: csr_rdata_o[31:0]                            │
   └──────────────────────────────────────────────────────────┘

   ╔════════════════════════════════════════════════════════════╗
   ║              COLLISION SCENARIOS                          ║
   ╠════════════════════════════════════════════════════════════╣
   ║                                                             ║
   ║  Scenario 1: Port C active, Port B also active           ║
   ║  ─────────────────────────────────────────────           ║
   ║  → Port C wins (trap entry takes priority)               ║
   ║  → Port B write is dropped (CSR instr delayed)           ║
   ║  → Both fire at edge; trap atomically updates MEPC,      ║
   ║    MCAUSE, MTVAL, MSTATUS                               ║
   ║  → Handler sees consistent CSR state on next read       ║
   ║                                                             ║
   ║  Scenario 2: Port C active, Port A also active          ║
   ║  ──────────────────────────────────────────────         ║
   ║  → Port A reads BEFORE Port C write                      ║
   ║  → EX stage reads "old" CSR value (designs choice)     ║
   ║  → No write conflict (A is read-only)                   ║
   ║                                                             ║
   ║  Scenario 3: Port B writes to MTVEC while trap         ║
   ║  ──────────────────────────────────────────────         ║
   ║  → Port C writes MEPC/MCAUSE/MTVAL/MSTATUS             ║
   ║  → Port B attempts MTVEC write                          ║
   ║  → Port C wins; MTVEC unchanged this cycle             ║
   ║  → Port B write queued (???) → This is a concern!       ║
   ║  → Real solution: Handler must NOT write CSRs while    ║
   ║    exception is in-flight. RV spec says this           ║
   ║                                                             ║
   ╚════════════════════════════════════════════════════════════╝

  ┌────────────────────────────────────────────────────────────┐
  │ PORT D (MRET RESTORE) — IMPLEMENTED                        │
  ├────────────────────────────────────────────────────────────┤
  │                                                              │
  │ Implementation:                                             │
  │   The WB trap/mret commit controller issues a CSR write     │
  │   that updates the `mstatus` fields on MRET commit.         │
  │                                                              │
  │   On MRET commit the following are restored/updated:        │
  │     - MIE  (bit 3) ← MPIE                                   │
  │     - MPIE (bit 7) ← 1'b1                                   │
  │     - MPP  (bits 12:11) ← appropriate value                 │
  │                                                              │
  │   This is performed atomically alongside the WB commit      │
  │   logic and the CSR regfile write path (synchronous).       │
  └────────────────────────────────────────────────────────────┘
```

---

## DIAGRAM 5: Single vs Multiple Exception Paths (Comparison)

```
╔═════════════════════════════════════════════════════════════════╗
║           SINGLE EXCEPTION vs MULTIPLE EXCEPTION               ║
║              (Illustrative Timeline Comparison)                ║
╚═════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────┐
│ CASE 1: SINGLE EXCEPTION (Clean Case)                           │
├─────────────────────────────────────────────────────────────────┤

Time  │ IF/ID    │ ID/EX    │ EX/MEM   │ MEM/WB   │ Hazard Unit
t=1   │ Fetch    │ -        │ -        │ -        │ Normal
      │ Inc@0x00 │          │          │          │ operation
      │ ---      │          │          │          │
      │ v=1      │          │          │          │
      │ exc=0    │          │          │          │
      │          │          │          │          │
t=2   │ Fetch    │ Decode   │ -        │ -        │ Normal
      │ Add@0x04 │ Inc→OK   │          │          │
      │ ---      │ ---      │          │          │
      │ v=1      │ v=1      │          │          │
      │ exc=0    │ exc=0    │          │          │
      │          │          │          │          │
t=3   │ Fetch    │ Decode   │ Execute  │ -        │ Normal
      │ Ill@0x08 │ Add→OK   │ Inc→OK   │          │
      │ ---      │ ---      │ ---      │          │
      │ v=1      │ v=1      │ v=1      │          │
      │ exc=0    │ exc=0    │ exc=0    │          │
      │          │          │          │          │
t=4   │ Fetch    │ Decode   │ Execute  │ Memory   │ Normal
      │ OK@0x0C  │ Ill→ILL! │ Add→OK   │ Inc→OK   │
      │ ---      │ ---      │ ---      │ ---      │
      │ v=1      │ v=1      │ v=1      │ v=1      │
      │ exc=0    │ exc=1    │ exc=0    │ exc=0    │
      │          │ cau=2    │          │          │
      │          │ (illegal)│          │          │
      │          │          │          │          │ ✓ FlushD=1
      │          │          │          │          │   (exc in ID)
      │          │          │          │          │
t=5   │ <empty>  │ <empty>  │ Execute  │ Memory   │ Continuous
      │ (flushed)│ (flushed)│ Ill→ILL! │ Add→OK   │ flush
      │ ---      │ ---      │ ---      │ ---      │ updates ID/EX
      │ v=0      │ v=0      │ v=1      │ v=1      │
      │ exc=0    │ exc=0    │ exc=1    │ exc=0    │
      │          │          │ cau=2    │          │
      │          │          │          │          │ ✓ FlushE=1
      │          │          │          │          │   (exc in EX)
      │          │          │          │          │
t=6   │ <empty>  │ <empty>  │ <empty>  │ Memory   │ TRAP
      │ (flushed)│ (flushed)│ (flushed)│ Ill→ILL! │ COMMIT
      │ ---      │ ---      │ ---      │ ---      │
      │ v=0      │ v=0      │ v=0      │ v=1      │
      │ exc=0    │ exc=0    │ exc=0    │ exc=1    │ ✓ trap_commit=1
      │          │          │          │ cau=2    │
      │          │          │          │          │
      │          │          │          │ WB Trap  │ ✓ Port C CSR
      │          │          │          │ Trap→PC  │   write
      │          │          │          │ redir    │
      │          │          │          │          │
      │          │          │          │ CSR Upd: │
      │          │          │          │ MEPC←PC  │
      │          │          │          │ MCAUSE←2 │
      │          │          │          │ MSTATUS  │
      │          │          │          │ updated  │

RESULT: Single trap entry point; clean state at WB.

┌─────────────────────────────────────────────────────────────────┐
│ CASE 2: MULTIPLE EXCEPTION (Corner Case)                        │
├─────────────────────────────────────────────────────────────────┤

Time  │ IF/ID    │ ID/EX    │ EX/MEM   │ MEM/WB   │ Hazard Unit
t=1   │ Fetch    │ -        │ -        │ -        │ Normal
      │ LW@0x00  │          │          │          │
      │ ---      │          │          │          │
      │ v=1      │          │          │          │
      │ exc=0    │          │          │          │
      │          │          │          │          │
t=2   │ Fetch    │ Decode   │ -        │ -        │ Normal
      │ Add@0x04 │ LW→OK    │          │          │
      │ ---      │ ---      │          │          │
      │ v=1      │ v=1      │          │          │
      │ exc=0    │ exc=0    │          │          │
      │          │          │          │          │
t=3   │ Fetch    │ Decode   │ Execute  │ -        │ Normal
      │ Ill@0x08 │ Add→OK   │ LW→OK    │          │
      │ ---      │ ---      │ ---      │          │
      │ v=1      │ v=1      │ v=1      │          │
      │ exc=0    │ exc=0    │ exc=0    │          │
      │          │          │          │          │
t=4   │ Fetch    │ Decode   │ Execute  │ Memory   │ CRITICAL:
      │ OK@0x0C  │ Ill→ILL! │ Add→OK   │ LW→BAD!  │ LW detects
      │ ---      │ ---      │ ---      │ ---      │ misalign
      │ v=1      │ v=1      │ v=1      │ v=1      │
      │ exc=0    │ exc=1    │ exc=0    │ exc=1    │ ✓ exc_valid_M=1
      │          │ cau=2    │          │ cau=4    │   (from memory)
      │          │ (illegal)│          │ (misaln) │
      │          │          │          │          │
      │          │          │          │          │ ✓ exc_inflight_M=1
      │          │          │          │          │
      │          │          │          │          │ ✓ FlushD=1
      │          │          │          │          │   (inc to flush ID)
      │          │          │          │          │
      │          │          │          │          │ ✓ FlushE=1
      │          │          │          │          │   (inc to flush EX)
      │          │          │          │          │
t=5   │ <empty>  │ <empty>  │ <empty>  │ Memory   │ Continuous
      │ (flushed)│ (flushed)│ (flushed)│ LW→BAD!  │ flush
      │ ---      │ ---      │ ---      │ ---      │
      │ v=0      │ v=0      │ v=0      │ v=1      │ ID and EX
      │ exc=0    │ exc=0    │ exc=0    │ exc=1    │ NOW CLEARED,
      │          │          │          │ cau=4    │ but Ill
      │          │          │          │          │ exception
      │          │          │          │          │ DISCARDED!
      │          │          │          │          │
      │          │          │          │          │ Add also
      │          │          │          │          │ flushed away
      │          │          │          │          │
t=6   │ <empty>  │ <empty>  │ <empty>  │ Memory   │ TRAP
      │ (flushed)│ (flushed)│ (flushed)│ LW→BAD!  │ COMMIT
      │ ---      │ ---      │ ---      │ ---      │
      │ v=0      │ v=0      │ v=0      │ v=1      │ ✓trap_commit=1
      │ exc=0    │ exc=0    │ exc=0    │ exc=1    │
      │          │          │          │ cau=4    │ Only LW
      │          │          │          │ (misaln) │ exception
      │          │          │          │          │ commits!
      │          │          │          │ CSR Upd: │
      │          │          │          │ MEPC←PC  │ ✓ Port C CSR
      │          │          │          │ MCAUSE←4 │   write
      │          │          │          │ MTVAL←   │   (mepc,
      │          │          │          │  fault   │    mcause,
      │          │          │          │  addr    │    mtval)

RESULT: LW exception (older, in-flight) commits.
        Add exception (younger, flushed) discarded.
        Ill exception (youngest, flushed) discarded.
        Only one trap entry; LW is the culprit.

╔════════════════════════════════════════════════════════════════╗
║ KEY OBSERVATION:                                              ║
║─────────────────────────────────────────────────────────────║
║ When an OLDER instruction has an exception in-flight (MEM), ║
║ ALL younger instructions are continuously flushed, even      ║
║ if they also have exceptions. The oldest exception wins.     ║
║                                                              ║
║ This is achieved by:                                         ║
║ 1. exc_inflight_M = valid_M & exc_valid_M                   ║
║ 2. FlushD, FlushE includes exc_inflight_E, exc_inflight_M  ║
║ 3. Pipeline register updates on each clock, clearing        ║
║    exc_valid for flushed instructions                       ║
║ 4. At WB, only the oldest unflused exception commits        ║
╚════════════════════════════════════════════════════════════════╝
```

---

## DIAGRAM 6: CSR Port C Atomic Update Sequence

```
┌──────────────────────────────────────────────────────────────────┐
│      CSR PORT C TRAP ENTRY UPDATE (Atomic Multi-Register)       │
├──────────────────────────────────────────────────────────────────┤

SCENARIO: Load address misaligned exception at PC 0x00000100
          Bad address: 0x0000064D (odd, triggers misalignment fault)

Before Trap (t=5 state):
  MEPC     = 32'h00000000 (old, stale)
  MCAUSE   = 32'h00000000 (old, stale)
  MTVAL    = 32'h00000000 (old, stale)
  MSTATUS  = 32'h00001800 (example: MIE=0, MPIE=1, MPP=M)

Combinational (t=6 WB stage):
  trap_valid_o         = 1'b1
  trap_cause_o         = 5'd4 (load address misaligned)
  trap_pc_o            = 32'h00000100 (faulting instruction PC)
  trap_addr_o          = 32'h0000064D (bad address from exception)
  trap_addr_valid_o    = 1'b1 (address is meaningful)
  trap_is_interrupt_o  = 1'b0 (exception, not interrupt)

Synchronous (posedge clk, t=6→t=7):

  ┌────────────────────────────────────────────────────┐
  │ CSR File Clock Edge (All Writes Happen Together)  │
  ├────────────────────────────────────────────────────┤

  1. MEPC (0x341) write:
     mepc_r <= trap_pc_o     // ← 32'h00000100
     Result: mepc_r = 32'h00000100

  2. MCAUSE (0x342) write:
     mcause_r <= {trap_is_interrupt_o, trap_cause_o}
              = {1'b0, 5'd4}
              = 32'h00000004       // bit 31=0 (exception), bits 4:0=4
     Result: mcause_r = 32'h00000004

  3. MTVAL (0x343) write:
     if (trap_addr_valid_o)
         mtval_r <= trap_addr_o    // ← 32'h0000064D
     else
         mtval_r <= 32'h00000000
     Result: mtval_r = 32'h0000064D

  4. MSTATUS (0x300) read-modify-write:
     
     Old MSTATUS = 32'h00001800
     Bits:        XXXX1100 0000 XXXX
                      │1111_0011│   ││││ ││││ ││││ ││││ ││
                      │ MPP     MPIE MIE

     Step A: Save MIE to MPIE
             new MIE = old MIE = bit[3] of old MSTATUS
                     = 1'b0
             new MPIE = new MIE = 1'b0

     Step B: Disable interrupts (clear MIE)
             new MIE = 1'b0

     Step C: Set MPP to M-mode
             new MPP = 2'b11 (M-mode)

     New MSTATUS within mask 32'h00001888:
             mstatus_r = ( old_mstatus & ~32'h00001888 )
                       | ( new_value & 32'h00001888 )

             where new_value = {12'b1111, 7'b0000000, 1'b0, 3'b111, 8'b00000000}
                             = 32'h00001800

             = (32'h00001800 & 0xFFFF2677)
             | (32'h00001800 & 0x00001888)

             = 0x00001800 | 0x00001800
             = 32'h00001800

     Result: mstatus_r = 32'h00001800 (unchanged in this case, since MIE was 0)

  └────────────────────────────────────────────────────┘

After Trap (t=7 state, on clock edge):
  MEPC     = 32'h00000100 ✓
  MCAUSE   = 32'h00000004 ✓
  MTVAL    = 32'h0000064D ✓
  MSTATUS  = 32'h00001800 (or updated if MIE was 1)

Handler can now read these CSRs (Port A, combinational):
  CSRR x1, mepc      → x1 = 32'h00000100
  CSRR x2, mcause    → x2 = 32'h00000004
  CSRR x3, mtval     → x3 = 32'h0000064D

Handler inspects:
  • Cause = 4 → load address misaligned
  • Address = 0x0000064D → odd address, can't do 32-bit load
  • PC = 0x00000100 → instruction that faulted

Handler options:
  1. Fix address and retry (not possible for load in user code)
  2. Skip instruction (ADDM mepc, mepc, 4)
  3. Call OS via SWI
  4. Panic/abort

Atomic Property:
  ╔══════════════════════════════════════════════════════════╗
  ║ All four registers (MEPC, MCAUSE, MTVAL, MSTATUS)       ║
  ║ updated simultaneously on one clock edge.                ║
  ║                                                          ║
  ║ Handler reads consistent snapshot of exception state.    ║
  ║                                                          ║
  ║ No race: Even if handler is interrupted during read,    ║
  ║ the CSR values were cohesive at entry.                  ║
  ╚══════════════════════════════════════════════════════════╝
```

---

## DIAGRAM 7: Valid Bit Lifecycle (Dead Code Elimination)

```
┌──────────────────────────────────────────────────────────────────┐
│           VALID BIT LIFECYCLE: How Dead Code is Killed           │
└──────────────────────────────────────────────────────────────────┘

Instruction A (LEGAL)       Instruction B (EXCEPTION)   Instruction C
at PC 0x100               at PC 0x104 (illegal)         at PC 0x108

t=0     Fetch A             ─                            ─
        ────────────────────────────────────────────────────
        valid_F = 1'b1
        exc_valid_F = 0

t=1     IF/ID = A           Fetch B                      ─
        ────────────────────────────────────────────────────
        valid_D = 1'b1      InstrF = (illegal)
        exc_valid_D = 0     exc_valid_F = 0

        (A continues normal path)

t=2     ID/EX = A           IF/ID = B                    Fetch C
        ────────────────────────────────────────────────────
        valid_E = 1'b1      valid_D = 1'b1               InstrF = C
        exc_valid_E = 0     exc_valid_D = 0              exc_valid_F = 0
        (No exception in A)  
                            (B's illegal detected in ID
                             combinational, but not yet
                             in exc_valid_D)

t=3     EX/MEM = A          ID/EX = B                    IF/ID = C
        ────────────────────────────────────────────────────
        valid_M = 1'b1      valid_E = 1'b1               valid_D = 1'b1
        exc_valid_M = 0     exc_valid_E = 1'b1 ✓✓✓      exc_valid_D = 0
        (A legal)            (EXCEPTION IN EX!)
                             
        Hazard Unit:
        exc_inflight_E = valid_E & exc_valid_E = 1
        ∴ FlushD = 1       (kill C in ID)
        ∴ FlushE = 1... is set on NEXT clock edge

t=4     MEM/WB = A          EX/MEM = B                   ID/EX = ??
        ────────────────────────────────────────────────────
        valid_W = 1'b1      valid_M = 1'b1               [flushed]
        exc_valid_W = 0     exc_valid_M = 1'b1           valid_E = 1'b0 ✓✓
        (A retires OK)      (EXCEPTION IN MEM!)           exc_valid_E = 0
                             
        IMPORTANT:
        A's RegWriteW = 1 & valid_W & ~exc_valid_W
                      = 1 & 1 & 1 = 1 ✓ (A writes register)
        
        C's ID/EX cleared: valid_E = 0 ✓ (FlushE=1 took effect)
        B's exception still propagates (was in EX, now in MEM)
        
        Hazard Unit (this cycle):
        exc_inflight_M = valid_M & exc_valid_M = 1
        ∴ FlushE, FlushD still set for NEXT cycle

t=5     MEM/WB = B          EX/MEM = ??                  ID/EX = ??
        ────────────────────────────────────────────────────
        valid_W = 1'b1      [flushed]                    [flushed]
        exc_valid_W = 1'b1  valid_M = 1'b0 ✓✓            valid_E = 0
        (EXCEPTION IN WB!)  exc_valid_M = 0              exc_valid_E = 0
        
        B's RegWriteM_gated = RegWriteM & valid_M & ~exc_valid_M
                            = ? & 0 & ? = 0 ✓ (B cannot write reg)
        B's WB_trap_commit = valid_W & exc_valid_W = 1 ✓✓✓
        
        (Trap now taken)
        wb_trap_redirect = 1
        ∴ Final FlushD=1, FlushE=1, FlushM=1, FlushW=1

t=6     [empty]             [empty]                      [empty]
        ────────────────────────────────────────────────────
        all valid = 0       (All stages cleared)
        
        PC redirects to mtvec.BASE (trap handler)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

TRIPLE GATING (Side-Effect Protection):

Instruction A (registers written):  RegWriteW_gated = 1 & 1 & 1 = 1 ✓ (OK)
Instruction B (register blocked):   RegWriteM_gated = ? & 0 & ? = 0 ✓ (blocked)
Instruction C (register blocked):   RegWriteE_gated = ? & 0 & ? = 0 ✓ (blocked)

WHY VALID=0 IS IMPORTANT:
─────────────────────────
 1. Blocks side-effects (write-inhibit gate)
 2. Marks instruction as "never happened" (for correctness)
 3. Combinational with hazard unit logic (no latency)
 4. Prevents speculative execution side effects
 5. Ensures only architectural instructions commit

FLUSH PROPAGATION:
──────────────────
 On t=3: FlushE=1 is driven (combinational)
 On t=4: ID/EX reg updates with valid_E ← 0 (synchronous)
         Result: C.valid_E = 0 (dead code detected)
         
 On t=4: FlushM still driven combinational (from exc_inflight_M)
 On t=5: EX/MEM reg updates with valid_M ← 0 (synchronous)
         Result: B is killed when it moves from EX to MEM

 On t=5: wb_trap_redirect = 1 (final stage flush)
 On t=6: All stages cleared, processor ready for trap handler
```

---

## DIAGRAM 8: MRET Return Path (Symmetric to Exception Entry)

```
┌──────────────────────────────────────────────────────────────────┐
│              MRET RETURN PATH (Reverse of Trap Entry)            │
└──────────────────────────────────────────────────────────────────┘

HANDLER EXECUTION (inside mtvec.BASE handler):

  At some point: mret instruction @ 0x80000010 (in handler space)

t=20  MEM/WB captures MRET:
      ────────────────────────────────────────────
      Instr @ 0x80000008 (previous handler instr)
      (moves to WB)
      │
      Next: Instr @ 0x8000000C (next in handler)
      │
      Next: Instr @ 0x80000010 (← MRET)

t=21  MEM/WB captures next handler instr:
      ────────────────────────────────────────────
      (handler instruction at WB)

t=22  MEM/WB captures MRET @ 0x80000008:
      ────────────────────────────────────────────
      MRET instr @ 0x80000008
      │
      valid_W = 1'b1 (retiring)
      is_mret_W = 1'b1 ✓✓✓ (MRET detected)
      exc_valid_W = 1'b0 (MRET has no exception sideband)
      RegWriteW = 1'b0 (MRET doesn't write general registers)
      │
      WB Trap Commit Controller (combinational):
      ├─ mret_commit = valid_W & is_mret_W & ~exc_valid_W
      │              = 1 & 1 & 1 = 1 ✓
      │
      ├─ wb_mret_redirect_o = mret_commit = 1
      │
      ├─ trap_target_o = {mepc[31:2], 2'b00}
      │               = {32'h00000100[31:2], 2'b00}
      │               = 32'h00000100 (return to faulting instr PC)
      │
      ├─ mret_commit_o = 1'b1 (signal CSR file)
      │
      └─ flush_pipeline_onehot_o = 4'b1111 (empty pipeline)

t=23  Clock edge (t=22→t=23):
      ────────────────────────────────────────────
      
      CSR File (Port D - MRET restore):
      ⚠️ CURRENTLY NOT IMPLEMENTED ⚠️
      
      if (mret_commit_i) begin  // ← Should be driven by above
          mstatus_r[3]        <= mstatus_r[7];  // MIE ← MPIE
          mstatus_r[7]        <= 1'b1;          // MPIE ← 1
          mstatus_r[12:11]    <= 2'b11;         // MPP ← M
      end
      
      Current workaround: Handler must manually issue
          CSRRS x0, mstatus, (some reg with MPIE bit set)
      to restore MIE before MRET.
      
      Fetch Cycle (PC redirect):
      PC ← mepc (from csr_sideband = 32'h00000100)
      │
      Next instruction fetched from 32'h00000100
      (the original faulting location, or handler may have
       modified mepc to skip instruction)

t=24  Pipeline resumes from return address:
      ────────────────────────────────────────────
      IF: Fetch @ 0x100
      ID: (decode)
      EX: (execute)
      MEM: (memory)
      WB: (writeback)
      
      Normal execution resumes
      MSTATUS is now restored (if Port D implemented):
      • MIE = old MPIE (interrupts re-enabled)
      • MPIE = 1
      • MPP = M-mode


╔════════════════════════════════════════════════════════════════╗
║               MRET RESTORE: IMPLEMENTATION COMPLETE             ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║ Port D (MRET Restore) is now connected/implemented in CSR file.║
║                                                                ║
║ Current state:                                                ║
║ • mret_commit_o is driven by WB trap controller              ║
║ • mret_commit_o now updates the CSR regfile mstatus fields    ║
║   atomically on commit (via the CSR write path)              ║
║                                                                ║
║ Result / Consequence:                                         ║
║ • MRET restores MSTATUS.MIE from MPIE on commit               ║
║ • Handler can safely execute MRET without manual CSR restore  ║
║ • Atomicity preserved; no race with CSRRS                     ║
║                                                                ║
║ Files changed:                                                ║
║ • `core/top.v` — wired mret commit signals into CSR path      ║
║ • `wb_trap_mret_commit_controller.v` — produces CSR write     ║
║   signals for MRET commit                                      ║
║ • `csr_regfile.v` — accepts the write and updates `mstatus`   ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
```

---

## Summary: All Critical Signals at a Glance

```
┌────────────────────────────────────────────────────────────────┐
│      EXCEPTION CRITICAL PATH SIGNALS (Alphabetical)             │
├────────────────────────────────────────────────────────────────┤

From EXCEPTION DETECTION:
  • exc_cause_* (5 bits)  ← Exception code (0-11)
  • exc_pc_*    (32 bits) ← PC of faulting instruction
  • exc_tval_*  (32 bits) ← Fault address or instruction bits
  • exc_valid_* (1 bit)   ← Exception detected (TRUE if exception)
  • is_mret_*   (1 bit)   ← MRET flag

Through PIPELINE REGISTERS:
  • valid_*     (1 bit)   ← Instruction not flushed (FALSE if flush)

From HAZARD UNIT (Combinational):
  • FlushD, FlushE, FlushM, FlushW (1 bit each) ← Kill stages
  • exc_inflight_E, exc_inflight_M (1 bit) ← Exception in-flight
  • flush_pipeline_onehot[3:0] ← From WB (final flush)

From WB TRAP COMMIT CONTROLLER (Combinational):
  • mret_commit_o        (1 bit)   ← MRET is retiring
  • trap_valid_o         (1 bit)   ← CSR Port C write enable
  • trap_target_o        (32 bits) ← New PC (mtvec or mepc)
  • trap_cause_o         (31 bits) ← {interrupt, cause[30:0]}
  • trap_pc_o            (32 bits) ← Exception PC for MEPC
  • trap_addr_o          (32 bits) ← Fault address for MTVAL
  • trap_addr_valid_o    (1 bit)   ← MTVAL is meaningful
  • trap_is_interrupt_o  (1 bit)   ← 1=interrupt, 0=exception
  • wb_trap_redirect_o   (1 bit)   ← Trigger PC redirect + flush

To CSR REGFILE PORT C (Synchronous write):
  • csr_write_en_exc_i   (1 bit)   ← trap_valid_o
  • csr_waddr_*_i        (12 bits) ← CSR address
  • csr_wdata_*_i        (32 bits) ← New CSR value

To CSR REGFILE PORT D (NOT IMPLEMENTED):
  • mret_valid_i         (1 bit)   ← mret_commit_o (should be)

To FETCH CYCLE PC MUX:
  • wb_trap_redirect     (1 bit)   ← Assert trap/MRET redirect
  • trap_target          (32 bits) ← New PC for next cycle

From CSR SIDEBAND (Combinational reads):
  • mepc_out_o           (32 bits) ← Return address for MRET
  • mtvec_out_o          (32 bits) ← Trap handler base address
  • mstatus_mie_out_o    (1 bit)   ← Global interrupt enable

└────────────────────────────────────────────────────────────────┘
```

---

**End of Diagram Document**
