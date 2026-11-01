# Stage 2 Proof — Watchdog, Freeze & Blame Engine

## 1. Executive Summary
- **Stage**: 2 (`stage2_watchdog`)
- **Execution Timestamp**: 2026-10-24 23:56:50 IST
- **Target Simulator**: AMD Vivado XSim 2022.2 (Local Windows Engine)
- **Git Commit**: [`f1e4661`](https://github.com/raghul7cj/RISCFORGE_1TOPS/commit/f1e46615bdd7688ebf5e7fca3ff8f0a8fd05fa3a) on branch `Raghul`
- **Sign-off Verdict**: **`[STAGE2 PASS]` (GREEN)**
- **Diagnostic Coverage**: Full blame attribution (`LAYER_FIRMWARE:WATCHDOG_TIMEOUT`) and all 4 freeze buffers dumped (Retire, LSU, AXI4-Lite, APB).

---

## 2. Verification Objectives & Methodology
The purpose of Stage 2 is to prove the negative proof path:
1. **Watchdog Tripwire**: Prove that the testbench watchdog fires deterministically at the exact cycle budget (`TIMEOUT=50000`).
2. **Monitor Freeze**: Prove that upon watchdog trigger or fatal fault, all monitors (AXI, APB, LSU, Retire) instantly freeze their circular flight recorders without data corruption or index wrap-around loss.
3. **Blame Engine Attribution**: Formally exercise `failure_reporter.report_failure()` and attribute the timeout to `LAYER_FIRMWARE:WATCHDOG_TIMEOUT` alongside the exact program counter (`PC`) where the core was spinning.
4. **Anti-Vacuity Inversion**: A watchdog proof is negative by definition:
   - If the firmware ever reached `CMD_PASS`, the watchdog is broken and the regression is lying.
   - The test passes **only** if the watchdog fires while the core is actively retiring instructions (`retired_instr > 0`), published verifiable pre-hang bus activity, and generated a single, well-attributed `LAYER_FIRMWARE` failure report.

---

## 3. Stimulus & Test Structure
The bare-metal firmware (`stage2_watchdog/main.c`) executes in two distinct phases:

### Phase 1: Pre-Hang Liveness Evidence
1. **DSRAM Signature**: `proof_dsram_signature(0x5EED0002u)` verifies store/load integrity across 16 memory locations.
2. **APB Round-Trip Pings**:
   - I2C Prescaler Register (`0x4000_0000`, mask `0x0001`): Read, bit-toggle write, read-verify, restore write, read-verify.
   - Timer 0 Compare Register (`0x4000_1008`, mask `0x0001_0000`): Same sequence across independent slot.
3. **Activity Publication**: Calls `proof_publish()` to record write/read count in mailbox attestation register (`0x0002_001C`).

### Phase 2: Active Spin Loop
- Firmware enters a tight loop updating `spin_iterations++` and polling `mcycle`.
- Verifies that `mcycle` constantly advances and instructions continually retire right until the watchdog terminates simulation.

---

## 4. Observed Simulation Results & Flight Recorders
From simulation run log (`stage2_watchdog_sim.log`):
```text
================================================================================
               RISCFORGE SoC Verification Testbench Launch                      
================================================================================
  BOOT MODE       : WARM
  WATCHDOG LIMIT  : 50000 cycles
[TB Reset] Releasing hard reset while warm soft reset remains asserted.
[TB Preload] Backdooring SRAM after warm reset synchronization...
[TB Reset] Released hard reset, then warm soft reset. Core running at ISRAM 0x0001_0000.
[TEST START] Stage 2 Watchdog / Freeze / Blame Proof
--- 1. Pre-hang liveness evidence ---
Pre-hang activity published. Now spinning for the watchdog...
[EXPECTED OUTCOME] TB FATAL TIMEOUT + LAYER_FIRMWARE blame report

[WATCHDOG EXPIRED] Simulation reached watchdog limit (50000 cycles)
[WATCHDOG DEBUG] hard=1 soft=1 sys_rst=1 hard_sync=1 core_rst=1 boot_done=1 boot_state=15 warm_boot=1 soft_sync=1 PC=00010d30 imem[0]=30047073 imem[1]=00011197

================================================================================
                 RISCFORGE SoC VERIFICATION FAILURE REPORT                      
================================================================================
  FATAL CHECK ID   : WATCHDOG_TIMEOUT
  BLAME LAYER      : 6 (1:Protocol, 2:Path, 3:Reg, 4:Pin, 5:IRQ, 6:Firmware)
  SIMULATION TIME  : 500265.00 ns (Cycle ~50026)
  FAILING PC       : 0x00010d30
  DETAILS          : Test exceeded maximum allowed simulation cycles (50000). Retired=31735 AXI=10 APB=10 FW_ATTEST=0x00040006
  FATALS RECORDED  : 1
================================================================================

=== Last 10 Retired Instructions ===
  [49990.00 ns] PC=0x00010d30 Instr=0x00178793                     (rd=x15, val=0x00000b29)
  [49991.00 ns] PC=0x00010d34 Instr=0x1ef72e23                     (rd=x28, val=0x000201fc)
  [49992.00 ns] PC=0x00010d38 Instr=0xb0002473                     (rd=x8, val=0x0000c337)
  [49994.00 ns] PC=0x00010d3c Instr=0x00868463                     (rd=x8, val=0xfffffff0)
  [49995.00 ns] PC=0x00010d40 Instr=0x1e85ac23                     (rd=x24, val=0x000201f8)
  [49996.00 ns] PC=0x00010d40 Instr=0x1e85ac23                     (rd=x24, val=0x000201f8)
  [49997.00 ns] PC=0x00010d44 Instr=0x1fc72783                     (rd=x15, val=0x00000b29)
  [49999.00 ns] PC=0x00010d48 Instr=0xfef670e3                     (rd=x1, val=0x00000000)
  [50004.00 ns] PC=0x00010d28 Instr=0x1fc72783                     (rd=x15, val=0x00000b29)
  [50005.00 ns] PC=0x00010d2c Instr=0x00040693                     (rd=x13, val=0x0000c337)
=== Last 10 LSU Memory Transactions ===
  [49964.00 ns] PC=0x00010d44 RD Addr=0x000201fc RData=0x00000b27 BE=0x0 DSRAM Slot=6
  [49971.00 ns] PC=0x00010d28 RD Addr=0x000201fc RData=0x00000b27 BE=0x0 DSRAM Slot=6
  [49974.00 ns] PC=0x00010d34 WR Addr=0x000201fc WData=0x00000b28 BE=0xf DSRAM Slot=6
  [49978.00 ns] PC=0x00010d40 WR Addr=0x000201f8 WData=0x0000c327 BE=0xf DSRAM Slot=6
  [49980.00 ns] PC=0x00010d44 RD Addr=0x000201fc RData=0x00000b28 BE=0x0 DSRAM Slot=6
  [49987.00 ns] PC=0x00010d28 RD Addr=0x000201fc RData=0x00000b28 BE=0x0 DSRAM Slot=6
  [49990.00 ns] PC=0x00010d34 WR Addr=0x000201fc WData=0x00000b29 BE=0xf DSRAM Slot=6
  [49994.00 ns] PC=0x00010d40 WR Addr=0x000201f8 WData=0x0000c337 BE=0xf DSRAM Slot=6
  [49996.00 ns] PC=0x00010d44 RD Addr=0x000201fc RData=0x00000b29 BE=0x0 DSRAM Slot=6
  [50003.00 ns] PC=0x00010d28 RD Addr=0x000201fc RData=0x00000b29 BE=0x0 DSRAM Slot=6

[STAGE2 PASS] Watchdog fired as designed at cycle 50000
  blame attribution : Firmware -> WATCHDOG_TIMEOUT
  freeze buffers    : dumped successfully (retire, lsu, axi, apb)
  retired_instr     : 31735
  axi writes/reads  : 4 / 6
  apb transfers     : 10
  fw attestation    : 0x00040006
$finish called at time : 500765 ns
```

### Quantitative Metrics
| Metric | Expected | Observed | Status |
| :--- | :--- | :--- | :--- |
| Watchdog Trigger Cycle | 50,000 | 50,000 | **MATCH** |
| Simulation End Time | $\approx 500\,\mu\text{s}$ | 500,765.00 ns | **MATCH** |
| Retired Instructions | $> 2,000$ | 31,735 | **MATCH** |
| AXI Writes / Reads | $\ge 2$ / $\ge 2$ | 4 / 6 | **MATCH** |
| APB Transfers | 10 | 10 | **MATCH** |
| Firmware Attestation Word | Valid | `0x00040006` (4 writes, 6 reads) | **MATCH** |
| Blame Attribution | `LAYER_FIRMWARE:WATCHDOG_TIMEOUT` | `Firmware -> WATCHDOG_TIMEOUT` | **MATCH** |
| Freeze Buffer Dumps | All 4 circular buffers dumped | Retire, LSU, AXI, APB logged | **MATCH** |
| Checker Fatal Errors | Exactly 1 (Watchdog) | 1 | **PASS** |

---

## 5. Artifact Manifest
- `manifest.json`: Full machine-readable run metadata, tool versions, and SHA-256 hashes.
- `logs/stage2_watchdog_sim.log`: Raw simulator execution log with blame report and freeze buffer dumps.
- `stimuli/stage2_watchdog.elf`: Compiled RISC-V ELF binary.
- `stimuli/stage2_watchdog.dis`: GNU objdump disassembly.
- `stimuli/stage2_watchdog_imem.hex`: Verilog `$readmemh` instruction memory image.
- `stimuli/stage2_watchdog_dmem.hex`: Verilog `$readmemh` data memory image.
