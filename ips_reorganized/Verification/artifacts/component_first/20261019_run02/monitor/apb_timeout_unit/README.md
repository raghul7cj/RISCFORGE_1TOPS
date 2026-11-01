# APB timeout monitor unit run

Vivado XSim 2022.2; top `tb_apb_timeout_monitor`; 14 checks passed at 160 ns. The test uses the actual `ips/bus_monitors/apb_timeout_monitor.sv` with a three-cycle threshold and checks transparent response, early completion, timeout response (`PREADY=1`, `PSLVERR=1`, `PRDATA=0xDEADBEEF`), sticky status, access clear, and reset recovery.

From this directory:

```powershell
xvlog.bat -sv -f unit.f
xelab.bat -nolog -timescale 1ns/1ps tb_apb_timeout_monitor -s apb_tmo_unit
xsim.bat apb_tmo_unit -runall -log simulation.log
```

`TEST_PASS checks=14` is in `simulation.stdout.log`. Source snapshot and compile/elaboration/simulation logs are preserved here.
