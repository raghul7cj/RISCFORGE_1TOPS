// Pong test.   From sim/:  xrun -f ../tests/pong.f -l logs/pong.log
-f ../run.f
-f ../filelists/core.f
+incdir+../mem/pong/sim_build
../tb/soc_pong_tb.sv
-top soc_pong_tb
