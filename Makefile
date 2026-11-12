# Makefile for G4 Unit Testbenches (4.1 PC, 4.3 Register File, 4.5 Branch Unit)
# Primary tool: Synopsys VCS / Verdi (+ URG coverage)

VCS       ?= vcs
URG       ?= urg
VERDI     ?= verdi
VCS_FLAGS ?= -full64 -sverilog +v2k -timescale=1ns/1ps -debug_access+all \
             -cm line+cond+fsm+tgl+branch +define+FSDB

XRUN       ?= xrun
IMC        ?= imc
XRUN_FLAGS ?= -64bit -sv -access +rwc -timescale 1ns/1ps \
              -coverage all -covoverwrite +define+SHM

IVERILOG       ?= iverilog
VVP            ?= vvp
IVERILOG_FLAGS ?= -g2012 -DNO_COVERGROUP -Wall

OUT_DIR   := build
COV_DIR   := $(OUT_DIR)/cov.vdb
CORE_RTL  := $(wildcard ../*.v)
IMC_TEST  ?= core_sanity

.PHONY: all vcs_all vcs_pc vcs_rf vcs_branch vcs_core cov verdi_pc verdi_rf verdi_branch \
        xrun_all xrun_pc xrun_rf xrun_branch xrun_core imc_gui imc_report \
        regress_vcs regress_xrun regress_iverilog \
        iverilog_all iverilog_pc iverilog_rf iverilog_branch iverilog_core clean

all: vcs_all

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

# 4.1 Unit TB for PC unit
vcs_pc: | $(OUT_DIR)
	$(VCS) $(VCS_FLAGS) -cm_dir $(COV_DIR) -cm_name pc_unit \
		-o $(OUT_DIR)/simv_pc ../PC.v ../PC_Adder.v tb_pc_unit.sv
	./$(OUT_DIR)/simv_pc -cm line+cond+fsm+tgl+branch -cm_dir $(COV_DIR) -cm_name pc_unit \
		-l $(OUT_DIR)/pc_unit.log

# 4.3 Unit TB for Register File
vcs_rf: | $(OUT_DIR)
	$(VCS) $(VCS_FLAGS) -cm_dir $(COV_DIR) -cm_name register_file \
		-o $(OUT_DIR)/simv_rf ../Register_File.v tb_register_file.sv
	./$(OUT_DIR)/simv_rf -cm line+cond+fsm+tgl+branch -cm_dir $(COV_DIR) -cm_name register_file \
		-l $(OUT_DIR)/register_file.log

# 4.5 Unit TB for Branch Unit
vcs_branch: | $(OUT_DIR)
	$(VCS) $(VCS_FLAGS) -cm_dir $(COV_DIR) -cm_name branch_unit \
		-o $(OUT_DIR)/simv_branch ../JB_unit.v ../ALU.v tb_branch_unit.sv
	./$(OUT_DIR)/simv_branch -cm line+cond+fsm+tgl+branch -cm_dir $(COV_DIR) -cm_name branch_unit \
		-l $(OUT_DIR)/branch_unit.log

vcs_core: | $(OUT_DIR)
	$(VCS) $(VCS_FLAGS) -cm_dir $(COV_DIR) -cm_name core_sanity \
		-o $(OUT_DIR)/simv_core $(CORE_RTL) tb_core_sanity.sv
	./$(OUT_DIR)/simv_core -cm line+cond+fsm+tgl+branch -cm_dir $(COV_DIR) -cm_name core_sanity \
		-l $(OUT_DIR)/core_sanity.log

vcs_all: vcs_pc vcs_rf vcs_branch vcs_core cov

cov:
	$(URG) -dir $(COV_DIR) -report $(OUT_DIR)/urgReport

verdi_pc:
	$(VERDI) -sv ../PC.v ../PC_Adder.v tb_pc_unit.sv -ssf tb_pc_unit.fsdb &

verdi_rf:
	$(VERDI) -sv ../Register_File.v tb_register_file.sv -ssf tb_register_file.fsdb &

verdi_branch:
	$(VERDI) -sv ../JB_unit.v ../ALU.v tb_branch_unit.sv -ssf tb_branch_unit.fsdb &

# Cadence Xcelium / IMC targets
xrun_pc: | $(OUT_DIR)
	$(XRUN) $(XRUN_FLAGS) -covtest pc_unit -xmlibdirname $(OUT_DIR)/xcelium_pc.d \
		-l $(OUT_DIR)/xrun_pc.log ../PC.v ../PC_Adder.v tb_pc_unit.sv

xrun_rf: | $(OUT_DIR)
	$(XRUN) $(XRUN_FLAGS) -covtest register_file -xmlibdirname $(OUT_DIR)/xcelium_rf.d \
		-l $(OUT_DIR)/xrun_rf.log ../Register_File.v tb_register_file.sv

xrun_branch: | $(OUT_DIR)
	$(XRUN) $(XRUN_FLAGS) -covtest branch_unit -xmlibdirname $(OUT_DIR)/xcelium_branch.d \
		-l $(OUT_DIR)/xrun_branch.log ../JB_unit.v ../ALU.v tb_branch_unit.sv

xrun_core: | $(OUT_DIR)
	$(XRUN) $(XRUN_FLAGS) -covtest core_sanity -xmlibdirname $(OUT_DIR)/xcelium_core.d \
		-l $(OUT_DIR)/xrun_core.log $(CORE_RTL) tb_core_sanity.sv

xrun_all: xrun_pc xrun_rf xrun_branch xrun_core

# 4.9 Unit regression targets
regress_vcs:
	bash ./run_unit_regression.sh vcs 3

regress_xrun:
	bash ./run_unit_regression.sh xrun 3

regress_iverilog:
	bash ./run_unit_regression.sh iverilog 1

imc_gui:
	$(IMC) -gui -load cov_work/scope/$(IMC_TEST) &

imc_report:
	@for t in pc_unit register_file branch_unit core_sanity; do \
		if [ -d "cov_work/scope/$$t" ]; then \
			echo "=== IMC Coverage Summary: $$t ==="; \
			$(IMC) -execcmd "load -run cov_work/scope/$$t; report -summary -all"; \
		fi; \
	done

# Local functional sanity targets (Icarus Verilog)
iverilog_pc: | $(OUT_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $(OUT_DIR)/iv_pc.vvp ../PC.v ../PC_Adder.v tb_pc_unit.sv
	$(VVP) $(OUT_DIR)/iv_pc.vvp

iverilog_rf: | $(OUT_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $(OUT_DIR)/iv_rf.vvp ../Register_File.v tb_register_file.sv
	$(VVP) $(OUT_DIR)/iv_rf.vvp

iverilog_branch: | $(OUT_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $(OUT_DIR)/iv_branch.vvp ../JB_unit.v ../ALU.v tb_branch_unit.sv
	$(VVP) $(OUT_DIR)/iv_branch.vvp

iverilog_core: | $(OUT_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $(OUT_DIR)/iv_core.vvp $(CORE_RTL) tb_core_sanity.sv
	$(VVP) $(OUT_DIR)/iv_core.vvp

iverilog_all: iverilog_pc iverilog_rf iverilog_branch iverilog_core

clean:
	rm -rf $(OUT_DIR) csrc simv* *.daidir ucli.key *.fsdb *.vcd *.shm \
		novas.* verdiLog xcelium.d cov_work xrun.* *.log simvision*
