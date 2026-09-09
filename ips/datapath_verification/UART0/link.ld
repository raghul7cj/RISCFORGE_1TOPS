/* =============================================================================
 * RISCFORGE 1TOPS — SoC Linker Script (Direct SRAM Preload Architecture)
 * ============================================================================= */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  ISRAM (rx)  : ORIGIN = 0x00010000, LENGTH = 32K
  DSRAM (rwx) : ORIGIN = 0x00020000, LENGTH = 32K
}

SECTIONS
{
  .text :
  {
    . = ALIGN(4);
    *(.text.init)
    *(.text .text.*)
    *(.gnu.linkonce.t.*)
    . = ALIGN(4);
    _etext = .;
  } > ISRAM

  .rodata :
  {
    . = ALIGN(4);
    _srodata = .;
    *(.rodata .rodata.*)
    *(.gnu.linkonce.r.*)
    *(.srodata .srodata.*)
    . = ALIGN(4);
    _erodata = .;
  } > DSRAM

  .data :
  {
    . = ALIGN(4);
    _sdata = .;
    PROVIDE(__global_pointer$ = . + 0x800);
    *(.data .data.*)
    *(.gnu.linkonce.d.*)
    *(.sdata .sdata.*)
    *(.gnu.linkonce.s.*)
    . = ALIGN(4);
    _edata = .;
  } > DSRAM

  .bss (NOLOAD) :
  {
    . = ALIGN(4);
    _sbss = .;
    *(.sbss .sbss.*)
    *(.gnu.linkonce.sb.*)
    *(.bss .bss.*)
    *(.gnu.linkonce.b.*)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;
  } > DSRAM

  _stack_top = ORIGIN(DSRAM) + LENGTH(DSRAM);

  /DISCARD/ :
  {
    *(.note*)
    *(.comment*)
    *(.eh_frame*)
  }
}

