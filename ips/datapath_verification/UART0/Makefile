# =============================================================================
# RISCFORGE 1TOPS — UART0 Verification Build Makefile
# =============================================================================

CROSS_COMPILE ?= riscv64-unknown-elf-
CC             = $(CROSS_COMPILE)gcc
OBJDUMP        = $(CROSS_COMPILE)objdump
PYTHON         = python3

ARCH_FLAGS     = -march=rv32im_zicsr -mabi=ilp32
CFLAGS         = $(ARCH_FLAGS) -O2 -g -Wall -ffreestanding -nostdlib -fno-builtin
LDFLAGS        = -T link.ld -nostdlib -Wl,--gc-sections

all: imem.hex dmem.hex

app.elf: crt0.S uart_smoke_test.c link.ld uart_min.h
	$(CC) $(CFLAGS) $(LDFLAGS) crt0.S uart_smoke_test.c -o $@
	$(OBJDUMP) -d -S $@ > app.dis

imem.hex dmem.hex: app.elf elf_to_hex.py
	$(PYTHON) elf_to_hex.py app.elf imem.hex dmem.hex

clean:
	rm -f app.elf app.dis imem.hex dmem.hex xrun.log xrun.history *.vcd
	rm -rf xcelium.d simv simv.daidir

.PHONY: all clean

