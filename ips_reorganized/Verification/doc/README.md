# Verification documentation — coverage closure, bins and stimulus

**Scope:** all documentation under `ips/Verification/doc/`. Segregated by document purpose on 11 November 2026 (previously flat). Records the CSR/trap unit bench closure state; no signoff credit is claimed.

| Folder | Object type | Contents |
|---|---|---|
| `architecture/` | How the bench is built | `CSR_TRAP_TESTBENCH_ARCHITECTURE.html` |
| `plans/` | What will be verified, and how | `CSR_TRAP_CORNER_TESTPLAN.md` |
| `status/` | What a run established, and what it did not | `CSR_TRAP_VERIFICATION_STATUS.md`, `CJ_EVIDENCE_INDEX_20261111.md` |
| `briefs/` | Delegated work orders (no results) | `csr_trap/`, `stages/` (stage_1–8), `tracks/` (formal Track F) |
| `diagrams/` | Validated diagram specs + renders | `csr_trap_unit_verification_chain.*` |
| `backup/` | Dated pre-edit copies + manifests | `20261111_1807/`, `20261111_1821_presegregation/` |

Reading order: `plans/` → `architecture/` → `status/` → `../infrastructure/tb/csr_trap/README.md` → `briefs/csr_trap/`.

---

## 1. What is claimed, and what is not

| Claim | State | Basis |
|---|---|---|
| Unit bench compiles and elaborates | **Established** | XSim 2022.2, zero warnings |
| Unit stimulus drives 236 directed cases | **Established** | `tb_csr_corner_unit.sv` |
| 552 expected-value checks, 0 failures | **Established** | `UNIT_DONE\|checks=552\|failures=0` |
| 236 index bins sampled once each | **Established (observation)** | `OBSERVED_COVERAGE\|…\|100.000` |
| 56 collision/counter cases judged | **Not claimed** | `spec_pending`, no expected value |
| Value, mask or cross coverage | **Not claimed** | no such bins exist |
| Core-level behaviour | **Not claimed** | no stimulus, 0 checks |
| Independent reference model | **Absent** | expectations are in-test literals |
| Coverage-database report | **Absent** | XCRG crashes (`0xC0000374`) |

## 2. How a bin earns credit

Each bin is an **index bin**: `coverpoint index { bins planned[] = {[0:N-1]}; }`, one bin per planned case
([`csr_trap_coverage_pkg.sv`](../infrastructure/tb/csr_trap/csr_trap_coverage_pkg.sv)).

- `sample_bin(group_id, index)` is called once, at the end of the case, after the sampling edge.
- Each call prints `BIN_HIT|<group>|<index>`; the suite prints `OBSERVED_COVERAGE|<group>|<pct>` at the end.
- **Credit means "this case was executed once"**, not "this value combination was observed". There is no hit count, no `bins`/`binsof` value partition, no cross, no exclusion, no illegal-bin check.
- Report reading: `get_inst_coverage()` over the declared range. A 100.000 figure is therefore an attempt index, not an architectural closure metric.

## 3. Unit bins — group, case count, stimulus, verdict

| Group | Bins | Cases | Stimulus driven | Expected result | Verdict |
|---|---|---|---|---|---|
| `u_status` | 8 | 8 | `trap_valid` XOR `mret_commit` × old MIE {0,1} × old MPIE {0,1}; `mscratch` preloaded `0x12345678` | trap: MIE←0, MPIE←old MIE. MRET: MIE←MPIE, MPIE←1, MPP←`11`. `mscratch` preserved | 24 checks, 0 fail |
| `u_metadata` | 168 | 168 | 21 causes (0–20, causes ≥8 flagged interrupt) × `trap_pc` {0, `0x80000124`} × `trap_address_valid` {0,1} × `trap_address` {0, `0x87654321`} | `mepc`=trap PC; `mcause`=interrupt bit \| code; `mtval`=address only when valid | 504 checks, 0 fail |
| `u_collision` | 40 | 40 | Port B write `0x89ABCDEF` to one of 13 CSRs × {trap, MRET, trap+MRET}, plus trap+MRET with no write | **none encoded** — record only | 40 observations |
| `u_counter` | 16 | 16 | 2 counters × 2 rollover boundaries (low half written `0xFFFFFFFF`, high half 0/`0xFFFFFFFF`) + 2 counters × {low, high} × {increment, trap, MRET} with `instr_retired=1` | **none encoded** — record only | 16 observations |
| `u_reset` | 4 | 4 | `rst_n` asserted during {write, trap, MRET, write+trap} | `mstatus`, `mie`, `mepc`, `mcause`, `mcycle`, `minstret` all 0 | 24 checks, 0 fail |
| **Total** | **236** | **236** | | | **552 checks / 0 fail / 56 pending** |

