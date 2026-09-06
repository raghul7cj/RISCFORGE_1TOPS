# Verification Master Plan — RISCFORGE 1TOPS

**Core**: 5-Stage RV32I, M-Mode Only, Propagate-and-Commit Exceptions  
**Last Updated**: May 2026  
**Tooling**: Vivado 2022.2 (primary) · Verilator (regression) · Xcelium (future)

---

## 1. Verification Philosophy

### ROI-First Approach
Not all blocks carry equal risk. This plan ranks verification effort by **architectural impact** — blocks that can silently corrupt state or break the programming model get verified first. Leaf datapath blocks (ALU, sign-extend) are proven by integration tests, not isolated unit TBs.

### High-ROI Targets (Verify Now)

| Priority | Block | Why |
|----------|-------|-----|
| **P0** | `csr_regfile.v` | Silent corruption of machine state → undebuggable in C code |
| **P0** | `wb_trap_mret_commit_controller.v` | Incorrect trap/MRET → broken exception model |
| **P0** | CSR ↔ WB Controller integration | Port priority, atomic trap entry, MRET restore |
| **P1** | `memory_cycle.v` misalignment detection | MEM-local exception merge with propagated exceptions |
| **P1** | `hazard_unit.v` continuous flush + exc_inflight | Younger instructions leaking past exception |
| **P2** | Full-pipeline exception round-trip | ECALL → handler → MRET end-to-end |
| **P2** | Performance counters (mcycle/minstret) | Needed for bare-metal C timing validation |

### Low-ROI (Skip for Now)

| Block | Reason |
|-------|--------|
| ALU unit tests | Proven by instruction-level integration tests |
| Sign_Extend unit test | Trivially correct; bugs surface immediately in decode |
| ls_unit standalone | Covered by memory-stage + misalignment tests |
| Register File standalone | x0 hardwire tested by any instruction test |
| Instruction Memory | Static ROM; tested by loading programs |

---

## 2. Tooling Strategy

### Short-Term: Vivado 2022.2 + Verilator

```
┌──────────────────────────────────────────────────┐
│  Development Flow (Now)                          │
│                                                  │
│  Write SV TB ──► Vivado xsim ──► Waveform debug │
│       │                                          │
│       └────────► Verilator ──► Fast regression   │
│                  (lint + sim)    (CI-ready)       │
└──────────────────────────────────────────────────┘
```

| Tool | Use Case | SV Support |
|------|----------|------------|
| **Vivado xsim** | Interactive debug, waveform, synthesis check | Full SV (2017) |
| **Verilator** | Fast compile, lint, regression sweeps | SV subset (no `rand`, limited `covergroup`) |

### Verilator Constraints
- No `randomize()` — use manual stimulus or LFSR-based
- No `covergroup` — use `cover property` or manual counters
- Assertions (`assert property`) supported with `--assert`
- Use `--trace` for VCD, `--coverage` for line/toggle coverage

### Future: Xcelium
- Full UVM, `covergroup`, constrained-random
- Planned for interrupt/PLIC integration (Phase 6+)
- **Not required now** — all current tests are directed

---

## 3. Test Suite Architecture

### Directory Structure
```
rtl/5_stage/
├── tb/                          ← NEW: All testbenches
│   ├── common/                  ← Shared packages, clock/reset
│   │   ├── tb_pkg.sv            ← Types, macros, checker tasks
│   │   └── clk_rst_gen.sv       ← Reusable clock/reset generator
│   ├── unit/                    ← Block-level TBs
│   │   ├── tb_csr_regfile.sv
│   │   ├── tb_wb_commit_ctrl.sv
│   │   └── tb_mem_exception.sv
│   ├── integration/             ← Multi-block TBs
│   │   ├── tb_csr_trap_integration.sv
│   │   └── tb_hazard_flush.sv
│   ├── system/                  ← Full-pipeline program tests
│   │   ├── tb_top_smoke.sv
│   │   ├── tb_top_trap_roundtrip.sv
│   │   └── tb_top_perf_counters.sv
│   ├── programs/                ← Assembly test programs (.hex)
│   │   ├── ecall_mret.hex
│   │   ├── illegal_instr.hex
│   │   ├── misaligned_load.hex
│   │   └── csr_rw_suite.hex
│   └── scripts/                 ← Build/run scripts
│       ├── run_vivado.tcl
│       ├── run_verilator.sh
│       └── regression.py
```

### Regression Levels

| Level | Scope | Run When | Time |
|-------|-------|----------|------|
| **L0** | Compile + lint all RTL | Every save | < 30s |
| **L1** | Unit: CSR + WB Controller | Any trap_mret_csr/ change | < 2 min |
| **L2** | Integration: CSR↔Controller↔Hazard | Any pipeline change | < 5 min |
| **L3** | System: Full pipeline programs | Before milestone | < 10 min |
| **L4** | ISS co-sim (future) | Release candidate | < 30 min |

