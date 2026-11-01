# =============================================================================
# RISCFORGE 1TOPS - Minimal Software Build Makefile
# =============================================================================

CROSS_COMPILE ?= riscv64-unknown-elf-
CC             = $(CROSS_COMPILE)gcc
OBJCOPY        = $(CROSS_COMPILE)objcopy
OBJDUMP        = $(CROSS_COMPILE)objdump
PYTHON         = python3

# Target architecture matching RV32IM_Zicsr
ARCH_FLAGS     = -march=rv32im_zicsr -mabi=ilp32
CFLAGS         = $(ARCH_FLAGS) -O2 -g -Wall -ffreestanding -nostdlib -fno-builtin -I./bsp
LDFLAGS        = -T bsp/link.ld -nostdlib -Wl,--gc-sections

BUILD_DIR      = build
TOOLS_DIR      = tools

BSP_SRCS       = bsp/crt0.S bsp/trap_entry.S bsp/irq.c

all: $(BUILD_DIR)/uart_smoke.hex $(BUILD_DIR)/timer_irq.hex $(BUILD_DIR)/datapath_asm.hex

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# 1. C-based UART smoke test
$(BUILD_DIR)/uart_smoke.elf: $(BSP_SRCS) tests/uart_smoke_test.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $^ -o $@
	$(OBJDUMP) -d -S $@ > $(BUILD_DIR)/uart_smoke.dis

$(BUILD_DIR)/uart_smoke.hex: $(BUILD_DIR)/uart_smoke.elf
	$(PYTHON) $(TOOLS_DIR)/elf_to_hex.py $< $(BUILD_DIR)/uart_smoke_imem.hex $(BUILD_DIR)/uart_smoke_dmem.hex

# 2. C-based End-to-End Timer Interrupt Test
$(BUILD_DIR)/timer_irq.elf: $(BSP_SRCS) tests/timer_interrupt_test.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $^ -o $@
	$(OBJDUMP) -d -S $@ > $(BUILD_DIR)/timer_irq.dis

$(BUILD_DIR)/timer_irq.hex: $(BUILD_DIR)/timer_irq.elf
	$(PYTHON) $(TOOLS_DIR)/elf_to_hex.py $< $(BUILD_DIR)/timer_irq_imem.hex $(BUILD_DIR)/timer_irq_dmem.hex

# 3. Pure ASM Datapath test
$(BUILD_DIR)/datapath_asm.elf: tests/datapath_smoke_test.s | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $^ -o $@
	$(OBJDUMP) -d -S $@ > $(BUILD_DIR)/datapath_asm.dis

$(BUILD_DIR)/datapath_asm.hex: $(BUILD_DIR)/datapath_asm.elf
	$(PYTHON) $(TOOLS_DIR)/elf_to_hex.py $< $(BUILD_DIR)/datapath_asm_imem.hex $(BUILD_DIR)/datapath_asm_dmem.hex

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all clean
