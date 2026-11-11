# RISCFORGE 1-TOPS sign-off — action plan (draft, 2026-11-02)

Source checklist: `1TOPS OFFICIAL DELIVERABLES/1TOPS_Project_Signoff_Checkl.xlsx` (124 items, G0–G9; target tape-out 2026-12-01, 28 nm).
Existing framework this plan hangs on: Rev B phases P0–P6 (`Verification/status/PHASE_STATUS.md`), stage tracker S0–S7 (`INFRA_TRACKING.md`), evidence audit (`Verification/signoff/README.md`).
**Status of this file: proposal for the owner to edit. Nothing here is a gate claim.**

## 0. Facts that shape the plan

| Fact | Source | Consequence |
|---|---|---|
| 29 days to tape-out; G7–G9 (synth, DFT, PD, STA, DRC/LVS) all come after RTL freeze (6.19) | checklist | RTL freeze must be early; every day spent on G4–G6 comes out of the back-end budget |
| Core RTL last changed 2026-10-29 (DEF-001 fix, IRQ integration). Old unit TBs date from June–Sept | file dates | Old TB results are history. Every unit TB must be re-run on the current RTL before it counts |
| 5 checklist items disagree with the design: PLIC (3.4), CLINT/CLIC (3.6), 4 KB boot ROM (3.9, actual 64 B), boot_mode strap + fallback (1.12), AXI→AXI-Lite bridge (3.11) | `Verification/signoff/README.md` | Needs a coach decision (build or waive) before the related G1/G3/G6 items can be written |
| Checklist says VCS/Verdi for sim. Much evidence is XSim/Xcelium | checklist, `PHASE_STATUS.md` ACT-006 | Pick simulator of record (suggest VCS) and re-run the final evidence there |
| Known limitation: taken branch/jump costs 1 cycle more than an optimal fetch would (functionally proven) | owner | Record as performance note in micro-arch doc; not a gate item, no work planned |

## 1. Step-by-step order

Who: **You** = judgment/ownership (tutor-mode: you propose, I review). **Claude** = mechanical work I can run. **Coach** = approval.

### Step 1 — Decisions and identity (days 1–2) — unblocks everything
| # | Task | Checklist | Who |
|---|---|---|---|
| 1.1 | Meet coach with the 5 mismatches; for each choose **build** or **waiver** (one-line reason). Also record DC-1 (CLIC / AON watchdog out of scope) and Q1 (UART RTL present or struck) | 1.9, 3.4, 3.6, 3.9, 1.12, 3.11 | You + Coach |
| 1.2 | Declare ISA RV32IM+Zicsr, 5-stage, forwarding policy; set target MHz and area/power budget with coach | 1.1, 1.2, 1.15 | You + Coach |
| 1.3 | Fix filelist rot and duplicate RTL copies (DEF-005, B9/B10/B15); write the P0 run-package script (hash RTL + filelist, tool version, seed, command, logs) | 0.6, 0.7, P0 | Claude runs; you review |
| 1.4 | Choose simulator of record and `make regress`-style single command | 0.7 | You decide, Claude wires |

### Step 2 — Freeze the specification (days 2–5) — G1
| # | Task | Checklist | Who |
|---|---|---|---|
| 2.1 | Review the four documents written in the background (see §2) against RTL, correct them, answer their "Ambiguities" lists | 1.1–1.13 | You |
| 2.2 | Verification plan: feature → test → coverage map across 5 phases. Start from `Verification/soc_verification_plan.md` + Rev B plan, re-keyed to checklist IDs | 1.14 | You draft, Claude formats |
| 2.3 | Coach approval; tag repo `g1-freeze` | G1 | Coach |

### Step 3 — Core RTL gate (days 3–8, overlaps Step 2) — G2
| # | Task | Checklist | Who |
|---|---|---|---|
| 3.1 | Evidence table: one RTL file link per 2.1–2.10 (the unit exists; rows are mostly "Done" once the micro-arch doc is reviewed). Honest "N/A" with reason for 2.10 (no C extension) | 2.1–2.10 | Claude fills; you confirm |
| 3.2 | Run SpyGlass lint + CDC on the core; triage by you, waivers written | 2.11–2.13 | Claude runs; you triage |

### Step 4 — Core verification, unit and sanity (days 4–12) — G4
Old TBs exist; they must be ported/re-run on current RTL.