---

## 4. Verification Methodology

### 4.1 SystemVerilog Assertions (SVA)
- **Inline** in RTL for architectural invariants (always active)
- **Bind files** for block-level protocol checks (TB-only)
- Both Vivado and Verilator (`--assert`) support `assert property`

### 4.2 Functional Coverage
- **Vivado**: Use `covergroup` in TB wrapper
- **Verilator**: Use manual hit counters + `cover property`
- Coverage targets: CSR write masks, exception cause codes, flush scenarios

### 4.3 Directed Smoke Tests
- Hand-crafted corner cases for each block
- Each test has explicit pass/fail criteria (not just "no errors")
- Self-checking: TB compares DUT output against expected values

### 4.4 ISS Integration Roadmap (Future)
```
Phase A: spike --isa=rv32i  → golden trace (PC, reg writes, CSR writes)
Phase B: DUT trace logger   → captures same events from RTL sim
Phase C: Python comparator  → diff golden vs DUT, report mismatches
Phase D: C program runner   → compile C → hex → load → compare trace
```
- **Not blocked on Xcelium** — Python-based comparison works with any simulator
- End goal: run bare-metal C → verify against spike

---

## 5. Phased Execution Plan

### Phase V1: CSR + Exception Foundation (This Week)
| # | Task | Document |
|---|------|----------|
| 1 | CSR regfile unit TB + assertions | `01_CSR_REGFILE_VERIFICATION.md` |
| 2 | WB commit controller unit TB + assertions | `02_WB_COMMIT_CTRL_VERIFICATION.md` |
| 3 | CSR ↔ Controller integration TB | `03_CSR_TRAP_INTEGRATION_VERIFICATION.md` |

### Phase V2: Pipeline Exception Flow (Next Week)
| # | Task | Document |
|---|------|----------|
| 4 | MEM-stage misalignment + exception merge | `03_CSR_TRAP_INTEGRATION_VERIFICATION.md` §MEM |
| 5 | Hazard unit continuous flush assertions | `04_PIPELINE_EXCEPTION_VERIFICATION.md` |
| 6 | Full trap round-trip (ECALL→handler→MRET) | `04_PIPELINE_EXCEPTION_VERIFICATION.md` |

### Phase V3: System Smoke + Perf Counters (Week 3)
| # | Task | Document |
|---|------|----------|
| 7 | Performance counter accuracy tests | `05_SYSTEM_SMOKE_TESTS.md` |
| 8 | Assembly program regression suite | `05_SYSTEM_SMOKE_TESTS.md` |
| 9 | Regression script + CI setup | `05_SYSTEM_SMOKE_TESTS.md` |

### Phase V4: ISS + Bare-Metal C (Month 2)
| # | Task | Document |
|---|------|----------|
| 10 | Spike ISS trace comparison | `06_FUTURE_VERIFICATION_ROADMAP.md` |
| 11 | C toolchain integration | `06_FUTURE_VERIFICATION_ROADMAP.md` |
| 12 | Interrupt/PLIC verification (Xcelium) | `06_FUTURE_VERIFICATION_ROADMAP.md` |

---

## 6. Document Index

| File | Content | Status |
|------|---------|--------|
| `00_VERIFICATION_MASTER_PLAN.md` | This document — strategy + phasing | ✅ |
| `01_CSR_REGFILE_VERIFICATION.md` | CSR unit TB, assertions, coverage | 📋 Next |
| `02_WB_COMMIT_CTRL_VERIFICATION.md` | WB controller unit TB, assertions | 📋 Next |
| `03_CSR_TRAP_INTEGRATION_VERIFICATION.md` | CSR+Controller+MEM integration | 📋 Next |
| `04_PIPELINE_EXCEPTION_VERIFICATION.md` | Hazard flush, full trap flow | 📋 Next |
| `05_SYSTEM_SMOKE_TESTS.md` | Program-level tests, perf counters | 📋 Next |
| `06_FUTURE_VERIFICATION_ROADMAP.md` | ISS, C, interrupts, Xcelium | 📋 Next |

---

## 7. Pass/Fail Criteria

### Block-Level (L1)
- All assertions pass (zero failures)
- All directed test vectors produce expected output
- Coverage bins hit >= 90% for implemented features

### Integration (L2)
- Trap entry atomically updates mepc/mcause/mtval/mstatus
- MRET atomically restores mstatus and redirects to mepc
- Exception priority: trap > MRET > normal commit
- Continuous flush prevents younger side effects

### System (L3)
- All assembly programs produce correct signature in DMEM
- Performance counters match expected values +/- 0
- No assertion failures across entire regression

### Release (L4 — Future)
- ISS trace matches DUT trace for all test programs
- Bare-metal C printf equivalent produces correct output
- Interrupt round-trip (when PLIC connected) works end-to-end
