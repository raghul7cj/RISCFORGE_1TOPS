# ==============================================================================
# Makefile for Bare-metal Firmware and RTL Simulation
# ==============================================================================

PREFIX   ?= riscv32-unknown-elf-
CC       := $(PREFIX)gcc
OBJCOPY  := $(PREFIX)objcopy
OBJDUMP  := $(PREFIX)objdump
NM       := $(PREFIX)nm

RTL_DIR  := ../RISCFORGE_1TOPS/ips_reorganized/riscv_core/rtl
TARGET   := firmware
SRCS     := start.s main.c

all: $(TARGET).elf $(TARGET).mem $(TARGET).disass imem.hex dmem.hex

$(TARGET).elf: $(SRCS) link.ld
	$(CC) -march=rv32im -mabi=ilp32 -O2 -nostdlib -T link.ld $(SRCS) -o $@

$(TARGET).mem: $(TARGET).elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 --change-addresses=-0x80000000 $< $@

imem.hex: $(TARGET).mem
	cp $(TARGET).mem imem.hex

dmem.hex: $(TARGET).mem
	cp $(TARGET).mem dmem.hex

$(TARGET).disass: $(TARGET).elf
	$(OBJDUMP) -d $< > $@

# Run RTL simulation of the firmware
sim: all
	@TOHOST_ADDR=$$($(NM) $(TARGET).elf | grep -w "tohost" | awk '{print $$1}'); \
	iverilog -g2012 -o firmware_sim.vvp \
		$(RTL_DIR)/ALU.v \
		$(RTL_DIR)/ALU_Decoder.v \
		$(RTL_DIR)/Control_Unit_Top.v \
		$(RTL_DIR)/Data_Memory.v \
		$(RTL_DIR)/Instruction_Memory.v \
		$(RTL_DIR)/JB_unit.v \
		$(RTL_DIR)/Main_Decoder.v \
		$(RTL_DIR)/Mux2.v \
		$(RTL_DIR)/Mux_3_by_1.v \
		$(RTL_DIR)/PC.v \
		$(RTL_DIR)/PC_Adder.v \
		$(RTL_DIR)/Register_File.v \
		$(RTL_DIR)/Sign_Extend.v \
		$(RTL_DIR)/booth_enc.v \
		$(RTL_DIR)/csa.v \
		$(RTL_DIR)/csr_regfile.v \
		$(RTL_DIR)/decode_cycle.v \
		$(RTL_DIR)/execute_cycle.v \
		$(RTL_DIR)/fetch_cycle.v \
		$(RTL_DIR)/hazard_unit.v \
		$(RTL_DIR)/imem_controller.v \
		$(RTL_DIR)/irq_arbiter.v \
		$(RTL_DIR)/irq_gateway.v \
		$(RTL_DIR)/ls_unit.v \
		$(RTL_DIR)/memory_cycle.v \
		$(RTL_DIR)/opcode_check.v \
		$(RTL_DIR)/pp_gen.v \
		$(RTL_DIR)/rv32m_div.v \
		$(RTL_DIR)/rv32m_mul.v \
		$(RTL_DIR)/rv32m_unit.v \
		tb_firmware.v \
		$(RTL_DIR)/top.v \
		$(RTL_DIR)/wb_trap_mret_commit_controller.v \
		$(RTL_DIR)/writeback_cycle.v && \
	vvp firmware_sim.vvp +tohost_addr=$$TOHOST_ADDR

clean:
	rm -f *.elf *.mem *.disass *.hex *.vvp *.vcd

.PHONY: all sim clean
