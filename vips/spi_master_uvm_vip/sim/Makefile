TEST       ?= spi_smoke_read_test
SEED       ?= 1
VERBOSITY  ?= UVM_MEDIUM
NUM_TRANS  ?= 50
EXTRA_ARGS ?=
COV        ?= 1

PLUSARGS = +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) +NUM_TRANS=$(NUM_TRANS)

XRUN_COV_ARGS = -coverage all -covoverwrite -covdut spi_tb_top -covtest $(TEST)
VCS_COV_ARGS  = -cm line+cond+fsm+tgl+branch

ifeq ($(COV),1)
  XCOV := $(XRUN_COV_ARGS)
  VCOV := $(VCS_COV_ARGS)
else
  XCOV :=
  VCOV :=
endif

TESTS = spi_smoke_read_test spi_sequential_read_test spi_burst_read_test \
        spi_quad_read_test spi_write_test spi_overflow_test \
        spi_empty_fifo_stall_test spi_reset_test spi_flash_read_test spi_flash_fast_read_test spi_random_test \
        spi_regression_test

.PHONY: vcs vcs_compile xcelium covreport_xcelium covreport_vcs \
        regress_xcelium regress_vcs covreport_all_xcelium clean

xcelium:
	xrun -sv -uvm -timescale 1ns/1ps $(XCOV) -f filelist.f $(EXTRA_ARGS) -svseed $(SEED) $(PLUSARGS)

regress_xcelium:
	@for t in $(TESTS); do \
	    echo "=== Running $$t (Xcelium) ==="; \
	    $(MAKE) xcelium TEST=$$t COV=1 || exit 1; \
	done

covreport_xcelium:
	@echo 'load_test -run cov_work/scope/$(TEST)' > /tmp/covrpt_$(TEST).tcl
	@echo 'report -summary -out cov_summary_$(TEST).txt' >> /tmp/covrpt_$(TEST).tcl
	@echo 'report -detail -html -out cov_html_$(TEST)' >> /tmp/covrpt_$(TEST).tcl
	@echo 'exit -force' >> /tmp/covrpt_$(TEST).tcl
	imc -exec /tmp/covrpt_$(TEST).tcl

covreport_all_xcelium:
	@for t in $(TESTS); do \
	    echo "=== Report for $$t ==="; \
	    $(MAKE) covreport_xcelium TEST=$$t; \
	done

vcs_compile:
	vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps $(VCOV) -f filelist.f $(EXTRA_ARGS) -o simv

vcs: vcs_compile
	./simv $(VCOV) -cm_name $(TEST) -cm_dir cm_$(TEST).vdb +ntb_random_seed=$(SEED) $(PLUSARGS)

regress_vcs: 
	$(MAKE) vcs_compile COV=1
	@for t in $(TESTS); do \
	    echo "=== Running $$t (VCS) ==="; \
	    ./simv $(VCS_COV_ARGS) -cm_name $$t -cm_dir cm_$$t.vdb +ntb_random_seed=$(SEED) \
	        +UVM_TESTNAME=$$t +UVM_VERBOSITY=$(VERBOSITY) +NUM_TRANS=$(NUM_TRANS) || exit 1; \
	done

covreport_vcs:
	urg -dir cm_$(TEST).vdb -report urgReport_$(TEST)

covreport_all_vcs:
	@for t in $(TESTS); do \
	    echo "=== Report for $$t (VCS) ==="; \
	    urg -dir cm_$$t.vdb -report urgReport_$$t; \
	done

clean:
	rm -rf simv simv.daidir csrc *.log *.vcd xcelium.d xrun.log xrun.history \
	       .simvision INCA_libs cov_work cov_html_* cov_summary_*.txt \
	       urgReport_* cm_*.vdb /tmp/covrpt_*.tcl
