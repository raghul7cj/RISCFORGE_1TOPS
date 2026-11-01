# Exact monitor path follow-up

The monitor smoke now requires a single UART write to be recorded exactly once at each layer. It checks direction, address/slot, data, byte enables/strobes, and LSU→AXI→APB timestamp order. The first follow-up run (`../exact_join/`) failed because the LSU monitor record had `be=0000`; `rf_monitors.sv` was changed to build the packed record atomically. This run passes with `be=1111` at all three layers.

The test uses a deterministic structural monitor stub. It proves the monitor capture/join harness, not SoC firmware accounting.

From this directory:

```powershell
xvlog.bat -sv -nolog -i inputs -f exact_join.f
xelab.bat -nolog -timescale 1ns/1ps rf_mon_smoke_tb -s rf_mon_exact_join_fixed
xsim.bat rf_mon_exact_join_fixed -runall -log simulation.log
```

`SMOKE TEST PASSED` and `J4.exact_uart_path` are in `simulation.stdout.log`; the complete monitor dump is `monitor_postmortem.txt`.
