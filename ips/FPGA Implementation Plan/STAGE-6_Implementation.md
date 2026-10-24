# STAGE 6 — Place & Route, Timing Closure & DRC
**FPGA-PLAN-S6 | Blocked on S5 Sign-Off**

> **Status**: ⏳ BLOCKED — Waiting for S5 sign-off  
> **Target**: Nexys4 DDR (`xc7a100tcsg324-1`)  
> **Tool**: Vivado 2022.2 Implementation Flow  
> **Sign-Off**: ⬜ PENDING

---

## Objective

Execute full implementation flow: `opt_design`, `place_design`, `phys_opt_design`, `route_design`, and post-route design rule check (DRC) & timing closure verification.

---

## Implementation Stages & Tcl Commands

```tcl
# 1. Logic Optimization
opt_design -directive Explore

# 2. Placement
place_design -directive Explore

# 3. Physical Logic Optimization (post-place)
phys_opt_design -directive Explore

# 4. Routing
route_design -directive Explore

# 5. Timing Closure Verification
report_timing_summary -max_paths 10 -file reports/s6_timing_summary.rpt
report_timing -delay_type min_max -max_paths 20 -file reports/s6_worst_paths.rpt

# 6. DRC & Methodology Checks
report_drc -file reports/s6_drc.rpt
report_methodology -file reports/s6_methodology.rpt
```

---

## Timing Closure Acceptance Criteria

| Timing Metric | Threshold Requirement | Goal |
|:--------------|:---------------------:|:----:|
| **WNS** (Worst Negative Slack) | $\ge 0.000\,\text{ns}$ | Positive margin (> 0.5 ns) |
| **TNS** (Total Negative Slack) | $0.000\,\text{ns}$ | Clean closure |
| **WHS** (Worst Hold Slack) | $\ge 0.000\,\text{ns}$ | No hold violations |
| **THS** (Total Hold Slack) | $0.000\,\text{ns}$ | Clean hold |
| Unconstrained paths | 0 endpoints | 100% constrained |

---

## Findings Log

| Finding ID | Phase | Issue Description | Severity | Status |
|:-----------|:------|:------------------|:--------:|:------:|
| S6-F001 | — | Pending S6 execution | — | ⏳ |

---

## Sign-Off Block

| Criteria | Status |
|:---------|:------:|
| `opt_design` and `place_design` complete cleanly | ⬜ |
| `route_design` complete with 0 unrouted nets | ⬜ |
| Post-route WNS $\ge 0.0\,\text{ns}$ and WHS $\ge 0.0\,\text{ns}$ | ⬜ |
| `report_drc` shows 0 errors and 0 critical warnings | ⬜ |
| `report_methodology` violations reviewed and clean | ⬜ |

**Human Sign-Off**: ⬜ — Type `SIGN OFF: S6` in chat to unlock Stage 7.

