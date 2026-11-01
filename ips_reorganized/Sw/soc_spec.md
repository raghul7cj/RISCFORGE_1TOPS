# Architecture & File Structure: SoC and Core

Below is the architectural breakdown and directory structural analysis of the **RISC-V Core** and the **SoC Subsystem**.

```mermaid
flowchart TB
    subgraph SoC_Subsystem ["RISCFORGE SoC Top-Level (riscforge_soc_subsystem.sv)"]
        direction TB
        subgraph Core_Subsystem ["RISC-V 5-Stage RV32IM_Zicsr Core (top.v)"]
            IF["IF: fetch_cycle"] --> ID["ID: decode_cycle"]
            ID --> EX["EX: execute_cycle + rv32m_unit"]
            EX --> MEM["MEM: memory_cycle"]
            MEM --> WB["WB: writeback_cycle + csr_regfile"]
        end

        Core_Subsystem -->|Fetch Port: 30-bit addr| Demux["instr_fetch_demux.sv"]
        Demux -->|0x0000_0000| BootROM["boot_rom.sv (64 B)"]
        Demux -->|0x0001_0000| ISRAM_MUX["sram_mux (ISRAM)"]
        ISRAM_MUX --> ISRAM["ISRAM (32 KB)"]

        Core_Subsystem -->|LSU Bus| Hybrid["hybrid_mem_interface.sv"]
        Hybrid -->|0x0002_0000 (DSRAM)| DSRAM_MUX["sram_mux (DSRAM)"]
        DSRAM_MUX --> DSRAM["DSRAM (32 KB)"]

        Hybrid -->|0x4000_0000 (MMIO)| XBAR["2x3 AXI-Lite Crossbar (axi_lite_xbar)"]
        Bootloader["bootloader.sv (SPI QSPI Flash Loader)"] -->|AXI Master (SLV 1)| XBAR

        XBAR -->|MST 0: Privileged Writes| ISRAM_AXI["axi_lite_sram_if"] --> ISRAM_MUX
        XBAR -->|MST 1: Data Writes| DSRAM_AXI["axi_lite_sram_if"] --> DSRAM_MUX
        XBAR -->|MST 2: 0x4000_0000 - 0x5000_0000| APB_Bridge["axi_lite_to_apb (1 to 6 Bridge)"]

        APB_Bridge --> APB0["APB[0]: apb_i2c (0x4000_0000)"]
        APB_Bridge --> APB1["APB[1]: apb_timer0 (0x4000_1000)"]
        APB_Bridge --> APB2["APB[2]: apb_uart (0x4000_2000)"]
        APB_Bridge --> APB3["APB[3]: gpio_apb_wrap (0x4000_3000)"]
        APB_Bridge --> APB4["APB[4]: Bootloader Mux -> apb_spi_master (0x4000_4000)"]
        APB_Bridge --> APB5["APB[5]: apb_timer1 (0x4000_5000)"]
    end
```

---

## 1. Directory Organization

### A. `ips/` sibling Directory (SoC IPs and Core Integration)
```
ips/
├── RTL_SOC/                  # Top-level SoC subsystem & integration testbenches
│   ├── riscforge_soc_subsystem.sv  # Main SoC Top module
│   ├── instr_fetch_demux.sv        # BootROM vs ISRAM fetch router
│   ├── boot_rom.sv                 # Hardware 64-byte boot vector ROM
│   ├── axi_lite_sram_if.sv         # AXI-Lite to single-port SRAM adapter
│   ├── sram_mux.sv                 # 2:1 priority SRAM port multiplexer
│   ├── sram_sp.sv                  # 32 KB synchronous single-port SRAM
│   └── soc_*.sv / *.f              # SoC-level verification suites & filelists
├── riscv_core/               # Core RTL tree for SoC synthesis & standalone simulation
│   └── rtl/
│       ├── top.v                   # 5-stage core top module
│       ├── hybrid_mem_interface.sv # Splits direct SRAM access from AXI MMIO
│       ├── axi_pkg.sv              # AXI4-Lite type definitions and structs
│       ├── fetch_cycle.v           # IF stage
│       ├── decode_cycle.v          # ID stage
│       ├── execute_cycle.v         # EX stage
│       ├── memory_cycle.v          # MEM stage (LSU)
│       ├── writeback_cycle.v       # WB stage
│       ├── rv32m_unit.v / mul / div# Hardware multiplier & non-restoring divider
│       ├── csr_regfile.v           # Zicsr register file (mstatus, mie, mip, mtvec, mepc, mcause)
│       └── hazard_unit.v           # Forwarding & pipeline stall controller
├── bootloader/               # Autonomous hardware bootloader
│   ├── bootloader.sv               # SPI Flash reader & SRAM loader FSM
│   └── bootloader_tb*.sv           # Comprehensive bootloader testbenches
├── axi_lite_xbar/            # 2-Slave to 3-Master AXI4-Lite crossbar interconnect
├── axi_lite_to_apb/          # AXI4-Lite to 6-channel APB bridge
├── apb_uart-main/            # 16550-compatible APB UART
├── apb_timer-master/         # Dual 32-bit APB Timer with prescaler & compare IRQs
├── apb_i2c-master/           # APB I2C Master with programmable prescaler
├── gpio-master/              # 32-pin GPIO controller with edge/level IRQ logic
├── spi_master_ip/            # QSPI/SPI Master transceiver with TX/RX FIFOs
├── clic-master/              # Core-Local Interrupt Controller
├── mem_files/                # BootROM, Flash images, and test hex files
└── instr_module/             # Instruction memory test modules
```

