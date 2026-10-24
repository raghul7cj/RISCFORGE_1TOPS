# STAGE 3 — RevB Defect Triage & RTL Fixes
**FPGA-PLAN-S3 | Blocked on S2 Sign-Off**

> **Status**: ✅ COMPLETE — Root-Cause Triage & Remediation Methodology Completed  
> **Report Artifact**: [`TRIAGE_AND_METHODOLOGY_REPORT.md`](./TRIAGE_AND_METHODOLOGY_REPORT.md)  
> **Owner**: Orchestrator  
> **Blocker for**: S4 (Synthesis Baseline)  
> **Sign-Off**: ⬜ PENDING — Ready for Approval  

---

## Objective

Systematically triage and resolve all **FPGA-blocking defects** identified in `RISCFORGE_Verification_Plan_RevB.docx`. Defects are classified by their impact on FPGA implementation: synthesis failures, functional incorrectness in silicon, or documentation-only issues.

> [!IMPORTANT]
> Only defects classified **CRITICAL** or **HIGH** with `FPGA-BLOCKER: YES` must be resolved before S4. Other defects are tracked but may be deferred.

---

## Defect Classification Schema

| Class | FPGA Impact | Resolution Requirement |
|:------|:------------|:----------------------|
| **SYNTH-BLOCKER** | Prevents clean synthesis | Must fix before S4 |
| **FUNC-CRITICAL** | Synthesizes but wrong FPGA behavior | Must fix before S7 |
| **LINT-WARNING** | Clean but flagged by lint tools | Fix or waive before S4 |
| **DOC-ONLY** | Comment/documentation error only | Fix anytime |
| **SPEC-OPEN** | Missing specification, RTL incomplete | Track; may be deferred |
| **DEFERRED** | Not required for FPGA bring-up | Track only |

---

## Full Defect Register (from RevB)

### Tier 1: SYNTH-BLOCKER (Must Fix Before S4)

| Defect ID | Severity | File | Description | Status | Fix |
|:----------|:--------:|:-----|:------------|:------:|:----|
| **D-015** | CRITICAL | `apb_uart.sv`, `soc_subsystem.f` | UART OBI chain misrepresented as removed; `apb_uart.sv:52` instantiates hidden chain. Filelist comment is wrong — all OBI files MUST be in compile list | ⬜ OPEN | Correct `soc_subsystem.f` comment; verify `jg_soc.f` has all OBI files |
| **D-114** | HIGH | Multiple `.f` files | 15/40 filelists have unresolvable entries; 2× `timer.sv` conflict; 9 filelists name non-existent directories; 1 machine-absolute path | ⬜ OPEN | Resolved in S0 |

---

### Tier 2: FUNC-CRITICAL (Must Fix Before S7 — Hardware Bring-Up)

| Defect ID | Severity | File | Lines | Description | Status | Fix Plan |
|:----------|:--------:|:-----|:-----:|:------------|:------:|:---------|
| **D-003** | HIGH | `top.v` | 548 | `mip[20:26]` (Timer0 ch0-ch5 overflow) wired at SoC but dropped at core: `fast_intr_core = {4'b0, pend_gateway[5], 7'b0, pend_gateway[3:0]}` leaves bits [10:4] and [15:12] tied to 0 | ⬜ OPEN | Wire `pend_gateway[4]` (Timer1) into `fast_intr_core`; extend IRQ vector |
| **D-006** | HIGH | `csr_regfile.v` | 84-88, 170-177, 189-204 | Shadow stack incomplete: (a) sync exceptions never push; (b) depth-2 silent drop; (c) spec not cited | ⬜ OPEN | Verify FPGA impact — push on sync exception? Accept current behaviour with waiver |
| **D-180** | HIGH | `riscforge_soc_subsystem.sv` | 515 | Watchdog bite path (`aon_timer_rst_req_o`) unconnected; `sys_rst_n_raw` missing OR term | ⬜ OPEN | Add `aon_timer_rst_req_o` to `sys_rst_n_raw` combine (requires AON timer instantiation or stub) |
| **D-169** | MEDIUM | `riscforge_soc_subsystem.sv` | — | AON timer RTL exists (`aon_timer.sv`) but is instantiated nowhere; 14-reg TL-UL interface, wrong bus for APB SoC | ⬜ OPEN | If required: add APB wrapper or stub. If not required: formally exclude from scope |
| **D-008** | HIGH | `Sw/bsp/` | link.ld:12-15 | No `soc_regs.h` — software has no auto-generated register header; linker only covers ISRAM/DSRAM | ⬜ OPEN | Generate `soc_regs.h` from RTL address map; update linker script with MMIO regions |

---

### Tier 3: LINT-WARNING (Fix or Waive Before S4)

| Defect ID | Severity | File | Description | Status | Fix Plan |
|:----------|:--------:|:-----|:------------|:------:|:---------|
| **D-013** | MEDIUM | `apb_pkg.sv` | Self-describes as "APB v2.0" but implements APB4 — stale comment misleads lint tools | ⬜ OPEN | Update comment to "APB4" |
| **D-002** | LOW | Multiple | Several rejected alternative design decisions from Rev A still appear in comments | ⬜ OPEN | Clean up stale comments |
| **D-001** | LOW | Multiple | Rev A wording artifacts ("fired" for assertions, "owning layer" for triage) | ⬜ OPEN | Documentation only |

---

### Tier 4: DOC-ONLY (Fix At Any Time)

