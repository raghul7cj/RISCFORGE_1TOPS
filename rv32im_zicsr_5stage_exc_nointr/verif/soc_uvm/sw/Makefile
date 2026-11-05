CROSS ?= riscv64-unknown-elf-
PROG  ?= hello

CFLAGS = -march=rv32im_zicsr -mabi=ilp32 -nostdlib -nostartfiles -T link.ld

all: $(PROG).hex

%.elf: %.S common.h link.ld
	$(CROSS)gcc $(CFLAGS) -o $@ $<

%.bin: %.elf
	$(CROSS)objcopy -O binary -j .text $< $@

%.hex: %.bin
	od -An -v -tx4 -w4 $< | tr -d ' ' > $@

dump: $(PROG).elf
	$(CROSS)objdump -d $<

clean:
	rm -f *.elf *.bin *.hex

.PRECIOUS: %.elf %.bin
