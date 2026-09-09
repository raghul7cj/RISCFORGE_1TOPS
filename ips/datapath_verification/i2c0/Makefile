# =============================================================================
# RISCFORGE 1TOPS — Bare-Metal I2C0 Application Makefile
# =============================================================================

RISCV_PREFIX ?= riscv64-unknown-elf-
CC      := $(RISCV_PREFIX)gcc
OBJDUMP := $(RISCV_PREFIX)objdump
OBJCOPY := $(RISCV_PREFIX)objcopy

ARCH_FLAGS := -march=rv32im_zicsr -mabi=ilp32
CFLAGS     := $(ARCH_FLAGS) -O2 -g -Wall -ffreestanding -nostdlib -fno-builtin
LDFLAGS    := -T link.ld -nostdlib -Wl,--gc-sections

TARGET     := app.elf
DISASM     := app.dis
IMEM_HEX   := imem.hex
DMEM_HEX   := dmem.hex

SRCS       := crt0.S i2c_smoke_test.c

.PHONY: all clean hex

all: $(TARGET) $(DISASM) hex

$(TARGET): $(SRCS) link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRCS) -o $@

$(DISASM): $(TARGET)
	$(OBJDUMP) -d -S $< > $@

hex: $(TARGET)
	python3 elf_to_hex.py $(TARGET) $(IMEM_HEX) $(DMEM_HEX)

clean:
	rm -f $(TARGET) $(DISASM) $(IMEM_HEX) $(DMEM_HEX) xrun.log xrun.history *.vcd
	rm -rf xcelium.d simv simv.daidir

