CROSS ?= riscv64-unknown-elf-
PROG  ?= hello

CFLAGS = -march=rv32im_zicsr -mabi=ilp32 -nostdlib -nostartfiles -T link.ld

all: $(PROG).hex

%.elf: %.S common.h link.ld
	$(CROSS)gcc $(CFLAGS) -o $@ $<

%.bin: %.elf
	$(CROSS)objcopy -O binary -j .text $< $@

%.hex: %.bin
	hexdump -v -e '1/4 "%08x\n"' $< > $@

dump: $(PROG).elf
	$(CROSS)objdump -d $<

clean:
	rm -f *.elf *.bin *.hex

.PRECIOUS: %.elf %.bin