### B. `5_stage/` Directory (Modular Core Development Tree)
```
5_stage/
├── core/             # top.v (Core integration)
├── pipeline/         # fetch_cycle.v, decode_cycle.v, execute_cycle.v, memory_cycle.v, writeback_cycle.v
├── control/          # Control_Unit_Top.v, Main_Decoder.v, ALU_Decoder.v, hazard_unit.v, opcode_check.v
├── ALU/              # ALU.v, JB_unit.v
├── rv32m/            # rv32m_unit.v, rv32m_mul.v, rv32m_div.v, booth_enc.v, pp_gen.v, csa.v
├── trap_mret_csr/    # csr_regfile.v, wb_trap_mret_commit_controller.v
├── memory/           # hybrid_mem_interface.sv, imem_controller.v, ls_unit.v, Instruction_Memory.v, Data_Memory.v
├── utils/            # PC.v, PC_Adder.v, Register_File.v, Sign_Extend.v, Mux2.v, Mux_3_by_1.v
└── tb/               # SystemVerilog OOP & UVM-like CSR/Exception verification environments
```

---

## 2. Memory & MMIO Address Map

| Region | Address Range | Size | Master / Access Path | Description |
|---|---|---|---|---|
| **BootROM** | `0x0000_0000 – 0x0000_003F` | 64 B | Core Fetch Demux | Read-only reset vector (`sp` init, jumps to ISRAM) |
| **ISRAM** | `0x0001_0000 – 0x0001_7FFF` | 32 KB | Core Fetch / AXI MST[0] | Core fetches via direct port; AXI writes privilege-gated (`awprot[0]=1`) |
| **DSRAM** | `0x0002_0000 – 0x0002_7FFF` | 32 KB | Core LSU / AXI MST[1] | Core LSU accesses directly via SRAM mux port 0 (1-cycle latency) |
| **APB MMIO** | `0x4000_0000 – 0x4FFF_FFFF` | 256 MB | Core LSU → AXI MST[2] | Routed across AXI Crossbar to APB Bridge |
| ├─ **I2C** | `0x4000_0000 – 0x4000_0FFF` | 4 KB | APB[0] | I2C Prescaler, Control, Status, TX/RX buffers |
| ├─ **Timer 0** | `0x4000_1000 – 0x4000_1FFF` | 4 KB | APB[1] | Dual 32-bit timers with compare match / overflow IRQ |
| ├─ **UART** | `0x4000_2000 – 0x4000_2FFF` | 4 KB | APB[2] | 16550-compatible UART registers |
| ├─ **GPIO** | `0x4000_3000 – 0x4000_3FFF` | 4 KB | APB[3] | 32 GPIO pins with level/edge interrupt triggers |
| ├─ **SPI Master** | `0x4000_4000 – 0x4000_4FFF` | 4 KB | APB[4] | QSPI Master (bootloader control during boot, runtime passthrough) |
| └─ **Timer 1** | `0x4000_5000 – 0x4000_5FFF` | 4 KB | APB[5] | Secondary dual 32-bit timer block |

---

