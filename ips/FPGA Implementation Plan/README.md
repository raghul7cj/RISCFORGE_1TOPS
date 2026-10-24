# RISCFORGE SoC — FPGA Implementation Plan
**Orchestration-Driven, Stage-Gated Implementation Flow**

> **Document ID**: FPGA-PLAN-ROOT  
> **Revision**: A.0  
> **Date**: 2026-10-16  
> **Orchestrator**: Antigravity (Claude Sonnet 4.6)  
> **Status**: 🔵 IN PROGRESS — Stage 0 Active

---

## Overview

This folder contains the complete FPGA Implementation Plan for **RISCFORGE 1TOPS** — a 5-stage RV32IM SoC targeting FPGA prototyping. The plan is **stage-gated**: no stage may begin until the previous stage's **sign-off is explicitly granted**.

The inputs to this plan are:
- **RTL tree**: `ips/` — 139 RTL files across 20+ IP blocks
- **Verification findings**: `RISCFORGE_Verification_Plan_RevB.docx` — 170+ open defects (D-001 through D-180+) catalogued against the RTL
- **JasperGold config**: `jaspergold/lint.tcl`, `jaspergold/jg_soc.f`
- **SpyGlass config**: `spyglass/spyglass.prj`

---

## Stage Index & Sign-Off Gate Map

| Stage | File | Title | Status | Sign-Off |
|:-----:|:-----|:-------|:------:|:--------:|
| S0 | [STAGE-0_Filelist_Audit.md](./STAGE-0_Filelist_Audit.md) | Filelist Integrity & File Resolution | ✅ Verified | ⬜ Pending Sign-Off |
| S1 | [STAGE-1_RTL_Lint.md](./STAGE-1_RTL_Lint.md) | RTL Structural Lint (XSim Elaboration) | ✅ Verified (0 Err) | ⬜ Pending Sign-Off |
| S2 | [STAGE-2_Structural_Checks.md](./STAGE-2_Structural_Checks.md) | Clock/Reset Domain & Connectivity Analysis | ✅ Verified (0 BB) | ⬜ Pending Sign-Off |
| S3 | [STAGE-3_RTL_Defect_Triage.md](./STAGE-3_RTL_Defect_Triage.md) | RevB Defect Triage & RTL Fixes | ✅ Triage & Fix Done | ⬜ Pending Sign-Off |
| S4 | [STAGE-4_Synthesis_Baseline.md](./STAGE-4_Synthesis_Baseline.md) | Vivado Synthesis Baseline (Out-of-Context) | ✅ Verified (0 Err, 16 BRAM) | ⬜ Pending Sign-Off |
| S5 | [STAGE-5_Constraints_IO.md](./STAGE-5_Constraints_IO.md) | Timing Constraints, I/O Planning & XDC | 🔵 Ready to Run | ⬜ Pending |
| S6 | [STAGE-6_Implementation.md](./STAGE-6_Implementation.md) | Place & Route + Timing Closure | ⏳ Blocked on S5 | ⬜ Pending |
| S7 | [STAGE-7_Bitstream_Validation.md](./STAGE-7_Bitstream_Validation.md) | Bitstream Generation & Hardware Bring-Up | ⏳ Blocked on S6 | ⬜ Pending |

---

## Status Legend

| Icon | Meaning |
|:----:|:--------|
| 🔵 | Active — work in progress |
| ✅ | Complete — findings documented |
| 🔴 | Blocked — critical issue requires resolution |
| ⏳ | Waiting — blocked on prior stage sign-off |
| ⬜ | Sign-off pending — awaiting human approval |
| ✔️ | Signed off — stage approved, next stage unlocked |

---

## Sign-Off Protocol

Each stage document ends with a **Sign-Off Block**. For a stage to be declared closed:
1. All mandatory checks must show `PASS` or `WAIVED (with rationale)`
2. All `CRITICAL` / `ERROR` findings must be resolved or formally waived
3. The user must explicitly write **"SIGN OFF: S\<N\>"** in chat

---

## SoC Architecture Quick Reference

```
RISC-V RV32IM Core (5-stage)
  ├── BootROM (64B, 0x0000_0000)          ← Direct fetch demux
  ├── ISRAM  (32KB, 0x0001_0000)          ← Priv-gated AXI writes
  ├── DSRAM  (32KB, 0x0002_0000)          ← AXI direct
  └── AXI-Lite Crossbar (2SLV × 3MST)
        ├── MST[0] → ISRAM (PRIV_WRITE_ONLY)
        ├── MST[1] → DSRAM
        └── MST[2] → AXI→APB Bridge (6 slaves)
              ├── APB[0] I2C      0x4000_0000
              ├── APB[1] Timer0   0x4000_1000
              ├── APB[2] UART     0x4000_2000
              ├── APB[3] GPIO     0x4000_3000
              ├── APB[4] SPI/BL   0x4000_4000
              └── APB[5] Timer1   0x4000_5000
Bootloader (AXI master, APB slave) → manages 5 reset domains
7× Bus Timeout Monitors (6 APB + 1 AXI)
```

---

## Key Known Issues (from RevB Verification Plan)

> These are the highest-severity defects the orchestrator must track through all stages.

| ID | Severity | Area | Summary |
|:---|:--------:|:-----|:--------|
| D-015 | CRITICAL | UART | OBI chain NOT removed — `apb_uart_wrap.sv` instantiates hidden chain |
| D-114 | HIGH | Filelist | 15/40 filelists have unresolvable entries; 2× timer.sv conflicts |
| D-008 | HIGH | SW/BSP | No `soc_regs.h`; linker script incomplete (ISRAM/DSRAM only) |
| D-013 | MEDIUM | APB | `apb_pkg.sv` self-describes as "APB v2.0" — stale (is APB4) |
| D-169 | MEDIUM | AON | AON timer RTL exists but is unconnected; 14-reg TL-UL interface |
| D-180 | HIGH | Reset | Watchdog bite path (`aon_timer_rst_req_o`) unconnected to `sys_rst_n_raw` |
| D-006 | HIGH | Core | Shadow stack incomplete — sync exceptions never push; depth-2 silent drop |
| D-009 | LOW | Compliance | RISCOF test suite snapshot v2.4.4 is not current upstream |
| D-003 | HIGH | IRQ | `mip[20:26]` wired at SoC but dropped at core (`top.v:548`) |
| D-022 | MEDIUM | Env | RTL hash / filelist identity checking not implemented |

*Full defect catalog is maintained in [STAGE-3_RTL_Defect_Triage.md](./STAGE-3_RTL_Defect_Triage.md)*

