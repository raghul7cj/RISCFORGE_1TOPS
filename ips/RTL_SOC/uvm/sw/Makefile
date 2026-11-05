CROSS ?= riscv64-unknown-elf-
PROG  ?= hello

HAVE_GCC := $(shell command -v $(CROSS)gcc 2> /dev/null)
MARCH    := $(shell echo | $(CROSS)gcc -march=rv32im_zicsr -mabi=ilp32 -x assembler -c -o /dev/null - 2> /dev/null && echo rv32im_zicsr || echo rv32im)
CFLAGS    = -march=$(MARCH) -mabi=ilp32 -nostdlib -nostartfiles -T link.ld

ifeq ($(HAVE_GCC),)
all:
	@test -f $(PROG).hex || { echo "no $(CROSS)gcc and no prebuilt $(PROG).hex"; exit 1; }
	@true
else
all: $(PROG).hex
endif

%.elf: %.S common.h link.ld
	$(CROSS)gcc $(CFLAGS) -o $@ $<

%.bin: %.elf
	$(CROSS)objcopy -O binary -j .text $< $@

%.hex: %.bin
	od -An -v -tx4 -w4 $< | tr -d ' ' > $@

dump: $(PROG).elf
	$(CROSS)objdump -d $<

clean:
	rm -f *.elf *.bin

.PHONY: all dump clean
.PRECIOUS: %.elf %.bin