## 3. Interrupt Mapping (Core & SoC)

| CSR Bit | Interrupt Type | Source Peripheral | Description |
|---|---|---|---|
| `mip[19]` | **Fast Local IRQ 3** | UART (`uart_int_o`) | UART TX/RX threshold / status IRQ |
| `mip[18]` | **Fast Local IRQ 2** | SPI (`spi_events_o[0]`) | SPI transfer completed / FIFO event |
| `mip[17]` | **Fast Local IRQ 1** | I2C (`i2c_interrupt_o`) | Byte transfer complete / ACK flag |
| `mip[16]` | **Fast Local IRQ 0** | GPIO (`gpio_global_interrupt_o`) | Edge/Level GPIO pin event |
| `mip[7]` | **MTIP** (Timer) | Timer 0 (`timer0_irq_o[1]`) | Machine Timer compare match |
| `mip[11]` | **MEIP** (External) | Tied to 0 | Platform PLIC line (extensible) |
| `mip[3]` | **MSIP** (Software) | Tied to 0 | Inter-processor interrupt line |

---

## 4. Key SoC Architectural Highlights

1. **Direct Memory Access vs. MMIO Splitting:**
   - The core **never suffers bus arbitration overhead for normal memory access**:
     - `Instruction Fetch` directly accesses **ISRAM** via [`instr_fetch_demux.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/RTL_SOC/instr_fetch_demux.sv).
     - `Load/Store Unit` accesses **DSRAM** via [`hybrid_mem_interface.sv`](file:///c:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/riscv_core/rtl/hybrid_mem_interface.sv).
   - Only addresses in the range `0x4000_0000 – 0x4FFF_FFFF` trigger AXI-Lite bus transactions to the APB peripherals.

2. **Boot Sequence & Clean-Slate Handover:**
   - On cold reset (`hard_rst_ni=0`), the **Bootloader** holds the CPU in reset (`core_rst_n=0`) and reads instructions/data from external SPI Flash, writing them directly into ISRAM (`0x0001_0000`) and DSRAM (`0x0002_0000`) over AXI with `awprot[0]=1` (privileged mode).
   - Once loading finishes (`boot_done_o=1`), the Bootloader locks down ISRAM against further writes, switches SPI APB port 4 to CPU runtime passthrough, pulses peripheral resets, and releases the CPU at reset vector `0x0000_0000` (BootROM), which immediately branches to ISRAM.

   // =============================================================================
// RISCFORGE 1TOPS — SoC Peripheral Subsystem Top-Level
// =============================================================================
//
// Architecture:
//   RISC-V Core (real RV32IM, 5-stage — ips/riscv_core/rtl/top.v):
//     - Instruction fetch port → instr_fetch_demux
//         ├─ BootROM range (0x0000_0000) → boot_rom (reset vector; sets sp,
//         │                                 jumps to ISRAM base)
//         └─ ISRAM range   (0x0001_0000) → sram_mux[ISRAM] port 0 → ISRAM (32 KB)
//     - Load/store port       → hybrid_mem_interface, which splits:
//         ├─ DSRAM range  → sram_mux[DSRAM] port 0 → DSRAM (32 KB), direct
//         └─ MMIO range   → AXI-Lite master → axi_lite_xbar SLV[0]
//     Both SRAM paths are direct; only MMIO crosses the AXI fabric.
//
//   Bootloader (real):
//     - AXI-Lite master       → axi_lite_xbar SLV[1]   (SRAM writes only,
//                                awprot[0]=1 privileged — passes ISRAM gate)
//     - APB slave  ← APB bridge slot 4 (SPI address space)
//     - APB master → apb_spi_master  (boot: FSM drives; runtime: passthrough)
//     - Outputs: core_rst_ni, periph_rst_ni (clean-slate reset after load)
//
//   axi_lite_xbar (2 SLV → 3 MST):
//     MST[0] → axi_lite_sram_if (PRIV_WRITE_ONLY=1)
//                → sram_mux[ISRAM] port 1 → ISRAM
//     MST[1] → axi_lite_sram_if → sram_mux[DSRAM] port 1 → DSRAM
//     MST[2] → axi_lite_to_apb (1 AXI → 6 APB)
//               ├─ APB[0] → I2C
//               ├─ APB[1] → Timer 0
//               ├─ APB[2] → UART
//               ├─ APB[3] → GPIO
//               ├─ APB[4] → Bootloader APB slave (→ apb_spi_master)
//               └─ APB[5] → Timer 1
//
//   BootROM is directly connected to the core fetch demux (NOT on crossbar).
//   ISRAM writes via AXI are privilege-gated: only awprot[0]=1 (privileged)
//   transactions are accepted; unprivileged writes return SLVERR.
//
// ─────────────────────────────────────────────────────────────────────────────
// Address Map (Crossbar):
//   ISRAM:    0x0001_0000 – 0x0001_8000  (32 KB, privilege-gated writes)
//   DSRAM:    0x0002_0000 – 0x0002_8000  (32 KB)
//   APB:      0x4000_0000 – 0x5000_0000  (256 MB peripheral space)
//
// Address Map (Core-only, NOT on crossbar):
//   BootROM:  0x0000_0000 – 0x0000_0040  (64 B, 16 × 32-bit, read-only stub)
//
// Address Map (APB Bridge, within peripheral space):
//   I2C:      0x4000_0000 – 0x4000_1000  (4 KB)
//   Timer 0:  0x4000_1000 – 0x4000_2000  (4 KB)
//   UART:     0x4000_2000 – 0x4000_3000  (4 KB)
//   GPIO:     0x4000_3000 – 0x4000_4000  (4 KB)
//   SPI:      0x4000_4000 – 0x4000_5000  (4 KB)
//   Timer 1:  0x4000_5000 – 0x4000_6000  (4 KB)
//
// ═══════════════════════════════════════════════════════════════════════════════
// MEMORY-MAPPED I/O REGISTER MAP
// ═══════════════════════════════════════════════════════════════════════════════
//
// ───────────────────────────────────────────────────────────────────────────────
// BootROM: 0x0000_0000 – 0x0000_003F  (64 B, 16 × 32-bit, read-only stub)
//   Core-only access via instruction fetch demux. Not on AXI crossbar.
// ───────────────────────────────────────────────────────────────────────────────
//   0x0000_0000 – 0x0000_003C   ROM data (16 × 32-bit words, NOP-filled stub)
//
// ───────────────────────────────────────────────────────────────────────────────
// ISRAM: 0x0001_0000 – 0x0001_7FFF  (32 KB, privilege-gated writes)
//   AXI writes require awprot[0]=1 (privileged). Unprivileged writes
//   return SLVERR. Core fetches via direct port (read-only, no AXI).
// ───────────────────────────────────────────────────────────────────────────────
//   0x0001_0000 – 0x0001_7FFC   Instruction SRAM (8192 × 32-bit words)
//
// ───────────────────────────────────────────────────────────────────────────────
// DSRAM: 0x0002_0000 – 0x0002_7FFF  (32 KB)
// ───────────────────────────────────────────────────────────────────────────────
//   0x0002_0000 – 0x0002_7FFC   Data SRAM (8192 × 32-bit words)
//
// ═══════════════════════════════════════════════════════════════════════════════
// APB PERIPHERAL SPACE: 0x4000_0000 – 0x4FFF_FFFF
// ═══════════════════════════════════════════════════════════════════════════════
//
// ───────────────────────────────────────────────────────────────────────────────
// I2C Master — APB[0]: 0x4000_0000 – 0x4000_0FFF  (4 KB)
// ───────────────────────────────────────────────────────────────────────────────
//   Offset  Name   Width   Access  Description
//   0x00    PRE    16-bit  R/W     Clock prescaler (SCL = PCLK/(5×(PRE+1)))
//   0x04    CTR    8-bit   R/W     Control register
//             [7]   EN       R/W     Core enable
//             [6]   IEN      R/W     Interrupt enable
//             [5:0] —        —       Reserved
//   0x08    RXR    8-bit   R       Received byte
//   0x0C    SR     8-bit   R       Status register
//             [7]   RxACK    R       Received ACK from slave (0=ACK)
//             [6]   Busy     R       I2C bus busy
//             [5]   AL       R       Arbitration lost
//             [1]   TIP      R       Transfer in progress
//             [0]   IF       R       Interrupt flag
//   0x10    TXR    8-bit   W       Transmit byte / slave address
//   0x14    CR     8-bit   W       Command register
//             [7]   STA      W       Generate START condition
//             [6]   STO      W       Generate STOP condition
//             [5]   RD       W       Read from slave
//             [4]   WR       W       Write to slave
//             [3]   ACK      W       ACK value to send (0=ACK, 1=NACK)
//             [0]   IACK     W       Interrupt acknowledge
//
// ───────────────────────────────────────────────────────────────────────────────
// Timer 0 — APB[1]: 0x4000_1000 – 0x4000_1FFF  (4 KB, TIMER_CNT=2)
// ───────────────────────────────────────────────────────────────────────────────
//   Per-timer registers (Timer_N at offset N × 0x10):
//
//   Timer_0 (N=0):
//   Offset  Name         Width   Access  Description
//   0x00    TIMER_VAL    32-bit  R/W     Current timer value
//   0x04    TIMER_CTRL   32-bit  R/W     Timer control
//             [0]   EN        R/W     Timer enable
//             [5:3] PRESCALER R/W     Prescaler divider (0=bypass)
//   0x08    TIMER_CMP    32-bit  R/W     Compare value (resets timer on match)
//
//   Timer_1 (N=1):
//   0x10    TIMER_VAL    32-bit  R/W     Current timer value
//   0x14    TIMER_CTRL   32-bit  R/W     Timer control
//   0x18    TIMER_CMP    32-bit  R/W     Compare value
//
//   IRQ outputs: [2*N] = overflow,  [2*N+1] = compare match
//
// ───────────────────────────────────────────────────────────────────────────────
// UART — APB[2]: 0x4000_2000 – 0x4000_2FFF  (4 KB, 16550-compatible)
//   Note: apb_uart takes a 3-bit word address PADDR[4:2] (8 registers).
// ───────────────────────────────────────────────────────────────────────────────
//   Offset  Name          Width   Access  Description
//   0x00    RBR/THR/DLL   8-bit   R/W     Receive buffer (R) / Transmit hold (W)
//                                          / Divisor latch LSB (when DLAB=1)
//   0x04    IER/DLM       8-bit   R/W     Interrupt enable (DLAB=0)
//                                          / Divisor latch MSB (DLAB=1)
//             [0]   ERBFI    R/W     Enable received data available IRQ
//             [1]   ETBEI    R/W     Enable TX hold empty IRQ
//             [2]   ELSI     R/W     Enable receiver line status IRQ
//             [3]   EDSSI    R/W     Enable modem status IRQ
//   0x08    IIR/FCR       8-bit   R/W     Interrupt identification (R)
//                                          / FIFO control (W)
//   0x0C    LCR           8-bit   R/W     Line control register
//             [7]   DLAB     R/W     Divisor latch access bit
//             [5:3] —        R/W     Parity config
//             [2]   STOP     R/W     Stop bits (0=1bit, 1=2bits)
//             [1:0] WLS      R/W     Word length (00=5, 11=8 bits)
//   0x10    MCR           8-bit   R/W     Modem control register
//   0x14    LSR           8-bit   R       Line status register
//             [0]   DR       R       Data ready
//             [5]   THRE     R       TX holding register empty
//             [6]   TEMT     R       Transmitter empty
//   0x18    MSR           8-bit   R       Modem status register
//   0x1C    SCR           8-bit   R/W     Scratch register
//
// ───────────────────────────────────────────────────────────────────────────────
// GPIO — APB[3]: 0x4000_3000 – 0x4000_37FF  (2 KB, 32 pins)
//   lowRISC reggen-generated register map (BlockAw=11).
// ───────────────────────────────────────────────────────────────────────────────
//   Offset  Name                Width   Access  Description
//   0x000   INFO                32-bit  R       [9:0] GPIO count, [19:10] version
//   0x004   CFG                 32-bit  R/W     [0] global_intrpt_mode
//                                                [1] pin_lvl_intrpt_mode
//   0x008   GPIO_MODE_0         32-bit  R/W     2-bit mode per GPIO[0..15]
//   0x00C   GPIO_MODE_1         32-bit  R/W     2-bit mode per GPIO[16..31]
//   0x010   GPIO_EN             32-bit  R/W     Output enable per pin
//   0x014   GPIO_IN             32-bit  R       Sampled input value
//   0x018   GPIO_OUT            32-bit  R/W     Output data value
//   0x01C   GPIO_SET            32-bit  W       Set output pins (write-1-to-set)
//   0x020   GPIO_CLEAR          32-bit  W       Clear output pins (write-1-to-clear)
//   0x024   GPIO_TOGGLE         32-bit  W       Toggle output pins
//   0x028   INTRPT_RISE_EN      32-bit  R/W     Rising-edge interrupt enable
//   0x02C   INTRPT_FALL_EN      32-bit  R/W     Falling-edge interrupt enable
//   0x030   INTRPT_LVL_HIGH_EN  32-bit  R/W     Level-high interrupt enable
//   0x034   INTRPT_LVL_LOW_EN   32-bit  R/W     Level-low interrupt enable
//   0x038   INTRPT_STATUS       32-bit  R/W1C   Interrupt status
//   0x03C   INTRPT_RISE_STATUS  32-bit  R/W1C   Rising-edge interrupt status
//   0x040   INTRPT_FALL_STATUS  32-bit  R/W1C   Falling-edge interrupt status
//   0x044   INTRPT_LVL_HIGH_STS 32-bit  R       Level-high interrupt status
//   0x048   INTRPT_LVL_LOW_STS  32-bit  R       Level-low interrupt status
//
// ───────────────────────────────────────────────────────────────────────────────
// SPI Master — APB[4]: 0x4000_4000 – 0x4000_4FFF  (4 KB)
//   Accessible via bootloader APB mux; during boot: FSM-driven.
// ───────────────────────────────────────────────────────────────────────────────
//   Offset  Name     Width   Access  Description
//   0x00    STATUS   32-bit  R       SPI status (TX/RX FIFO flags)
//             [0]   TX_FULL   R       TX FIFO full
//             [1]   TX_EMPTY  R       TX FIFO empty
//             [4]   RX_FULL   R       RX FIFO full
//             [5]   RX_EMPTY  R       RX FIFO empty
//             [8]   CS        R       Active chip select
//   0x04    CLKDIV   8-bit   R/W     SPI clock divider (f_SPI = f_CLK/(2×(CLKDIV+1)))
//   0x08    SPICMD   32-bit  R/W     SPI command value (MSB-aligned)
//   0x0C    SPIADR   32-bit  R/W     SPI address value (MSB-aligned)
//   0x10    SPILEN   32-bit  R/W     Transfer lengths
//             [5:0]   CMDLEN    R/W   Command length (bits)
//             [13:8]  ADRLEN    R/W   Address length (bits)
//             [31:16] DATALEN   R/W   Data length (bits)
//   0x14    SPIDUM   32-bit  R/W     Dummy cycle config
//             [15:0]  DUMMYRD   R/W   Dummy cycles for reads
//             [31:16] DUMMYWR   R/W   Dummy cycles for writes
//   0x18    TXFIFO   32-bit  W       TX FIFO data (push)
//   0x20    RXFIFO   32-bit  R       RX FIFO data (pop)
//   0x24    INTCFG   32-bit  R/W     Interrupt configuration
//   0x28    INTSTA   32-bit  R       Interrupt status
//
// ───────────────────────────────────────────────────────────────────────────────
// Timer 1 — APB[5]: 0x4000_5000 – 0x4000_5FFF  (4 KB, TIMER_CNT=2)
//   Same register layout as Timer 0.
// ───────────────────────────────────────────────────────────────────────────────
//   Timer_0 (N=0): 0x00 TIMER_VAL, 0x04 TIMER_CTRL, 0x08 TIMER_CMP
//   Timer_1 (N=1): 0x10 TIMER_VAL, 0x14 TIMER_CTRL, 0x18 TIMER_CMP
//   IRQ outputs: [2*N] = overflow,  [2*N+1] = compare match
//
// ─────────────────────────────────────────────────────────────────────────────
// Reset Topology:
//   hard_rst_ni  → cold boot, resets everything including bootloader
//   soft_rst_ni  → warm boot, SRAM preserved, bootloader runs clean-slate only
//   sys_rst_n    = hard_rst_ni & soft_rst_ni → crossbar, bridges, muxes
//   core_rst_n   ← bootloader output → RISC-V core
//   periph_rst_n ← bootloader output → non-boot peripherals (I2C, Timer 0,
//                                       Timer 1, UART, GPIO)
//   spi_rst_n    ← bootloader output → SPI master (independent timing: HIGH
//                                       during boot, pulsed LOW for clean-slate,
//                                       HIGH for runtime)
//
// =============================================================================
