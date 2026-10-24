# STAGE 5 — Timing Constraints, Clock Management & Pinout (XDC)
**FPGA-PLAN-S5 | Blocked on S4 Sign-Off**

> **Status**: ⏳ BLOCKED — Waiting for S4 sign-off  
> **Target Board**: Digilent Nexys4 DDR (`xc7a100tcsg324-1`)  
> **Master Oscillator**: 100 MHz onboard oscillator (`E3`)  
> **Target SoC System Clock**: 50 MHz (or 25 MHz bring-up) via MMCME2_BASE / Clocking Wizard  
> **Sign-Off**: ⬜ PENDING

---

## Objective

Define full physical pinout constraints, I/O voltage standards, clock generation via Xilinx Clocking Wizard (MMCM), and static timing analysis constraints (XDC) for the Nexys4 DDR development board.

---

## Nexys4 DDR Pinout Mapping

| SoC Port | Nexys4 DDR Signal / Peripheral | FPGA Pin (Package CSG324) | IOSTANDARD | Drive / Slew |
|:---------|:-------------------------------|:--------------------------|:-----------|:-------------|
| `clk_i` | Onboard 100 MHz oscillator | `E3` | `LVCMOS33` | — |
| `hard_rst_ni` | CPU Reset push button (active low) | `C12` | `LVCMOS33` | — |
| `soft_rst_ni` | Center push button `BTNC` (or Switch `SW0`) | `N17` | `LVCMOS33` | — |
| `uart_rx_i` | FTDI USB-UART Bridge `TXD` output | `C4` | `LVCMOS33` | — |
| `uart_tx_o` | FTDI USB-UART Bridge `RXD` input | `D4` | `LVCMOS33` | Fast, 8mA |
| `gpio_io[15:0]` | Onboard LEDs `LED[15:0]` | `H17, K15, J13, N14, R18, V17, U17, U16, V16, T15, U14, T16, V15, V14, V12, P14` | `LVCMOS33` | Slow, 4mA |
| `spi_sclk_o` | Onboard Micron 128Mb QSPI Flash `SCK` | `E9` (or `STARTUPE2` primitive) | `LVCMOS33` | Fast |
| `spi_cs_no` | QSPI Flash Chip Select `CS#` | `L13` | `LVCMOS33` | Fast |
| `spi_mosi_o` | QSPI Flash `DQ0` (MOSI) | `K17` | `LVCMOS33` | Fast |
| `spi_miso_i` | QSPI Flash `DQ1` (MISO) | `K18` | `LVCMOS33` | — |
| `i2c_scl_io` | Pmod Header JA Pin 1 (Pull-up required) | `C17` | `LVCMOS33` | Open-Drain |
| `i2c_sda_io` | Pmod Header JA Pin 2 (Pull-up required) | `D18` | `LVCMOS33` | Open-Drain |

---

## Clock & Timing Constraints Strategy

```xdc
# Primary Board Clock (100 MHz oscillator on Nexys4 DDR)
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk_i]

# If using internal MMCM to scale down to 50 MHz SoC clock:
# Generated clock is automatically derived by Vivado from MMCME2 / Clocking Wizard

# SPI SCLK generated clock (derived by spi_master_clkgen divider)
create_generated_clock -name spi_sclk -source [get_pins u_soc/u_spi/u_clkgen/clk_i] \
    -divide_by 8 [get_pins u_soc/u_spi/u_clkgen/spi_clk_o]

# Asynchronous Reset false path
set_false_path -from [get_ports hard_rst_ni]
set_false_path -from [get_ports soft_rst_ni]

# I/O Delays
set_input_delay -clock sys_clk_pin -max 3.0 [get_ports uart_rx_i]
set_input_delay -clock sys_clk_pin -min 1.0 [get_ports uart_rx_i]
set_output_delay -clock sys_clk_pin -max 2.5 [get_ports uart_tx_o]
set_output_delay -clock sys_clk_pin -min 0.5 [get_ports uart_tx_o]
```

---

## Findings Log

| Finding ID | Interface | Description | Severity | Status |
|:-----------|:----------|:------------|:--------:|:------:|
| S5-F001 | QSPI / CCLK | Xilinx 7-series dedicated CCLK pin requires `STARTUPE2` primitive if accessing flash after config | HIGH | ⏳ To evaluate in S5 |

---

## Sign-Off Block

| Criteria | Status |
|:---------|:------:|
| Complete `riscforge_nexys4ddr.xdc` constraint file created | ⬜ |
| Clock definitions and generated clocks verified via `check_timing` | ⬜ |
| I/O pin locations validated against Nexys4 DDR reference manual | ⬜ |
| Voltage standard defined for all user I/Os (`LVCMOS33`) | ⬜ |
| Zero unconstrained internal endpoints | ⬜ |

**Human Sign-Off**: ⬜ — Type `SIGN OFF: S5` in chat to unlock Stage 6.