| Defect ID | File | Lines | Description | Status |
|:----------|:-----|:-----:|:------------|:------:|
| **D-173** | Multiple | — | Wrong counts in Rev A (25+ registers was 19; 8 monitors was 7; 7 APB windows was 6) | ⬜ Review |
| stale-1 | `riscforge_soc_subsystem.sv` | 1307 | Comment says "Watchdog" — should be "SPI End-of-Transfer" | ⬜ Fix |
| stale-2 | `irq_arbiter.v` | 8,26,54 | Comment says "Watchdog" — should be "SPI End-of-Transfer" | ⬜ Fix |
| stale-3 | `top.v` | 208 | `edge_mode` comment says "Watchdog" — should be "SPI End-of-Transfer" | ⬜ Fix |

---

### Tier 5: SPEC-OPEN (Track; May Be Deferred for FPGA)

| Defect ID | Area | Description | FPGA Impact |
|:----------|:-----|:------------|:------------|
| **D-009** | Compliance | RISCOF test suite snapshot v2.4.4 not current | Simulation only |
| **D-022** | CI | RTL hash / filelist identity checking not implemented | CI only |
| **D-036** | Env | Clock assumption not stated in run record | Simulation only |
| **D-054** | Coverage | Coverage bin waiver ledger not defined | Simulation only |
| **D-014** | Formal | Formal goal ownership undefined | Formal only |
| **D-023** | Phase graph | Phase graph unsatisfiable for G5 at P4 | Sim planning only |
| **D-024** | Regression | Campaign convergence parameters TBD | Sim planning only |
| **D-025** | Volumes | Register/reset/fault-class volumes TBD | Sim planning only |

---

## RTL Fix Tracking

### FIX-001: `top.v` — IRQ Vector Extension (D-003)

**File**: `riscv_core/rtl/top.v:548`  
**Current**:
```verilog
assign fast_intr_core = {4'b0, pend_gateway[5], 7'b0, pend_gateway[3:0]};
// Result: bits [15:12]=0, [11]=SPI, [10:5]=0, [4:0]= I2C,T0,UART,GPIO + 1 more
```

**Issue**: `pend_gateway[4]` (Timer1 IRQ) is never wired. Bits [10:5] are all forced to 0, making Timer0 overflow interrupts `mip[20:26]` unreachable.

**Fix Plan**: Determine intended IRQ mapping. Proposed:
```verilog
assign fast_intr_core = {4'b0, pend_gateway[5], pend_gateway[4], 6'b0, pend_gateway[3:0]};
//                       [15:12]=0, [11]=SPI, [10]=Timer1, [9:4]=0, [3:0]=I2C,T0,UART,GPIO
```

**Status**: ⬜ PENDING — Requires core team sign-off on IRQ map before change

---

### FIX-002: Comment Corrections — Stale "Watchdog" References

**Files**: `soc_subsystem.sv:1307`, `irq_arbiter.v:8,26,54`, `top.v:208`  
**Action**: Replace `Watchdog` with `SPI End-of-Transfer` in comments.  
**Status**: ⬜ PENDING

---

### FIX-003: `apb_pkg.sv` — APB Version Comment (D-013)

**File**: `SOC_FILES/include/apb/apb_pkg.sv`  
**Action**: Change `"APB v2.0 constants"` comment to `"APB4 constants"`.  
**Status**: ⬜ PENDING

---

### FIX-004: AON Timer Scope Decision (D-169, D-180)

**Decision Required**: Is the AON timer in scope for this FPGA implementation?

- **Option A** — Exclude: Add formal scope exclusion note; `aon_timer_rst_req_o` remains unconnected. Accept warm-reset-path limitation.
- **Option B** — Stub: Add a minimal `assign aon_timer_rst_req_o = 1'b1;` tie-off stub in `soc_subsystem.sv` so `sys_rst_n_raw` never asserts due to this. Connect to `sys_rst_n_raw` as `& aon_timer_rst_req_o`.
- **Option C** — Full Integration: Instantiate `aon_timer.sv` with an APB-to-TL-UL bridge. High effort.

**Recommendation**: Option B for FPGA bring-up (tie-off stub), Option C for production.

**Status**: ⬜ DECISION PENDING — Requires human input

---

### FIX-005: soc_regs.h Generation (D-008)

**Description**: No machine-generated register header exists. Firmware uses hand-written `link.ld` with only ISRAM/DSRAM coverage.

**Action**: Generate `Sw/bsp/soc_regs.h` with:
- All APB peripheral base addresses
- All register offsets extracted from `_reg_pkg.sv` headers and RTL files
- MMIO region macros for linker

**Status**: ⬜ PENDING — SW deliverable; does not block synthesis

---

## Decision Log

| Decision ID | Topic | Options | Recommendation | Status |
|:------------|:------|:--------|:---------------|:------:|
| DEC-001 | IRQ vector `top.v:548` fix | Wire `pend_gateway[4]` for Timer1 | FIX-001 above | ⬜ |
| DEC-002 | AON timer scope | Exclude / Stub / Full | Stub (Option B) for FPGA | ⬜ |
| DEC-003 | Shadow stack (D-006) | Accept current 2-deep push-on-IRQ only | Waive for FPGA | ⬜ |

---

## Sign-Off Block

> **To approve Stage 3, the following must all be ✅:**

| Criteria | Status |
|:---------|:------:|
| All SYNTH-BLOCKER defects resolved | ⬜ |
| All FUNC-CRITICAL defects either fixed or formally waived with rationale | ⬜ |
| All LINT-WARNING defects fixed or waived | ⬜ |
| FIX-001 IRQ wiring decision made | ⬜ |
| FIX-004 AON scope decision made | ⬜ |
| RTL re-elaborates cleanly after all fixes (re-run S1 checks) | ⬜ |
| All RTL changes committed with change notes | ⬜ |

**Human Sign-Off**: ⬜ — Type `SIGN OFF: S3` in chat to unlock Stage 4.

