# STAGE 7 — Bitstream Generation & Hardware Bring-Up
**FPGA-PLAN-S7 | Blocked on S6 Sign-Off**

> **Status**: ⏳ BLOCKED — Waiting for S6 sign-off  
> **Target Board**: Digilent Nexys4 DDR (`xc7a100tcsg324-1`)  
> **Final Artifact**: `riscforge_soc_nexys4ddr.bit`  
> **Sign-Off**: ⬜ PENDING

---

## Objective

Generate the FPGA bitstream with proper SPI flash boot options (Bitstream generation properties for quad SPI mode and configuration rate), program the Nexys4 DDR over Vivado Hardware Manager / JTAG, and validate initial SoC operation via UART console and GPIO LEDs.

---

## Bitstream Configuration Properties

```tcl
# Configure Bitstream settings for Quad SPI Flash on Nexys4 DDR (Spansion/Micron 128Mbit)
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_DIV 1 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Generate bitstream
write_bitstream -force riscforge_soc_nexys4ddr.bit
write_cfgmem -format mcs -size 16 -interface SPIx4 -loadbit "up 0x0 riscforge_soc_nexys4ddr.bit" -file riscforge_soc.mcs
```

---

## Bring-Up Sequence on Board

1. **Power & JTAG Enumeration**: Connect micro-USB cable to `PROG/UART` port on Nexys4 DDR.
2. **Hardware Server Connect**:
   ```tcl
   open_hw_manager
   connect_hw_server
   open_hw_target
   current_hw_device [get_hw_devices xc7a100t_0]
   set_property PROGRAM.FILE {riscforge_soc_nexys4ddr.bit} [current_hw_device]
   program_hw_devices [current_hw_device]
   ```
3. **Reset De-assertion**: Observe `DONE` LED illuminates green.
4. **BootROM Execution**: Core fetches from address `0x0000_0000` (BootROM stub), initializes stack pointer, and transitions to ISRAM execution.
5. **UART Console Attestation**: Open terminal emulator (PuTTY / TeraTerm / minicom) at **115200 baud, 8N1** to observe boot banner / attestation signature.
6. **GPIO Check**: Check LEDs `LED[15:0]` blinking or reflecting bootloader status.

---

## Findings Log

| Finding ID | Test Item | Issue Description | Severity | Status |
|:-----------|:----------|:------------------|:--------:|:------:|
| S7-F001 | — | Pending hardware execution | — | ⏳ |

---

## Sign-Off Block

| Criteria | Status |
|:---------|:------:|
| Bitstream `riscforge_soc_nexys4ddr.bit` successfully created without DRC errors | ⬜ |
| FPGA programmed via JTAG, `DONE` LED turns ON | ⬜ |
| Reset sequence behaves reliably upon pressing `C12` (CPU Reset) | ⬜ |
| UART transmission verified at 115200 baud | ⬜ |
| Dual-sided verification criteria met (instruction retired + MMIO write) | ⬜ |

**Final Project Sign-Off**: ⬜ — Completed hardware delivery.

