// Bus timeout monitor test.   From sim/:  xrun -f ../tests/montest.f -l logs/montest.log
-f ../run.f
-f ../filelists/core.f
+incdir+../mem/montest
../tb/soc_montest_tb.sv
-top soc_montest_tb
