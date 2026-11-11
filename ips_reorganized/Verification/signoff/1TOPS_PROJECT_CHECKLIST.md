# 1-TOPS Project Signoff Checklist — Markdown index

**Source:** user-supplied `1TOPS_Project_Signoff_Checkl.xlsx` (2026-11-02). This Markdown index mirrors the **124 checklist item IDs and names** for GitHub browsing. The original `.xlsx` contains the detailed acceptance criteria, tools, owner, approvals and formulas and **is not replaced by this index**.

**Official status (refreshed 11 Nov 2026):** statuses below are read from the current official workbook (`1TOPS OFFICIAL DELIVERABLES/1TOPS_Project_Signoff_Checkl.xlsx`, last modified 2 Nov 2026 23:06, SHA-256 `d14dab56e3c358ad...06bffa`). The earlier version of this index showed every item as `Not Started`, which matched the original workbook before it was updated. Repository evidence cannot independently assign coach approval. Per-responsibility tracking for CJ: [CJ_RESPONSIBILITY_TRACKER.md](../../documentation/signoff/CJ_RESPONSIBILITY_TRACKER.md). The companion [evidence audit](README.md) makes partial/blocked findings explicit.

## G0

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 0.1 | Front-end tools installed and licensed | (blank) |
| 0.2 | Back-end tools installed and licensed | (blank) |
| 0.3 | RISC-V GNU toolchain installed | (blank) |
| 0.4 | Spike ISS built for your ISA | (blank) |
| 0.5 | 28 nm PDK, standard cells, SRAM macros and IO library received | (blank) |
| 0.6 | Version control in place | In Progress |
| 0.7 | Regression runnable by one command | In Progress |

## G1

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 1.1 | Core ISA frozen | In Progress |
| 1.2 | Pipeline depth frozen | In Progress |
| 1.3 | Privilege modes frozen | In Progress |
| 1.4 | CSR list frozen | In Progress |
| 1.5 | Trap and interrupt model defined | In Progress |
| 1.6 | Memory organisation frozen | In Progress |
| 1.7 | SoC block diagram approved | In Progress |
| 1.8 | Address map frozen | In Progress |
| 1.9 | Interrupt map frozen | In Progress |
| 1.10 | Clock and reset architecture defined | In Progress |
| 1.11 | Pin list / chip IO table frozen | In Progress |
| 1.12 | Boot plan defined | In Progress |
| 1.13 | Micro-architecture document complete | In Progress |
| 1.14 | Verification plan (testplan) written | In Progress |
| 1.15 | Area, frequency and power targets stated | (blank) |

## G2

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 2.1 | PC generation unit coded | Done |
| 2.2 | Decoder and control unit coded | In Progress |
| 2.3 | Register file coded | In Progress |
| 2.4 | ALU coded | Done |
| 2.5 | Branch unit coded | Done |
| 2.6 | MDU coded (if M extension) | In Progress |
| 2.7 | Memory interface unit coded | In Progress |
| 2.8 | Hazard and forwarding logic coded | In Progress |
| 2.9 | CSR block and trap logic coded | In Progress |
| 2.10 | Compressed decoder coded (if C extension) | (blank) |
| 2.11 | RTL coding rules followed | In Progress |
| 2.12 | Core lint clean | In Progress |
| 2.13 | Core CDC clean | (blank) |

## G3

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 3.1 | GPIO integrated (mandatory) | In Progress |
| 3.2 | UART integrated (mandatory) | In Progress |
| 3.3 | SPI / QSPI master integrated (mandatory) | In Progress |
| 3.4 | PLIC integrated (mandatory) | (blank) |
| 3.5 | Timer integrated (mandatory) | In Progress |
| 3.6 | CLINT / CLIC integrated (mandatory) | (blank) |
| 3.7 | I2C integrated (optional) | In Progress |
| 3.8 | I2S integrated (optional) | (blank) |
| 3.9 | Boot ROM integrated | In Progress |
| 3.10 | SRAMs integrated | In Progress |
| 3.11 | Interconnect integrated | In Progress |
| 3.12 | System control block integrated | In Progress |
| 3.13 | Address decode matches G1 map | In Progress |
| 3.14 | Top-level SoC lint clean | In Progress |
| 3.15 | SoC CDC and RDC clean | (blank) |
| 3.16 | Unconnected / floating nets checked | In Progress |

