# Stage 3 Proof — Exact Bus Transaction Counts & Monitor Observation

## 1. Executive Summary
- **Stage**: 3 (`stage3_monitor_count`)
- **Execution Timestamp**: 2026-10-24 23:57:36 IST
- **Target Simulator**: AMD Vivado XSim 2022.2 (Local Windows Engine)
- **Git Commit**: [`f1e4661`](https://github.com/raghul7cj/RISCFORGE_1TOPS/commit/f1e46615bdd7688ebf5e7fca3ff8f0a8fd05fa3a) on branch `Raghul`
- **Verdict**: **PASSED** (100% verified across hardware bus monitors, firmware assertions, and scoreboard)
- **Hardware Status**: **100% OPERATIONAL & VERIFIED** (all 18 bus transfers executed with perfect protocol and data integrity, exactly matching 14 reads and 4 writes)

---

## 2. Verification Objectives & Methodology
Stage 3 proves bus observability, bidirectional accounting, and directional isolation:
1. **DSRAM Isolation**: 20 stores followed by sequential forward and backward read-back sweeps to guarantee store retirement, read-back consistency, and no spurious MMIO/APB traffic during DSRAM accesses.
2. **Seed-Dependent Checksum**: Multi-word non-linear signature verification on scratch memory (`0xA459670A` computed and verified).
3. **Multi-Aperture APB Round-Trips**: Prove read-modify-write capability across at least 2 distinct APB slots (I2C at slot 0, Timer 0 at slot 1).
4. **Sustained Read Bursts**: 8 back-to-back read transactions on Timer 1 (slot 5) to test bridge throughput and FIFO stability without dropped beats.
5. **Bidirectional Cross-Check**:
   - Firmware counts operations it verified in memory (`proof_mmio_reads = 14`, `proof_mmio_writes = 4`).
   - Hardware monitors independently count AXI-Lite AR/AW beats and APB PSEL/PENABLE/PREADY cycles.
   - Exact matching between firmware counters and hardware monitor beats proves zero ghost transactions and zero dropped operations.

---

## 3. Hardware Datapath & Bus Monitor Evidence
The hardware buses and slave peripherals executed with complete protocol compliance and zero errors:

### AXI4-Lite Activity (Independent HW Monitor)
- **Total Writes**: 4 (2 to I2C PRER at `0x4000_0000`, 2 to Timer 0 CMP at `0x4000_1008`)
- **Total Reads**: 14 (3 from I2C, 3 from Timer 0, 8 from Timer 1)
- **Responses**: All returned `BRESP = 2'b00` (OKAY) and `RRESP = 2'b00` (OKAY).

### APB Activity (18 Transfers Total)
- All 18 APB transfers routed to the exact apertures:
  - Slot 0 (I2C): 2 writes, 3 reads
  - Slot 1 (Timer 0): 2 writes, 3 reads
  - Slot 5 (Timer 1): 8 reads
- Every transfer answered with `PSLVERR = 0`.
- Data was read back with 100% bit-exact accuracy.

---

## 4. Root Cause Analysis & Resolution of Counter Discrepancy
### The Observed Anomaly
In previous runs:
- `proof_mmio_reads` reached only 12 (expected 14).
- `proof_mmio_writes` had corrupted value `0x00010001` (expected 4).

### Hardware Root Cause Isolated
In [`ips/riscv_core/rtl/hazard_unit.v`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/hazard_unit.v):
- When an MMIO access was issued over AXI-Lite/APB, `mem_stall_i` was asserted to freeze the pipeline while awaiting the multi-cycle response.
- If the instruction immediately following in EX was a load from DSRAM (`lw a5, 732(a3)` or `lw a5, 736(a2)`), and the subsequent instruction in ID depended on `a5`, `lwstall` asserted.
- `hazard_unit.v` originally computed `FlushE = lwstall | ...` without gating `lwstall` with `~mem_stall_i`.
- In `decode_cycle.v`, `if (FlushE)` had priority over `else if (StallE)`. Thus, during the memory stall, the load instruction waiting in EX was flushed to all-zeros (NOP)!
- Consequently, the load was skipped, `a5` retained stale data from previous operations (e.g. `0x0001_0000` from Timer 0 CMP), and the subsequent increment corrupted `proof_mmio_writes` to `0x0001_0001` and dropped 2 reads from `proof_mmio_reads` ($14 - 2 = 12$).

### Resolution
In `hazard_unit.v`:
```verilog
assign FlushE = (lwstall & ~mem_stall_i) | (csr_gpr_stall & ~mem_stall_i) | PCSrcE | (csr_stall & ~mem_stall_i) | exc_inflight_M | wb_redirect | flush_pipeline_onehot[1] | stallMUL;
```
Gating `lwstall` with `~mem_stall_i` ensures that data hazard bubbles are not inserted into EX while EX is frozen by a memory stall. With this fix:
- `proof_mmio_reads` = 14
- `proof_mmio_writes` = 4
- `slots_touched` = `0x00000023` (slots 0, 1, 5)
- Firmware assertion passed cleanly, and `[MAILBOX PASS]` was confirmed by the testbench.

---

## 5. Artifact Manifest
- `manifest.json`: Full machine-readable run metadata, tool versions, and SHA-256 hashes.
- `logs/stage3_monitor_count_sim.log`: Raw simulator execution log with `[MAILBOX PASS]` and metrics.
- `stimuli/stage3_monitor_count.elf`: Compiled RISC-V ELF binary.
- `stimuli/stage3_monitor_count_imem.hex`: ISRAM hex stimulus image.
- `stimuli/stage3_monitor_count_dmem.hex`: DSRAM hex stimulus image.
- `stimuli/stage3.dis`: Full disassembly listing.
