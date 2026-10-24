# GPIO standalone address alias debug

## Result

Reproduced the two TC05 observations from `ips/gpio-master/tb_gpio_apb_directed.sv` with Vivado XSim 2022.2. Compilation, elaboration, and simulation succeeded. The bench reports `312 PASSED / 0 FAILED / 2 SUSPECTED RTL ISSUES`; the two `[BUG?]` checks are flagged observations, not simulator/testbench failures.

Observed in `sim.log`:

- Read at APB offset `0x800`: `pslverr=0`, `rdata=0x00000820`, matching the GPIO INFO register.
- Write at APB offset `0x980`: `pslverr=0`, `gpio_out=0xdeadbeef`.

## Root cause and scope

This is a real alias when `gpio_apb_wrap` is selected directly and presented with addresses outside its assigned aperture. The wrapper forwards `paddr` into `apb_to_reg` and has no address-range guard (it does have a separate sub-word write guard). `gpio_reg_top` defaults to `AW=11` and assigns the incoming address into an 11-bit `reg_addr`; upper bits are therefore discarded. Consequently `0x800` folds to register offset `0x000`, and `0x980` folds to `0x180` (`GPIO_OUT`). This explains both observed values.

The testbench directly instantiates the GPIO wrapper and drives APB requests; it does not exercise the SoC crossbar or APB address decoder. Its TC05 comment says the SoC maps a 4 KiB GPIO region, but the current `riscforge_soc_subsystem.sv` map is already narrowed to `[0x4000_3000, 0x4000_3800)`, i.e. 2 KiB, matching the register block's 11-bit aperture. The SoC bridge returns AXI `DECERR` for addresses not matched by its APB decoder. Therefore TC05 does **not** demonstrate a current SoC routing defect. It demonstrates the wrapper's behavior if selected outside its documented SoC range; direct-wrapper callers must honor the aperture, or the wrapper would need its own guard if rejecting such calls is part of its standalone contract.

The core's `hybrid_mem_interface` checks broad SRAM/MMIO routing ranges and routes MMIO to AXI; that broad MMIO range is not the GPIO register decode. Peripheral selection and the 2 KiB GPIO aperture are handled later by the SoC address map/bridge.

No RTL or testbench files were changed for this debug run.

## Reproduction

The run used a temporary staging copy of the GPIO wrapper, its dependencies, and the testbench so generated XSim files stayed out of the source tree. The exact staged compiler file list is `xvlog.f`; the repo's original directed-test file list is `source_tb_gpio_apb_directed.f`.

From the staged `gpio-master` directory, using Vivado 2022.2 on Windows:

```powershell
xvlog --sv -nolog -f xvlog.f
xelab tb_gpio_apb_directed -s gpio_sim --timescale 1ns/1ps
xsim gpio_sim -runall
```

Compile, elaboration, and simulation logs are preserved beside this report. The staged run directory was `%LOCALAPPDATA%\Temp\riscforge_gpio_aperture_debug_20261019\gpio-master`.

## Source evidence

- Directed test assumptions and stimuli: `ips/gpio-master/tb_gpio_apb_directed.sv`, TC05 around lines 646–668. The bench directly calls `apb_xfer()` at offsets `12'h800` and `12'h980`.
- Address truncation: `ips/gpio-master/gpio_reg_top.sv:13,34,51`; `AW=11` and `reg_addr = reg_intf_req.addr`.
- Wrapper forwarding: `ips/gpio-master/gpio_apb_wrap.sv:74–89`; it gates partial writes, otherwise forwards APB `paddr` and `psel` to `apb_to_reg`.
- Current SoC peripheral map: `ips/RTL_SOC/riscforge_soc_subsystem.sv:686–688`; GPIO is mapped to `[0x4000_3000, 0x4000_3800)` with a comment explaining the 2 KiB limit.
- Bridge decode miss: `ips/axi_lite_to_apb/axi_lite_to_apb.sv:265–276,299,316–322`; an invalid APB decode is handled as an AXI decode error without issuing a selected APB peripheral transfer.
- General core routing: `ips/riscv_core/rtl/hybrid_mem_interface.sv:19–20,70–75`; these bounds classify SRAM versus broad MMIO, rather than selecting an individual peripheral.

## Run evidence

- `compile.log`: xvlog completed with exit status 0.
- `elab.log`: xelab completed with exit status 0.
- `sim.log`: xsim completed with exit status 0 and includes the two observations plus the final summary.
- Testbench SHA-256 at run time: `0820AB07B42436F09362CDBD9733C551189A38CD4577E52A1AF4A6D8F7D66BBE`.
- `gpio_reg_top.sv` SHA-256 at run time: `8FCBFB2189098099AE2CAD84C2DDD5FD85241AD3483D574F3EC9E6016F3ED5FB`.