## G4

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 4.1 | Unit TB for PC unit | (blank) |
| 4.2 | Unit TB for decoder / control | (blank) |
| 4.3 | Unit TB for register file | (blank) |
| 4.4 | Unit TB for ALU | In Progress |
| 4.5 | Unit TB for branch unit | (blank) |
| 4.6 | Unit TB for MDU | (blank) |
| 4.7 | Unit TB for MIU | In Progress |
| 4.8 | Unit TB for hazard logic | In Progress |
| 4.9 | Unit regression 100% pass | (blank) |
| 4.10 | Core sanity TB built | In Progress |
| 4.11 | Core sanity tests pass | In Progress |
| 4.12 | Reset and interrupt entry verified | In Progress |
| 4.13 | Hazard tests pass at core level | (blank) |
| 4.14 | Core sanity coverage met | (blank) |

## G5

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 5.1 | ISS comparison flow working | In Progress |
| 5.2 | Official RISC-V ISA tests pass | In Progress |
| 5.3 | Privileged / trap tests pass | In Progress |
| 5.4 | riscv-dv integrated | (blank) |
| 5.5 | riscv-dv regression stable | (blank) |
| 5.6 | Memory latency randomisation run | (blank) |
| 5.7 | Benchmarks run | (blank) |
| 5.8 | Functional coverage closed at core level | In Progress |
| 5.9 | Code coverage >= 95% on core | (blank) |
| 5.10 | Core bug list closed | In Progress |

## G6

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 6.1 | UVM SoC testbench built | In Progress |
| 6.2 | Register tests pass | In Progress |
| 6.3 | Register field coverage closed | (blank) |
| 6.4 | Per-IP use cases pass | In Progress |
| 6.5 | Interrupt path verified end to end | In Progress |
| 6.6 | Bus bridge protocol verified | In Progress |
| 6.7 | Memory map decode verified | In Progress |
| 6.8 | Traffic stress run | (blank) |
| 6.9 | Boot from internal ROM passes | In Progress |
| 6.10 | Boot from external SPI flash passes | In Progress |
| 6.11 | SRAM load / ROM remap boot passes | In Progress |
| 6.12 | Bare-metal C test suite passes | In Progress |
| 6.13 | Trap robustness under load passes | (blank) |
| 6.14 | SoC random and stress tests pass | In Progress |
| 6.15 | SoC functional coverage closed | In Progress |
| 6.16 | SoC code coverage >= 95% | (blank) |
| 6.17 | Full regression clean | In Progress |
| 6.18 | No deadlocks in long runs | (blank) |
| 6.19 | RTL frozen for synthesis | (blank) |

## G7

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 7.1 | SDC constraints written | (blank) |
| 7.2 | Synthesis runs clean | (blank) |
| 7.3 | Timing met post-synthesis | (blank) |
| 7.4 | Area within budget | (blank) |
| 7.5 | DFT inserted | (blank) |
| 7.6 | ATPG coverage met | (blank) |
| 7.7 | Gate-level simulation passes | (blank) |
| 7.8 | Post-synthesis LEC clean | (blank) |

## G8

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 8.1 | Floorplan complete | (blank) |
| 8.2 | Power plan complete | (blank) |
| 8.3 | Placement complete | (blank) |
| 8.4 | CTS complete | (blank) |
| 8.5 | Routing complete | (blank) |
| 8.6 | Post-route STA signoff | (blank) |
| 8.7 | Post-layout LEC clean | (blank) |
| 8.8 | DRC clean | (blank) |
| 8.9 | LVS clean | (blank) |
| 8.10 | Antenna and DFM checks clean | (blank) |
| 8.11 | IR / EM signoff | (blank) |
| 8.12 | Post-layout gate simulation passes | (blank) |

## G9

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 9.1 | GDSII generated | (blank) |
| 9.2 | Sealring, fill and logo added | (blank) |
| 9.3 | Foundry tape-out checklist completed | (blank) |
| 9.4 | Test patterns delivered | (blank) |
| 9.5 | Pin list and package plan delivered | (blank) |
| 9.6 | Datasheet / user guide written | In Progress |
| 9.7 | Verification report submitted | In Progress |
| 9.8 | Full design database archived | (blank) |
| 9.9 | FPGA validation report (optional) | (blank) |
| 9.10 | Final coach and faculty approval | (blank) |
