## =============================================================================
## RISCFORGE 1TOPS — Nexys 4 DDR constraints for test "arm" (top_arm)
## =============================================================================
## Pin locations from the Digilent Nexys-4-DDR-Master.xdc (Rev. C board).
## Check them against the master XDC for your board revision before the first
## bitstream.
## =============================================================================

## Clock: 100 MHz oscillator. The SoC clock (32 MHz, u_mmcm CLKOUT0) is
## derived automatically from this constraint.
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports CLK100MHZ]
create_clock -name sys_clk -period 10.000 -waveform {0 5} [get_ports CLK100MHZ]

## CPU reset button (active low)
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports CPU_RESETN]

## USB-UART bridge (FT2232HQ), 1000000 baud. FPGA -> PC: mirror of the SoC
## UART TX. PC -> FPGA (C4): SoC UART RX in laptop-relay mode (SW13 = 1).
set_property -dict { PACKAGE_PIN C4  IOSTANDARD LVCMOS33 } [get_ports UART_TXD_IN]
set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports UART_RXD_OUT]

## Quad SPI configuration flash (S25FL128S). SCK is CCLK (E9), driven through
## STARTUPE2 in top_arm.sv, so it has no port here.
set_property -dict { PACKAGE_PIN L13 IOSTANDARD LVCMOS33 } [get_ports QSPI_CSN]
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports QSPI_DQ0]
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports QSPI_DQ1]
set_property -dict { PACKAGE_PIN L14 IOSTANDARD LVCMOS33 } [get_ports QSPI_DQ2]
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports QSPI_DQ3]

## Switches (SW8 and SW9 are in a 1.8 V bank)
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports {SW[0]}]
set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports {SW[1]}]
set_property -dict { PACKAGE_PIN M13 IOSTANDARD LVCMOS33 } [get_ports {SW[2]}]
set_property -dict { PACKAGE_PIN R15 IOSTANDARD LVCMOS33 } [get_ports {SW[3]}]
set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 } [get_ports {SW[4]}]
set_property -dict { PACKAGE_PIN T18 IOSTANDARD LVCMOS33 } [get_ports {SW[5]}]
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports {SW[6]}]
set_property -dict { PACKAGE_PIN R13 IOSTANDARD LVCMOS33 } [get_ports {SW[7]}]
set_property -dict { PACKAGE_PIN T8  IOSTANDARD LVCMOS18 } [get_ports {SW[8]}]
set_property -dict { PACKAGE_PIN U8  IOSTANDARD LVCMOS18 } [get_ports {SW[9]}]
set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS33 } [get_ports {SW[10]}]
set_property -dict { PACKAGE_PIN T13 IOSTANDARD LVCMOS33 } [get_ports {SW[11]}]
set_property -dict { PACKAGE_PIN H6  IOSTANDARD LVCMOS33 } [get_ports {SW[12]}]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports {SW[13]}]
set_property -dict { PACKAGE_PIN U11 IOSTANDARD LVCMOS33 } [get_ports {SW[14]}]
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports {SW[15]}]

## Push buttons (active high)
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports BTNC]
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports BTNU]
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports BTND]
set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 } [get_ports BTNL]
set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports BTNR]

## Dynamixel bus on Pmod JA (through a 3.3 V <-> 5 V direction-controlled
## buffer, never straight to the servos). JA1 is pulled up so the UART
## receiver sees idle when nothing drives it.
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports DXL_DATA]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports DXL_DIR]

## PS/2 from the on-board PIC24 (USB HOST connector, keyboard). Open drain
## (driven low or released by top_arm), pulled up.
set_property -dict { PACKAGE_PIN F4  IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports PS2_CLK]
set_property -dict { PACKAGE_PIN B2  IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports PS2_DATA]

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

## Asynchronous / slow I/O: the button, switches, GPIO inputs and UART RX are
## synchronized inside the SoC, the LEDs are static, the flash runs at
## 32 MHz / 10 (CLKDIV = 4), and the 1 Mbps bus is 32 clocks per bit, so no
## I/O timing is required.
set_false_path -from [get_ports {CPU_RESETN QSPI_DQ1 SW[*] BTNC BTNU BTND BTNL BTNR DXL_DATA PS2_CLK PS2_DATA UART_TXD_IN}]
set_false_path -to   [get_ports {UART_RXD_OUT QSPI_CSN QSPI_DQ0 QSPI_DQ2 QSPI_DQ3 LED[*] DXL_DATA DXL_DIR PS2_CLK PS2_DATA}]

## Configuration: 3.3 V bank 0, bitstream loaded from the SPI flash in x1 mode
## (matches write_cfgmem -interface SPIx1 in build.tcl).
set_property CFGBVS VCCO                     [current_design]
set_property CONFIG_VOLTAGE 3.3              [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 1 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33  [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
