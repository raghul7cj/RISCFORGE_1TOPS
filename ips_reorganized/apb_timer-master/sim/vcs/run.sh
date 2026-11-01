#!/bin/bash

rm -rf simv simv.daidir csrc *.log *.vdb urgReport

vcs -full64 \
    -sverilog \
    -ntb_opts uvm-1.2 \
    -timescale=1ns/1ps \
    -f ../../files.f \
    +incdir+../../tb \
    -debug_access+all \
    -cm line+cond+fsm+tgl+branch+assert \
    -cm_dir apb_timer.vdb \
    -o simv \
    -l compile.log

./simv \
    +UVM_TESTNAME=apb_timer_test \
    +UVM_VERBOSITY=UVM_MEDIUM \
    +ntb_random_seed_automatic \
    -cm line+cond+fsm+tgl+branch+assert \
    -cm_dir apb_timer.vdb \
    -l sim.log

urg \
    -dir apb_timer.vdb \
    -report CoverageReport \
    -format both
