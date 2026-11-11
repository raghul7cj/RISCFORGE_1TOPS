// System test (6.12: memory march, interrupts, SPI write). From sim/:  xrun -f ../tests/systest.f -l logs/systest.log
-f ../run.f
-f ../filelists/core.f
+incdir+../mem/systest
../tb/soc_systest_tb.sv
-top soc_systest_tb