Case index maps to loop order: status `event*4 + mie*2 + mpie`; metadata `cause*8 + pc*4 + valid*2 + value`; collision `kind*13 + target`; counter `4 rollover + 12 write-vs-increment`; reset `kind`.

## 4. Stimulus discipline

- Driven on `negedge`, sampled after `posedge` + `#1ns`, so every check sees settled state.
- `reset_case()` between cases: no state leaks across scenarios; each case is self-contained.
- 31/31 `csr_regfile` ports connected by name; read is combinational (port A), writes are commit-time (port B/C).
- Reset values and WARL masks are re-loaded per case, not assumed from the previous case.

## 5. What the collision run recorded

| Event in the same cycle as the Port B write | Effect observed |
|---|---|
| Trap | write dropped file-wide (e.g. `mie` stays `0x12340008`, `mtvec` stays `0x12345678`); trap-owned registers still update (`mepc`=`0x80000120`, `mcause`=`0x0000000b`) |
| MRET | write dropped file-wide; `mstatus` becomes `0x00001880` (MPIE←1, MIE←old MPIE, MPP←`11`) |
| Trap + MRET | trap wins; `mepc`/`mcause` updated, all other targets keep the preloaded value |
| `mip` under any event | `0x00000008` — MSIP commits from its own always block (`csr_regfile.v:208-215`) |
| Counter target | write dropped, counter still increments each clock (`mcycle` `0x12345678` → `0x1234567a`) |

These are observations of `csr_regfile.v:159-200`. Whether file-wide suppression is the approved contract is **D1–D6**, still open.

## 6. Core bins — defined, not sampled

Declared in the same package, instantiated with `unit_scope = 0`; no `sample_bin` call exists for group IDs 5–12.

| Group | Bins | Group | Bins |
|---|---|---|---|
| `c_exception` | 46 | `c_irq_phase` | 24 |
| `c_csr_dependency` | 76 | `c_m_interrupt` | 30 |
| `c_irq_delivery` | 52 | `c_exception_overlap` | 19 |
| `c_irq_order` | 18 | `c_mret` | 12 |
| **Total** | **277, 0 sampled** | | |

`tb_core_csr_trap` compiles 39 sources, elaborates, runs 30 ns reset-held: `SKELETON/INCOMPLETE; checks=0`.

## 7. Closure arithmetic and evidence

- Checks: 8×3 + 168×3 + 4×6 = **552**; `spec_pending` = 40 + 16 = **56**; bins = 8 + 168 + 40 + 16 + 4 = **236**.
- Evidence: [`artifacts/csr_trap_units_20261111_175150/`](../artifacts/csr_trap_units_20261111_175150/) — `compile.log`, `elaborate.log`, `simulation.log`, `sources.f`, `run.tcl`, `source_sha256.txt` per bench.
- Source identity: `sha256:9e68edc9…3903d3c` (digest of that run's `source_sha256.txt`); 10/10 tracked files still match.
- Run again: `pwsh -NoProfile -File ../run_csr_trap_units.ps1` (from `Verification/`).

## 8. Integrity gate

`py ../tools/check_csr_trap_docs.py` re-derives the claims from source and logs: **10/10 checks pass** (ports, filelists, evidence hashes, markers, bin count). Run it after any bench or doc edit.

## 9. Open decisions (owner) and next actions

| # | Decision | Blocks |
|---|---|---|
| D1 | Is file-wide trap/MRET write suppression intended? | 39 collision expectations |
| D2 | Should an MRET-cycle write to an unrelated CSR commit? | MRET scope |
| D3 | Is `mip.MSIP` write-through during trap intended? | 1 collision case |
| D4 | Counter write during event: increment kept or write applied? | 12 counter cases |
| D5 | `mtval` for interrupts: 0 or the driven address? | metadata policy |
| D6 | Silent unimplemented-CSR access (read 0 / drop write)? | illegal-access scope |

Next: record D1–D6 → convert the 56 observations into checks → add an independent reference model → build core stimulus and enable groups 5–12 → re-run the gate.

## 10. Filing rule for new documents

1. File by purpose: `architecture/`, `plans/`, `status/`, `briefs/`, `diagrams/` — never by date.
2. One object per document; do not append a second subsystem's results to an existing status page.
3. Status pages are dated and never rewritten; a newer run adds a dated section or a new page.
4. Every status claim links to retained evidence under `artifacts/<run>/` and states its source identity.
5. Copy to `backup/<timestamp>_<reason>/` with a manifest before editing an existing document.
6. Diagrams are rendered from a saved spec (`diagram_tool.py` must report `OK`), never drawn by hand.
7. Run the integrity gate before handing back.

Caveats: `briefs/stages/` and `briefs/tracks/` belong to the wider verification track, not CSR/trap. `ips/PROPOSED_REPOSITORY_CATALOG.md` lists a *proposed* `Verification/infrastructure/doc/` layout and was not rewritten. `backup/` is copies only — never link to it except a manifest reference.