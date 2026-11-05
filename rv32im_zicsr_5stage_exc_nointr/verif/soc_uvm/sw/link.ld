OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  ISRAM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
  DSRAM (rwx) : ORIGIN = 0x00010000, LENGTH = 4K
}

SECTIONS
{
  .text : { *(.text.init) *(.text*) } > ISRAM
  .data : { *(.data*) *(.bss*) } > DSRAM
}
