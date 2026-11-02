// Peripheral register access test.   From sim/:  xrun -f ../tests/regtest.f -l logs/regtest.log
-f ../run.f
-f ../filelists/core.f
+incdir+../mem/regtest
../tb/soc_regtest_tb.sv
-top soc_regtest_tb
