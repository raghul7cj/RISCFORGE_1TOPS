# 1-TOPS Project Signoff Checklist — Markdown index

**Source:** user-supplied `1TOPS_Project_Signoff_Checkl.xlsx` (2026-11-02). This Markdown index mirrors the **124 checklist item IDs and names** for GitHub browsing. The original `.xlsx` contains the detailed acceptance criteria, tools, owner, approvals and formulas and **is not replaced by this index**.

**Official status:** all items are `Not Started` in the supplied workbook; repository evidence cannot independently assign coach approval. The companion [evidence audit](README.md) makes partial/blocked findings explicit.

## G0

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 0.1 | Front-end tools installed and licensed | Not Started |
| 0.2 | Back-end tools installed and licensed | Not Started |
| 0.3 | RISC-V GNU toolchain installed | Not Started |
| 0.4 | Spike ISS built for your ISA | Not Started |
| 0.5 | 28 nm PDK, standard cells, SRAM macros and IO library received | Not Started |
| 0.6 | Version control in place | Not Started |
| 0.7 | Regression runnable by one command | Not Started |

## G1

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 1.1 | Core ISA frozen | Not Started |
| 1.2 | Pipeline depth frozen | Not Started |
| 1.3 | Privilege modes frozen | Not Started |
| 1.4 | CSR list frozen | Not Started |
| 1.5 | Trap and interrupt model defined | Not Started |
| 1.6 | Memory organisation frozen | Not Started |
| 1.7 | SoC block diagram approved | Not Started |
| 1.8 | Address map frozen | Not Started |
| 1.9 | Interrupt map frozen | Not Started |
| 1.10 | Clock and reset architecture defined | Not Started |
| 1.11 | Pin list / chip IO table frozen | Not Started |
| 1.12 | Boot plan defined | Not Started |
| 1.13 | Micro-architecture document complete | Not Started |
| 1.14 | Verification plan (testplan) written | Not Started |
| 1.15 | Area, frequency and power targets stated | Not Started |

## G2

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 2.1 | PC generation unit coded | Not Started |
| 2.2 | Decoder and control unit coded | Not Started |
| 2.3 | Register file coded | Not Started |
| 2.4 | ALU coded | Not Started |
| 2.5 | Branch unit coded | Not Started |
| 2.6 | MDU coded (if M extension) | Not Started |
| 2.7 | Memory interface unit coded | Not Started |
| 2.8 | Hazard and forwarding logic coded | Not Started |
| 2.9 | CSR block and trap logic coded | Not Started |
| 2.10 | Compressed decoder coded (if C extension) | Not Started |
| 2.11 | RTL coding rules followed | Not Started |
| 2.12 | Core lint clean | Not Started |
| 2.13 | Core CDC clean | Not Started |

## G3

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 3.1 | GPIO integrated (mandatory) | Not Started |
| 3.2 | UART integrated (mandatory) | Not Started |
| 3.3 | SPI / QSPI master integrated (mandatory) | Not Started |
| 3.4 | PLIC integrated (mandatory) | Not Started |
| 3.5 | Timer integrated (mandatory) | Not Started |
| 3.6 | CLINT / CLIC integrated (mandatory) | Not Started |
| 3.7 | I2C integrated (optional) | Not Started |
| 3.8 | I2S integrated (optional) | Not Started |
| 3.9 | Boot ROM integrated | Not Started |
| 3.10 | SRAMs integrated | Not Started |
| 3.11 | Interconnect integrated | Not Started |
| 3.12 | System control block integrated | Not Started |
| 3.13 | Address decode matches G1 map | Not Started |
| 3.14 | Top-level SoC lint clean | Not Started |
| 3.15 | SoC CDC and RDC clean | Not Started |
| 3.16 | Unconnected / floating nets checked | Not Started |

