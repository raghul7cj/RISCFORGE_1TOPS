# RTL_SOC — RISCFORGE 1TOPS SoC subsystem

```
RTL_SOC/
├── run.f            the ONLY file you edit to switch test (SELECT TEST block)
├── rtl/             synthesizable SoC RTL (riscforge_soc_subsystem + memories, boot ROM, fetch demux)
├── tb/              testbenches;  tb/models/ = sim-only models (riscv_core_stub)
├── mem/             firmware + memory images, one folder per firmware
│   ├── common/      riscforge_bootrom.hex (boot ROM image, shared by every test)
│   ├── regtest/  montest/  i2c_regtest/  timer/
├── filelists/       shared filelists pulled in by run.f
│   ├── inc.f        +incdir for the IPs
│   ├── ip.f         packages, common cells, AXI/APB fabric, bus monitors, peripherals, bootloader
│   ├── core.f       real RV32IM core            (core_stub.f = stub core, for imem_boot benches)
│   ├── soc_rtl.f    rtl/*.sv
│   ├── models.f     S25FS512S flash model
│   └── legacy/      the old per-test filelists, kept for reference (paths NOT updated)
├── constraints/     riscforge_soc.sdc
└── sim/             run directory: xcelium.d, *.shm, logs/
```

## Running a test

1. Build the firmware: `cd mem/<fw> && python build.py`
   (`mem/timer`: `python gen_flash_image.py`). This writes `fw_params.svh` — the
   same file name in every firmware folder — with the word counts and the image
   paths the testbench loads.
2. Edit the three SELECT TEST lines at the bottom of `run.f`:
   ```
   +incdir+../mem/regtest          // firmware: provides fw_params.svh
   ../tb/soc_regtest_tb.sv         // testbench file
   -top soc_regtest_tb             // testbench module
   ```
3. From `sim/`: `xrun -f ../run.f -l logs/regtest.log`

Every relative path (filelists, `fw_params.svh` image paths, the boot ROM
`HEX_FILE` default, the flash OTP file) is relative to `sim/`, so always run
from there.

| testbench | firmware folder | core list |
|---|---|---|
| soc_regtest_tb | mem/regtest | core.f |
| soc_montest_tb | mem/montest | core.f |
| soc_i2c_regtest_tb | mem/i2c_regtest | core.f |
| soc_timer0_boot_run_tb | mem/timer | core.f |
| soc_imem_boot_tb, soc_imem_boot_vendor_tb | none (image embedded in TB) | core_stub.f |

The imem_boot benches were written for an older SoC (CLIC, no boot ROM / bus
monitors); see `filelists/legacy/soc_imem_boot*.f` for what they used to compile.
