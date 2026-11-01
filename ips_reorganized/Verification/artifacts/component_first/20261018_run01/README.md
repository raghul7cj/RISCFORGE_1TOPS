# Component-first SoC verification run 01

Simulator: Vivado XSim 2022.2 (Windows). Run files and SHA-256 source records are in `reproducibility.json`.

## Results

| Area | Result | Evidence |
|---|---|---|
| Monitor smoke | PASS | `monitor/`; exact APB monitor payload checks cover all six slots and class trace queue. |
| Monitor challenge | PASS | `monitor_challenge/`; all 25 empirical checks pass, including ring wrap/freeze and monitor non-intrusiveness. |
| Monitor stress / IRQ concurrency | PASS AFTER FIX | `monitor_stress/`; 165 checks pass. The initial run reproduced a lost simultaneous IRQ event; the infra monitor now allocates unique ring slots, accumulates simultaneous counts, and logs Timer1 source edges. |
| Full SoC compile/elaboration | PASS | `soc_compile/`; XSim compile and `soc_tb_top` elaboration succeed. |
| Cold boot + warm reset retention | PASS | `boot/`; 36 checks pass, including all eight known words loaded into ISRAM and retained across warm reset. Testbench BFM was fixed to increment the flash byte address for each 32-bit word in a continuous SPI read. Test timeout increased to 100,000 cycles because the configured SRAM clear takes about 82,000 cycles. |
| GPIO APB component | PASS (SoC aperture decode enforced upstream) | `gpio/`; 312 pass, 0 fail. The bench observations directly access the GPIO wrapper and bypass the SoC APB decoder; the system map excludes offsets 0x800-0xFFF from GPIO. |
| I2C APB component | PASS | `i2c/`; 90 pass, 0 fail in the thorough direct APB bench with pin-level bus model. |
| UART APB component | INCOMPLETE | `uart_partial/`; compile/elaboration pass, simulation stops making progress after reset checks. |
| AXI-Lite-to-APB bridge | INCOMPLETE | `interconnect_bridge_partial/`; compile/elaboration pass, TC1/TC2 basic access pass, but TC3 unmapped address stalls and `rr_arb_tree` assertions occur. |

## Not yet covered

The full plan is not complete, so Stage1 firmware remains deferred. Direct checks are still needed for instruction/data SRAM boundaries and byte enables, crossbar decode/arbitration, APB routing through the real SoC, Timer0, Timer1, UART, SPI registers, external UART/SPI/GPIO pins, and I2C EEPROM ACK/read/write behavior. The current boot test covers ISRAM boot loading only (`NUM_DATA_WORDS=0`).

## Reproduction notes

Each subfolder has tool output logs. The run was performed in isolated `%TEMP%` work directories because this Windows environment denied changing the shell cwd to the repository; outputs were copied into this artifact directory. Boot BFM image is created deterministically in the testbench, not read from a separate firmware binary. Some existing bootloader `$readmemh` warnings refer to optional relative `bootrom.hex` / `imem.hex` files; they do not supply the SPI test image.



