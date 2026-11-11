# =============================================================================
# Makefile — RV32M Coprocessor Unit UVM Testbench Runner
# Supports: Cadence Xcelium, Synopsys VCS, and QuestaSim
# =============================================================================

SIM ?= xrun
SEED ?= 1001
GUI ?= 0

XCELIUM_UVM_HOME ?= /home/install/XCELIUM2409/tools/methodology/UVM/CDNS-1.2

.PHONY: all help test-directed test-random test-stress test-regression clean

help:
	@echo "=================================================================="
	@echo "           RV32M Coprocessor UVM Testbench Runner                "
	@echo "=================================================================="
	@echo " Targets:"
	@echo "   make test-directed   : Run 79-vector directed & corner test"
	@echo "   make test-random     : Run 200 randomized transactions"
	@echo "   make test-stress     : Run high-volume mul & div stress test"
	@echo "   make test-regression : Run full suite (corner + rand + stress)"
	@echo "   make clean           : Purge simulation artifacts and logs"
	@echo ""
	@echo " Variables:"
	@echo "   SEED=<num>           : Random seed (default: 1001)"
	@echo "   SIM=xrun|vcs|questa  : Simulator engine (default: xrun)"
	@echo "=================================================================="

all: test-regression

test-directed:
	./run_xrun.sh rv32m_directed_test $(SEED)

test-random:
	./run_xrun.sh rv32m_rand_test $(SEED)

test-stress:
	./run_xrun.sh rv32m_stress_test $(SEED)

test-regression:
	./run_xrun.sh rv32m_regression_test $(SEED)

# VCS Runner Target
vcs-regression:
	mkdir -p sim/vcs_reg_$(SEED)
	cd sim/vcs_reg_$(SEED) && vcs -sverilog -ntb_opts uvm-1.2 -full64 \
		+incdir+../.. +incdir+../../rtl \
		-f ../../filelist.f \
		-assert svaext \
		-cm line+tgl+branch+assert+covgroup \
		-o simv && \
		./simv +UVM_TESTNAME=rv32m_regression_test +ntb_random_seed=$(SEED) \
		-cm line+tgl+branch+assert+covgroup -cm_dir rv32m_cov.vdb -l vcs.log

clean:
	./run_xrun.sh clean
	rm -rf sim/ *.log *.vcd *.history xcelium.d/ cov_work/ work/
