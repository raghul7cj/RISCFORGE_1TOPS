# =============================================================================
# RISCFORGE Core Interrupt Verification — Synopsys VCS & Verdi Makefile
# =============================================================================

export SNPSLMD_LICENSE_FILE ?= 27020@14.139.1.126
export VCS_HOME             ?= /home/iiita/Synopsys/Installed_tools/vcs/U-2023.03
export VERDI_HOME           ?= /home/iiita/Synopsys/Installed_tools/verdi/U-2023.03-SP1
export PATH                 := $(VCS_HOME)/bin:$(VERDI_HOME)/bin:$(PATH)

# VCS compilation flags: -debug_access+all -kdb automatically enables Verdi & FSDB dumping
VCS_FLAGS = -sverilog \
            -full64 \
            +v2k \
            -timescale=1ns/1ps \
            -debug_access+all \
            -kdb \
            +define+FSDB \
            -l compile.log

FILELIST  = tb1_interrupts.f
SIMV      = ./simv

.PHONY: all hex compile run verdi clean

all: hex compile run

# Step 1: Generate hex files
hex:
	@echo "--- [STEP 1] Generating Hex Memory Images ---"
	python3 gen_tb1_hex.py

# Step 2: Compile with Synopsys VCS
compile: hex
	@echo "--- [STEP 2] Compiling with Synopsys VCS ---"
	vcs $(VCS_FLAGS) -f $(FILELIST) -o $(SIMV)

# Step 3: Run simulation snapshot
run:
	@echo "--- [STEP 3] Running Simulation ---"
	$(SIMV) -l sim.log

# Step 4: Open Verdi with FSDB waveform and source code
verdi:
	@echo "--- [STEP 4] Launching Verdi GUI ---"
	verdi -ssf core_interrupt_tb.fsdb -f $(FILELIST) &

clean:
	rm -rf simv* csrc *.log *.key *.fsdb *.vcd DVEfiles novas.* verdiLog ucli.key

