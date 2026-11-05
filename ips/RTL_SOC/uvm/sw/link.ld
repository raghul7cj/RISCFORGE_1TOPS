OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  ISRAM (rx)  : ORIGIN = 0x00010000, LENGTH = 32K
  DSRAM (rw)  : ORIGIN = 0x00020000, LENGTH = 32K
}

SECTIONS
{
  .text : { *(.text.init) *(.text*) } > ISRAM
  .data : { *(.data*) *(.bss*) } > DSRAM
}
