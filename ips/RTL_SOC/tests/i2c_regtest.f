// I2C register access test.   From sim/:  xrun -f ../tests/i2c_regtest.f -l logs/i2c_regtest.log
-f ../run.f
-f ../filelists/core.f
+incdir+../mem/i2c_regtest
../tb/soc_i2c_regtest_tb.sv
-top soc_i2c_regtest_tb
