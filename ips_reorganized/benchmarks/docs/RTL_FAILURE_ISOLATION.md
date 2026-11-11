# Benchmark failure isolation — 4 November 2026

Three behaviors were reproduced in fresh full-SoC XSim 2022.2 runs with the existing benchmark testbench and `--waves`. No design RTL, testbench, benchmark source, or validation expectation was changed. New files are documentation and offline waveform-analysis scripts only. All 109 original design-baseline hashes still match.

These are observed failure mechanisms, not proposed fixes. The short instruction excerpts below were extracted from the executed ELF disassembly; they are **not separately executed minimal tests**. Full ELF/images, logs, configuration, source hashes and VCD are retained in the listed run directories.

## 1. Completed MDU result loses architectural validity

**Observed:** multiply/divide/remainder units produce results, but the completion packet has `valid_M=0`, then `valid_W=0`; the register-file write is suppressed. This occurred for all 10 observed smoke completions, all 5 CoreMark completions, and all 3 completed Dhrystone operations before its trap.

Relevant RTL:

```verilog
// hazard_unit.v:173,192,199
assign StallE = wb_redirect ? 1'b0 : (mem_stall_i);
// The full FlushE expression includes: ... | stallMUL;
assign FlushM = wb_redirect | flush_pipeline_onehot[2] | stallMUL;

// decode_cycle.v:273,297 — in the FlushE branch
valid_E_r <= 1'b0;

// execute_cycle.v:329-331 — completion restores destination/write intent
wire [4:0] RD_E1 = (m_valid_out) ? rd_me : RD_E;
wire RegWriteE1 = (is_M_instruction_E && !m_valid_out) ? 1'b0 :
                 (m_valid_out) ? 1'b1 : RegWriteE;

// execute_cycle.v:424 — packet validity still follows cleared EX validity
valid_M_r <= valid_E;

// top.v:285 — invalid completion cannot update the register file
assign RegWriteW_gated = RegWriteW & valid_W & ~exc_valid_W & ~mret_commit;
```

**Trigger:** a normal multi-cycle M instruction starts, `stallMUL` flushes EX, and completion arrives while `valid_E=0`. This also occurs with `StallM=0`; an overlapping memory wait is not required for this failure.

Concrete smoke sequence:

```asm
0x1094c: lw   s3,8(sp)       # 0x6789
0x10950: lw   a4,12(sp)      # 0x12345
0x10954: lw   s2,0(sp)
0x10958: lw   a5,4(sp)
0x1095c: mul  s3,s3,a4
0x10960: lw   s4,0(sp)
```

Pre-rising-edge observations (times in ns from simulation origin):

| Time | Observation |
| --- | --- |
| 7695 | MDU accepts `mul`, operands `0x6789`, `0x12345`, destination x19. |
| 7725 | `m_valid_out=1`, result `0x75cca2ed` (correct), destination x19; `valid_E=0`, `FlushM=0`, `StallM=0`. |
| 7735 | `RegWriteM=1`, destination x19, but `valid_M=0`. |
| 7745 | WB data `0x75cca2ed`, destination x19; `valid_W=0`, `RegWriteW_gated=0`. |

This isolates transport/validity failure for this multiplication; the observed multiplier arithmetic is correct. It does not qualify every MDU operation or all operand cases.

### CoreMark consequence

`0x11284: divu a1,a1,a4` receives 2000 and 3 and produces 666, but the result is invalid at WB. The following size store therefore uses stale a1=2000. Later:

```asm
0x11408: mul  a4,a2,a1
0x1140c: addi a2,a2,1
0x11410: slli a2,a2,16
0x11414: srli a2,a2,16
0x11418: add  a4,a6,a4
0x1141c: sw   a4,12(a3)
```

The first `mul` receives 0 and 2000 and produces 0, again invalid at WB. At 42325 ns the `add` uses base `a6=0x2092c` and **stale a4=1**, creating `0x2092d`. This pointer is later loaded into a1 at PC `0x112c8` and supplied to `core_list_init`. Its `0x10fa4: sw zero,0(a1)` traps with cause 6 and address `0x2092d`. Thus the pointer is already wrong before the faulting store; changing pointer alignment in software would hide the symptom.

### Dhrystone consequence

```asm
0x10074: remu a3,a0,a1      # 100000000 % 10 = 0
0x10078: addi a4,a4,1
0x1007c: add  a5,a6,a4
0x10080: addi a2,a0,0
0x10084: add  a3,a7,a3      # digit-table base + remainder
0x10088: lbu  a3,0(a3)
0x1008c: divu a0,a0,a1
```

At 224315 ns `remu` produces 0; WB validity is zero at 224335 ns. At 224355 ns the table-address add uses stale a3=9, creating `0x2011d`. The `divu` later produces 10000000, also invalid at WB; the next loop still receives a0=100000000. The next `remu` result is again suppressed, so the add at 225185 ns uses stale a3=`0x2011d` and base `0x20114`, creating `0x40231`. The following byte load traps. The quotient/remainder arithmetic observed here is correct for the accepted inputs.

## 2. MDU start flushes an older waiting load

**Observed independently of completion:** a younger M instruction begins while a valid older load is held in EX/MEM. Both `StallM` and `FlushM` are 1. The EX/MEM register gives flush priority and clears the older load before it reaches valid WB.

Relevant RTL:

```verilog
// hazard_unit.v:175,199
assign StallM = wb_redirect ? 1'b0 : mem_stall_i;
assign FlushM = wb_redirect | flush_pipeline_onehot[2] | stallMUL;

// execute_cycle.v:368-389 — existing priority
end else if (FlushM) begin
    // clears EX/MEM registers, including:
    valid_M_r <= 1'b0;
    // ...
end else if (StallM) begin
    // holds EX/MEM
```

