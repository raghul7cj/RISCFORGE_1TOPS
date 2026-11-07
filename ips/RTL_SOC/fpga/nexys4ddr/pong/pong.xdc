## =============================================================================
## RISCFORGE 1TOPS — Nexys 4 DDR constraints for test "pong" (top_pong)
## =============================================================================
## Pin locations from the Digilent Nexys-4-DDR-Master.xdc (Rev. C board).
## Check them against the master XDC for your board revision before the first
## bitstream.
## =============================================================================

## Clock: 100 MHz oscillator. The SoC clock (40 MHz, u_mmcm CLKOUT0) is
## derived automatically from this constraint.
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports CLK100MHZ]
create_clock -name sys_clk -period 10.000 -waveform {0 5} [get_ports CLK100MHZ]

## CPU reset button (active low)
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports CPU_RESETN]

## USB-UART bridge (FT2232HQ). Names are from the FPGA's point of view of the
## master XDC: UART_TXD_IN is the PC's TX into the FPGA.
set_property -dict { PACKAGE_PIN C4  IOSTANDARD LVCMOS33 } [get_ports UART_TXD_IN]
set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports UART_RXD_OUT]

## Quad SPI configuration flash (S25FL128S). SCK is CCLK (E9), driven through
## STARTUPE2 in top_pong.sv, so it has no port here.
set_property -dict { PACKAGE_PIN L13 IOSTANDARD LVCMOS33 } [get_ports QSPI_CSN]
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports QSPI_DQ0]
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports QSPI_DQ1]
set_property -dict { PACKAGE_PIN L14 IOSTANDARD LVCMOS33 } [get_ports QSPI_DQ2]
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports QSPI_DQ3]

## LEDs
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {LED[0]}]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports {LED[1]}]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports {LED[2]}]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports {LED[3]}]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports {LED[4]}]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {LED[5]}]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports {LED[6]}]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {LED[7]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {LED[8]}]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports {LED[9]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {LED[10]}]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports {LED[11]}]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {LED[12]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {LED[13]}]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports {LED[14]}]
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports {LED[15]}]

## Asynchronous / slow I/O: the button and UART RX are synchronized inside the
## SoC, the LEDs are static, and the flash runs at 40 MHz / 10 (CLKDIV = 4),
## far below the clock period, so no I/O timing is required.
set_false_path -from [get_ports {CPU_RESETN UART_TXD_IN QSPI_DQ1}]
set_false_path -to   [get_ports {UART_RXD_OUT QSPI_CSN QSPI_DQ0 QSPI_DQ2 QSPI_DQ3 LED[*]}]

## Configuration: 3.3 V bank 0, bitstream loaded from the SPI flash in x1 mode
## (matches write_cfgmem -interface SPIx1 in build.tcl).
set_property CFGBVS VCCO                     [current_design]
set_property CONFIG_VOLTAGE 3.3              [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 1 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33  [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
