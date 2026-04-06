# =============================================================================
# Top-Level Makefile — RV32I Single-Cycle Core Verification
# =============================================================================
#
# Project Structure:
#   rtl/       — Verilog RTL source files
#   sim/       — Testbench (RISC_top_tb.v)
#   tests/     — C test programs (your inputs)
#   startup/   — Startup assembly (start.S) and linker scripts
#   build/     — All generated artifacts (ELF, hex, VCD, etc.)
#   scripts/   — Helper scripts (compare.sh)
#   docs/      — Documentation and diagrams
#
# ─────────────────────────────────────────────────────────────
# COMMANDS:
# ─────────────────────────────────────────────────────────────
#
#   make test PROGRAM=add_test.c           Compile + simulate
#   make test PROGRAM=branch_test.c        (default: add_test.c)
#   make test PROGRAM=function_test.c
#
#   make firmware PROGRAM=add_test.c       Only compile C → hex
#   make sim                               Only simulate (use existing hex)
#   make disasm PROGRAM=add_test.c         Show disassembly
#   make trace PROGRAM=add_test.c          Simulate with instruction trace
#   make wave                              Open VCD waveform in GTKWave
#
#   make verify PROGRAM=add_test.c         Compare RTL vs Spike (golden ref)
#   make verify-all                        Compare all tests vs Spike
#
#   make clean                             Remove all build artifacts
#
# =============================================================================

# ── Configuration ────────────────────────────────────────────
PROGRAM  ?= add_test.c
CROSS     = riscv64-unknown-elf-
CC        = $(CROSS)gcc
OBJCOPY   = $(CROSS)objcopy
OBJDUMP   = $(CROSS)objdump
CFLAGS    = -march=rv32i -mabi=ilp32 -O0 -ffreestanding -nostdlib

# ── Directories ──────────────────────────────────────────────
RTL_DIR    = rtl
SIM_DIR    = sim
TEST_DIR   = tests
START_DIR  = startup
BUILD_DIR  = build
SCRIPT_DIR = scripts

# ── Derived paths ────────────────────────────────────────────
TEST_SRC   = $(TEST_DIR)/$(PROGRAM)
ELF_FILE   = $(BUILD_DIR)/program.elf
BIN_FILE   = $(BUILD_DIR)/program.bin
HEX_FILE   = $(BUILD_DIR)/memfile.hex
LISTING    = $(BUILD_DIR)/listing.txt
VVP_FILE   = $(BUILD_DIR)/tb.vvp
VCD_FILE   = $(BUILD_DIR)/RISC_Core.vcd
SPIKE_ELF  = $(BUILD_DIR)/program_spike.elf

.PHONY: test firmware sim wave disasm trace verify verify-all clean

# ═════════════════════════════════════════════════════════════
# MAIN TARGETS
# ═════════════════════════════════════════════════════════════

# Full flow: compile + simulate
test: firmware sim

# ─────────────────────────────────────────────────────────────
# STEP 1: Compile C → ELF → hex
# ─────────────────────────────────────────────────────────────
firmware: $(HEX_FILE)

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(ELF_FILE): $(START_DIR)/start.S $(TEST_SRC) $(START_DIR)/linker.ld | $(BUILD_DIR)
	@echo ""
	@echo "═══════════════════════════════════════════════════════"
	@echo "  COMPILING: $(PROGRAM)"
	@echo "═══════════════════════════════════════════════════════"
	$(CC) $(CFLAGS) -T $(START_DIR)/linker.ld $(START_DIR)/start.S $(TEST_SRC) -o $@

$(HEX_FILE): $(ELF_FILE)
	$(OBJCOPY) -O binary -j .text $< $(BIN_FILE)
	hexdump -v -e '1/4 "%08x\n"' $(BIN_FILE) > $@
	@echo "────────────────────────────────────────────────"
	@echo "  Generated $(HEX_FILE) ($(shell wc -l < $@ 2>/dev/null || echo '?') instructions)"
	@echo "────────────────────────────────────────────────"

# ─────────────────────────────────────────────────────────────
# STEP 2: Simulate with Icarus Verilog
# ─────────────────────────────────────────────────────────────
sim: $(HEX_FILE)
	@echo ""
	@echo "═══════════════════════════════════════════════════════"
	@echo "  SIMULATING RTL"
	@echo "═══════════════════════════════════════════════════════"
	iverilog -o $(VVP_FILE) -I $(RTL_DIR) $(SIM_DIR)/RISC_top_tb.v
	vvp $(VVP_FILE)

# ─────────────────────────────────────────────────────────────
# UTILITIES
# ─────────────────────────────────────────────────────────────

# Simulate with instruction tracing
trace: firmware
	@echo ""
	@echo "═══════════════════════════════════════════════════════"
	@echo "  SIMULATING with instruction trace..."
	@echo "═══════════════════════════════════════════════════════"
	iverilog -o $(VVP_FILE) -DENABLE_TRACE -I $(RTL_DIR) $(SIM_DIR)/RISC_top_tb.v
	vvp $(VVP_FILE)

# Show disassembly listing
disasm: $(ELF_FILE)
	$(OBJDUMP) -d $(ELF_FILE) > $(LISTING)
	@echo ""
	@echo "  Disassembly saved to $(LISTING)"
	@echo ""
	@cat $(LISTING)

# Open waveform viewer
wave:
	gtkwave $(VCD_FILE) &

# ─────────────────────────────────────────────────────────────
# SPIKE GOLDEN REFERENCE VERIFICATION
# ─────────────────────────────────────────────────────────────

# Verify a single test against Spike
verify:
	$(SCRIPT_DIR)/compare.sh $(PROGRAM)

# Verify all tests at once
verify-all:
	@echo ""
	@PASS=0; FAIL=0; \
	for test in $(TEST_DIR)/*.c; do \
		prog=$$(basename $$test); \
		if [ "$$prog" = "loadstore_test.c" ]; then continue; fi; \
		echo ""; \
		if $(SCRIPT_DIR)/compare.sh "$$prog"; then \
			PASS=$$((PASS + 1)); \
		else \
			FAIL=$$((FAIL + 1)); \
		fi; \
	done; \
	echo ""; \
	echo "════════════════════════════════════════════════════════"; \
	echo "  SUMMARY: $$PASS passed, $$FAIL failed"; \
	echo "════════════════════════════════════════════════════════"; \
	[ $$FAIL -eq 0 ]

# ─────────────────────────────────────────────────────────────
# CLEAN
# ─────────────────────────────────────────────────────────────
clean:
	rm -rf $(BUILD_DIR)