**Trigger:** older load waiting in MEM, younger multiply/divide in EX, `stallMUL=1` and `mem_stall_i=1` on the same edge. Reproduced twice in smoke and once in Dhrystone. CoreMark does not show this overlap before its trap, so it is not needed to explain the CoreMark failure.

Smoke at 7695 ns: older `0x10958: lw a5,4(sp)` targets x15, address `0x27fd4`; younger `0x1095c: mul s3,s3,a4` starts. `valid_M=1`, `StallM=1`, `FlushM=1`. At 7705 ns the MEM packet is cleared (`valid_M=0`, PC=0). The intended a5 load never becomes valid WB.

Later `0x10968: divu s2,s2,a5` accepts `0x12345678 / 0x9a` at 7765 ns, rather than division by the stored divisor `0x1357`. Its result `0x1e430e` is **correct for divisor 0x9a**, but also loses completion validity under finding 1. This distinguishes incorrect input delivery from a divider arithmetic failure in this trace. A second overlap clears the load into s5 at `0x10964`.

Dhrystone at 224375 ns: older `0x10088: lbu a3,0(a3)` waits in MEM while younger `0x1008c: divu a0,a0,a1` starts; MEM is cleared on the next edge. The digit byte never replaces the address in a3, contributing to the next invalid table index. Both findings 1 and 2 are active in this chain; no patched counterfactual run was made to assign exclusive causality.

## 3. Held WB packet increments minstret repeatedly

Relevant RTL:

```verilog
// memory_cycle.v:260 — holds ALL MEM/WB registers, including valid_W_r
else if (core_stall_gated) begin
    // Hold all MEM->WB registers during memory stall.
end

// top.v:572 — CSR retirement input has no consume/hold qualification
.instr_retired_i(valid_W & ~exc_valid_W),

// csr_regfile.v:154
if (instr_retired_i) minstret_r <= minstret_r + 1'b1;
```

**Trigger:** memory stall with a valid, non-excepting packet already in WB. MEM/WB holds the packet while the CSR increments on each clock.

Actual smoke instruction context:

```asm
0x10920: add a4,a1,a4
0x10924: sw  a2,0(a4)
0x10928: lw  a5,0(a4)
0x1092c: lw  a4,0(a4)
```

| Time (ns) | WB PC | StallM | valid_W | minstret before edge |
| --- | --- | --- | --- | --- |
| 6095 | 0x10924 | 1 | 1 | 315 |
| 6105 | 0x10924 | 0 | 1 | 316 |
| 6115 | 0x10928 | 1 | 1 | 317 |

At both 6095 and 6105 ns the retirement input is 1 for the same **held pipeline packet**, not simply a coincidentally repeated program address. It increments on both edges. The full-run waveform checks detect 82 such held edges in smoke, 12 in CoreMark, and 183 in Dhrystone. These are observed held-packet increments, not a complete architectural retirement oracle or a correction factor for reported counts.

## Reproduction and evidence

From repository root, rerun each existing firmware image unchanged:

```powershell
.\ips\benchmarks\benchmark.ps1 -Action Run -Benchmark smoke -TimeoutCycles 2000000 -Waves
.\ips\benchmarks\benchmark.ps1 -Action Run -Benchmark coremark -TimeoutCycles 2000000 -Waves
.\ips\benchmarks\benchmark.ps1 -Action Run -Benchmark dhrystone -TimeoutCycles 2000000 -Waves
```

These commands are expected to report failures. `Run` uses iterations from the existing build manifest (1/1/10 respectively); it does not rebuild or change benchmark software. A matching source checkout is required by preflight. The new inspection campaign used the same Python runner with `--output-dir ips/benchmarks/runs/isolation`, `--wall-timeout-seconds 180`, and `--waves`.

| Workload | Fresh run under `ips/benchmarks/runs/isolation/` | Outcome |
| --- | --- | --- |
| Smoke | `smoke_20261104T113155Z_f7e5a503` | Same 3 arithmetic errors, expected sum 2980 / observed 1016. |
| CoreMark | `coremark_20261104T113222Z_030e35af` | Same store-misaligned trap, PC 0x10fa4 / address 0x2092d. |
| Dhrystone | `dhrystone_20261104T113308Z_2036a556` | Same load-access trap, PC 0x10088 / address 0x40231. |

Each run contains `waves.vcd`, `core_cycles.csv`, `trace_extraction.json`, `program.elf`, `program.dis`, SRAM hex files, `result.json`, `simulation.log`, source fingerprints and run metadata. Waveforms use 1 ps units. CSV values are decimal and sampled immediately before each rising edge, so the next row shows the register update from the current row's edge.

Compact evidence in `docs/evidence/isolation/`:

- `smoke_windows.csv`, `coremark_windows.csv`, `dhrystone_windows.csv`: focused edge-by-edge windows.
- `findings.json`: issue/completion pairs, lost MEM packets, held-WB increments, artifact SHA256 values and unchanged-design check.
- `extract_cycles.py`: reproducible VCD extraction, standard Python library only.
- `collect_findings.py`: reproducible evidence checks and focused CSV generation, standard Python library only.

To repeat extraction, pass each run directory to `extract_cycles.py`; then run `collect_findings.py` from the repository root. The latter intentionally names this campaign's retained runs. Its checks passed for all three runs.

**Limits:** no RTL or testbench fixes, reduced standalone assembly tests, formal proof, or alternate-simulator comparison were performed. The existing XSim assertion-selection limits still apply. These waveforms isolate concrete RTL mechanisms in the executed workloads; they do not prove those are the only core defects. No benchmark score or exact retirement qualification is established.
