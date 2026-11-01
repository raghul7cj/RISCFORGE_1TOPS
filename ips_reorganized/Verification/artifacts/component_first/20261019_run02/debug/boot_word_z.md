# Timer0 boot smoke: `Z` image words root cause and closure

## Root cause

The initial XSim run elaborated with:

```text
xelab --timescale 1ns/1ps --override_timeunit ...
```

The Infineon S25FS512S model declares `` `timescale 1 ps/1 ps `` and delays power-up by `#tdevice_PU`, where `tdevice_PU = 300e6` (300 µs at the model's 1 ps unit). `--override_timeunit` changed the model's unit to 1 ns, making that delay 300 seconds. Cold boot started its SPI read at about 1.119 ms, while the model still reported unpowered and tri-stated SO. The resulting `Z` MISO was captured in RXFIFO and propagated to the SRAM writes.

Evidence: initial failure trace in [`../timer0_integration/sim_override_timeunit_z_failure.log`](../timer0_integration/sim_override_timeunit_z_failure.log); model declaration and delay are in `ips/spi_slave_infinion/S25fs512s/model/s25fs512s.sv:60,659,916-917`.

## Corrected local XSim run

Re-elaboration omitted `--override_timeunit`, retaining the vendor model's 1 ps unit while setting the default timescale for units without a declaration:

```text
xvlog.bat --sv --nolog -d XSIM soc_timer0_boot_run_tb.sv
xelab.bat --nolog --timescale 1ns/1ps --debug all soc_timer0_boot_run_tb -s timer0_correct_timescale
xsim.bat timer0_correct_timescale -runall -nolog
```

The corrected trace in [`../timer0_integration/sim_timescale_preserved.log`](../timer0_integration/sim_timescale_preserved.log) shows `PoweredUp=1`, READ opcode `0x03`, MISO data, RXFIFO `PRDATA=0xb7100040`, and ISRAM word 0 written as `0x400010b7`. The program reaches Timer0, reads control value `0x9`, observes a nonzero counter, writes `1` to DSRAM[0], and parks at `0x00010028`.

The first corrected-timescale diagnostic captured DSRAM as soon as the core PC reached the park address. The final store commits two clock cycles later. The staged testbench was adjusted to wait for the committed result after reaching park, then the smoke passed **52/52 checks**. This was a verification-only staged bench change; RTL and the checked-in testbench were not changed.

## Boundary conclusion

The flash image preload was correct. The first unknown occurred because the flash model was held in power-up by the simulator time-unit override. With the correct time unit, SPI pins, RXFIFO, bootloader capture, AXI data, and SRAM contents all carry known values through the complete non-C integration smoke.

Further component validation remains open for UART, the SPI EOT caveat, standalone Timer0/Timer1 register checks, and monitor negative/vacuity checks. Stage1 remains deferred until those checks are closed.