## G4

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 4.1 | Unit TB for PC unit | Not Started |
| 4.2 | Unit TB for decoder / control | Not Started |
| 4.3 | Unit TB for register file | Not Started |
| 4.4 | Unit TB for ALU | Not Started |
| 4.5 | Unit TB for branch unit | Not Started |
| 4.6 | Unit TB for MDU | Not Started |
| 4.7 | Unit TB for MIU | Not Started |
| 4.8 | Unit TB for hazard logic | Not Started |
| 4.9 | Unit regression 100% pass | Not Started |
| 4.10 | Core sanity TB built | Not Started |
| 4.11 | Core sanity tests pass | Not Started |
| 4.12 | Reset and interrupt entry verified | Not Started |
| 4.13 | Hazard tests pass at core level | Not Started |
| 4.14 | Core sanity coverage met | Not Started |

## G5

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 5.1 | ISS comparison flow working | Not Started |
| 5.2 | Official RISC-V ISA tests pass | Not Started |
| 5.3 | Privileged / trap tests pass | Not Started |
| 5.4 | riscv-dv integrated | Not Started |
| 5.5 | riscv-dv regression stable | Not Started |
| 5.6 | Memory latency randomisation run | Not Started |
| 5.7 | Benchmarks run | Not Started |
| 5.8 | Functional coverage closed at core level | Not Started |
| 5.9 | Code coverage >= 95% on core | Not Started |
| 5.10 | Core bug list closed | Not Started |

## G6

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 6.1 | UVM SoC testbench built | Not Started |
| 6.2 | Register tests pass | Not Started |
| 6.3 | Register field coverage closed | Not Started |
| 6.4 | Per-IP use cases pass | Not Started |
| 6.5 | Interrupt path verified end to end | Not Started |
| 6.6 | Bus bridge protocol verified | Not Started |
| 6.7 | Memory map decode verified | Not Started |
| 6.8 | Traffic stress run | Not Started |
| 6.9 | Boot from internal ROM passes | Not Started |
| 6.10 | Boot from external SPI flash passes | Not Started |
| 6.11 | SRAM load / ROM remap boot passes | Not Started |
| 6.12 | Bare-metal C test suite passes | Not Started |
| 6.13 | Trap robustness under load passes | Not Started |
| 6.14 | SoC random and stress tests pass | Not Started |
| 6.15 | SoC functional coverage closed | Not Started |
| 6.16 | SoC code coverage >= 95% | Not Started |
| 6.17 | Full regression clean | Not Started |
| 6.18 | No deadlocks in long runs | Not Started |
| 6.19 | RTL frozen for synthesis | Not Started |

## G7

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 7.1 | SDC constraints written | Not Started |
| 7.2 | Synthesis runs clean | Not Started |
| 7.3 | Timing met post-synthesis | Not Started |
| 7.4 | Area within budget | Not Started |
| 7.5 | DFT inserted | Not Started |
| 7.6 | ATPG coverage met | Not Started |
| 7.7 | Gate-level simulation passes | Not Started |
| 7.8 | Post-synthesis LEC clean | Not Started |

## G8

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 8.1 | Floorplan complete | Not Started |
| 8.2 | Power plan complete | Not Started |
| 8.3 | Placement complete | Not Started |
| 8.4 | CTS complete | Not Started |
| 8.5 | Routing complete | Not Started |
| 8.6 | Post-route STA signoff | Not Started |
| 8.7 | Post-layout LEC clean | Not Started |
| 8.8 | DRC clean | Not Started |
| 8.9 | LVS clean | Not Started |
| 8.10 | Antenna and DFM checks clean | Not Started |
| 8.11 | IR / EM signoff | Not Started |
| 8.12 | Post-layout gate simulation passes | Not Started |

## G9

| ID | Checklist requirement | Official workbook status |
|---|---|---|
| 9.1 | GDSII generated | Not Started |
| 9.2 | Sealring, fill and logo added | Not Started |
| 9.3 | Foundry tape-out checklist completed | Not Started |
| 9.4 | Test patterns delivered | Not Started |
| 9.5 | Pin list and package plan delivered | Not Started |
| 9.6 | Datasheet / user guide written | Not Started |
| 9.7 | Verification report submitted | Not Started |
| 9.8 | Full design database archived | Not Started |
| 9.9 | FPGA validation report (optional) | Not Started |
| 9.10 | Final coach and faculty approval | Not Started |
