# Original User Request

## 2026-10-01T20:58:50Z

Deployment and sign-off of the complete SoC-level verification infrastructure for the RISCFORGE RV32IM_Zicsr subsystem, including passive monitors, checkers, failure reporter, peripheral register predictor, and ISS reference model co-simulation.

Working directory: c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips

## Requirements

### R1. Passive Protocol & Pipeline Monitors with Circular Freeze Buffers
Maintain 64-entry non-intrusive circular history ring buffers across Fetch, Retire (RVFI), LSU, AXI4-Lite, APB 6-Slot, and IRQ lines, freezing all buffers simultaneously on the first failing assertion or trap.

### R2. Deterministic Checkers & End-to-End Scoreboards
Execute protocol formal assertions (AXI/APB SVAs), end-to-end MMIO path scoreboard (LSU → AXI → APB Slot mapping), and vacuous pass prevention across bare-metal C proof suites.

### R3. Peripheral Register Predictor & Reference Models
Provide independent reference models for peripheral register states (RW, RO, W1C, atomic SET/CLEAR/TOGGLE) and 2-level priority class interrupt arbitration independent of RTL implementation.

### R4. Dual Simulator Build & Regression Harness
Support both remote Synopsys VCS / Cadence Xcelium flow (`run_vcs.sh` / `soc_verification.f`) and local Windows AMD Vivado XSim flow (`run_regression.ps1` / `soc_verification.prj`).

## Acceptance Criteria

### Infrastructure Readiness & Debug Observability
- [ ] All 6 passive monitors instantiate and log transactions without exerting backpressure or altering RTL timing.
- [ ] First-fatal blame engine produces a structured 1-page markdown diagnostic failure report naming layer, check ID, and last 10 instructions.
- [ ] Peripheral Register Predictor flags any unexpected MMIO read value with exact expected vs actual data.
- [ ] Interrupt Predictor flags any out-of-order grant, illegal preemption, or shadow stack overflow.
- [ ] All 7 proof stages pass with zero vacuous passes.