| Checklist | Unit | Old TB in repo (re-run needed) | Gap |
|---|---|---|---|
| 4.1 | PC | none found (`tb_fetch_equiv.v` is fetch equivalence only) | **new TB** |
| 4.2 | Decoder/control | none found | **new TB** |
| 4.3 | Register file | none found | **new TB** |
| 4.4 | ALU | `OLD files rtl-dv/verif/tb_alu/tb_alu_top.sv` | re-run, check corners listed in criterion |
| 4.5 | Branch (JB) | none found | **new TB** |
| 4.6 | MDU | none found | **new TB** |
| 4.7 | MIU / LSU | `verif/tb_lsu/*`, `lsu verification export/*` | re-run, check size×offset matrix |
| 4.8 | Hazard | `verif/tb_hazard/tb_hazard_top.sv` | re-run; DEF-001 regression (ACT-010) |
| (CSR/trap) | CSR, commit ctrl | `tb_csr_regfile.sv`, `tb_wb_commit_ctrl.sv`, `tb_top_exceptions.sv`, `tb_top_mret.sv` | re-run; supports 4.12 |
| 4.10–4.14 | Core sanity | `verification/riscof` flow, `rv32im..._old/.../tb_riscof_soc_dual.sv` | rebuild on `ips/` core |

Who: **You** write the test plan per unit and own any failures (tutor mode: I report failures, you hypothesise). **Claude** runs regressions, collects logs/coverage, packages evidence. New TBs: you propose structure, I review; scaffolding is mechanical and can be delegated on your say-so.

### Step 5 — Core verification with software (days 8–16) — G5
5.1 Spike lockstep/log-compare flow · 5.2 riscv-arch-test rv32ui/um (RISCOF already exists; re-run on current RTL) · 5.3 trap tests · 5.4–5.5 riscv-dv (seed count agreed with coach) · 5.6 memory-latency randomisation · 5.7 Dhrystone/CoreMark · 5.8–5.9 coverage · 5.10 bug list (migrate `bug fixes/*` and INFRA B/V register into one list).
Who: Claude builds/run flows; you triage every mismatch; Coach approves seed count.

### Step 6 — SoC integration gaps and SoC verification (days 3–18, parallel to Steps 4–5) — G3 + G6
| # | Task | Checklist | Who |
|---|---|---|---|
| 6.1 | Implement per Step 1 decisions: system control block (reset/clock/boot strap/ROM remap), 4 KB boot ROM, boot_mode pin, whatever interrupt-controller outcome the coach chose | 3.4, 3.6, 3.9, 3.12, 1.12 | You design, Claude reviews |
| 6.2 | Register tests across all APB slaves (regtest infra exists, 66-register model) | 6.2, 6.3 | Claude runs; you own failures |
| 6.3 | Interrupt path end-to-end per source; bridge/decode/error-path tests; fabric path scoreboard (INFRA: the one missing piece) | 6.5–6.7 | You |
| 6.4 | Boot tests: internal ROM, SPI flash with strap, SRAM load/remap | 6.9–6.11 | You |
| 6.5 | Bare-metal C suite, trap robustness, stress, long run | 6.12–6.14, 6.18 | Claude runs |
| 6.6 | Checklist demands a **UVM** SoC TB (6.1). Timer UVM env exists as template. Decide: build, or request waiver for the existing SV infra | 6.1 | You + Coach |
| 6.7 | SoC lint/CDC/RDC/floating nets | 3.14–3.16 | Claude runs; you triage |
| 6.8 | Coverage closure (functional + code ≥95 %) | 6.15, 6.16 | You |

### Step 7 — RTL freeze (target ~day 18 = 2026-11-20) — 6.17, 6.19
Full regression clean on VCS, tag `rtl-freeze`, coach approval. Slipping this date directly shortens G7–G8.

### Step 8 — Back end (day 18 → 29) — G7, G8, G9
Gated by 0.1/0.2/0.5 (tools and 28 nm PDK actually usable). Verify access **now** (G0), not at freeze: if the PDK/libs are not in hand, G7+ cannot start. Honest risk: 11 days for synthesis, DFT, PD, STA, DRC/LVS, GDS is very tight; discuss with coach whether 12-01 is the MPW date or the internal one.
Documents that can be produced before freeze (9.6 datasheet, 9.7 verification report skeleton, 9.5 pin/package plan) should be drafted in parallel.

## 2. Documentation produced by background agents (this session)
Folder `ips/documentation/signoff/`:
- `CSR_and_Trap_Model.md` → 1.3, 1.4, 1.5, 2.9
- `Core_Microarchitecture.md` → 1.1, 1.2, 1.13, 2.1–2.8
- `SoC_Architecture_Map_Boot.md` → 1.6, 1.7, 1.8, 1.9, 1.12, 3.1–3.13
- `Clock_Reset_CDC_and_Pinlist.md` → 1.10, 1.11
Not yet covered (candidate next batch): 1.14 test plan, 1.15 budgets, 9.6 datasheet/register map, 9.7 verification report.

## 3. Open questions for the owner
See the chat summary; answers go here as decisions.
