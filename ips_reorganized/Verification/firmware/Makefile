# =============================================================================
# RISCFORGE 1TOPS — Canonical Firmware Makefile
# =============================================================================

CROSS_COMPILE ?= riscv64-unknown-elf-
CC             = $(CROSS_COMPILE)gcc
OBJCOPY        = $(CROSS_COMPILE)objcopy
OBJDUMP        = $(CROSS_COMPILE)objdump
READELF        = $(CROSS_COMPILE)readelf
PYTHON         = python3

# Target RV32IM_Zicsr with standard soft-float ABI
ARCH_FLAGS     = -march=rv32im_zicsr -mabi=ilp32
CFLAGS         = $(ARCH_FLAGS) -O2 -g -Wall -Wextra -Werror -ffreestanding -nostdlib -fno-builtin \
                 -I./bsp -I./drivers
LDFLAGS        = -T bsp/link.ld -nostdlib -Wl,--gc-sections

BUILD_DIR      = build
TOOLS_DIR      = tools

BSP_SRCS       = bsp/crt0.S bsp/trap_entry.S bsp/irq.c
DRIVER_SRCS    = drivers/uart.c drivers/timer.c drivers/gpio.c drivers/i2c.c drivers/spi.c

TARGETS        = $(BUILD_DIR)/uart_smoke.hex \
                 $(BUILD_DIR)/timer_irq.hex \
                 $(BUILD_DIR)/datapath_asm.hex

all: $(TARGETS)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# -----------------------------------------------------------------------------
# 1. UART Smoke Test
# -----------------------------------------------------------------------------
$(BUILD_DIR)/uart_smoke.elf: $(BSP_SRCS) $(DRIVER_SRCS) tests/uart_smoke_test.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $^ -o $@
	$(OBJDUMP) -d -S $@ > $(BUILD_DIR)/uart_smoke.dis
	$(READELF) -h -l -S $@ > $(BUILD_DIR)/uart_smoke.readelf

$(BUILD_DIR)/uart_smoke.hex: $(BUILD_DIR)/uart_smoke.elf
	$(PYTHON) $(TOOLS_DIR)/elf_to_hex.py $< $(BUILD_DIR)/uart_smoke_imem.hex $(BUILD_DIR)/uart_smoke_dmem.hex
	touch $@

# -----------------------------------------------------------------------------
# 2. Timer Interrupt Test
# -----------------------------------------------------------------------------
$(BUILD_DIR)/timer_irq.elf: $(BSP_SRCS) $(DRIVER_SRCS) tests/timer_interrupt_test.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $^ -o $@
	$(OBJDUMP) -d -S $@ > $(BUILD_DIR)/timer_irq.dis
	$(READELF) -h -l -S $@ > $(BUILD_DIR)/timer_irq.readelf

$(BUILD_DIR)/timer_irq.hex: $(BUILD_DIR)/timer_irq.elf
	$(PYTHON) $(TOOLS_DIR)/elf_to_hex.py $< $(BUILD_DIR)/timer_irq_imem.hex $(BUILD_DIR)/timer_irq_dmem.hex
	touch $@

# -----------------------------------------------------------------------------
# 3. Assembly Datapath Test
# -----------------------------------------------------------------------------
$(BUILD_DIR)/datapath_asm.elf: tests/datapath_smoke_test.s | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $^ -o $@
	$(OBJDUMP) -d -S $@ > $(BUILD_DIR)/datapath_asm.dis
	$(READELF) -h -l -S $@ > $(BUILD_DIR)/datapath_asm.readelf

$(BUILD_DIR)/datapath_asm.hex: $(BUILD_DIR)/datapath_asm.elf
	$(PYTHON) $(TOOLS_DIR)/elf_to_hex.py $< $(BUILD_DIR)/datapath_asm_imem.hex $(BUILD_DIR)/datapath_asm_dmem.hex
	touch $@

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all clean
