// Timer 0 boot-to-runtime test.   From sim/:  xrun -f ../tests/timer0.f -l logs/timer0.log
-f ../run.f
-f ../filelists/core.f
+incdir+../mem/timer
../tb/soc_timer0_boot_run_tb.sv
-top soc_timer0_boot_run_tb
