#!/bin/bash

rm -rf xcelium.d *.log *.history *.key cov_work

xrun -64bit -uvm -sv -f ../../files.f -incdir ../../tb -timescale 1ns/1ps -access +rwc -coverage all -covoverwrite -svseed random +UVM_TESTNAME=apb_timer_test +UVM_VERBOSITY=UVM_MEDIUM -l xrun.log
