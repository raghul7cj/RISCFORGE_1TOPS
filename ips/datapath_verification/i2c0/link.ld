/* =============================================================================
 * RISCFORGE 1TOPS — Memory Map Linker Script for I2C0 Datapath
 * ============================================================================= */

MEMORY
{
  /* Instruction SRAM (ISRAM): 32 KB @ 0x0001_0000 */
  ISRAM (rx)  : ORIGIN = 0x00010000, LENGTH = 32K

  /* Data SRAM (DSRAM): 32 KB @ 0x0002_0000 */
  DSRAM (rwx) : ORIGIN = 0x00020000, LENGTH = 32K
}

ENTRY(_start)

SECTIONS
{
  /* -------------------------------------------------------------------------
   * Instruction SRAM: .text, .init, .rodata
   * ------------------------------------------------------------------------- */
  .text :
  {
    . = ALIGN(4);
    _stext = .;
    KEEP(*(.init))
    KEEP(*(.init.*))
    *(.text)
    *(.text.*)
    *(.gnu.linkonce.t.*)
    . = ALIGN(4);
    _etext = .;
  } > ISRAM

  /* -------------------------------------------------------------------------
   * Data SRAM: .rodata, .data, .sdata, .sbss, .bss, Stack
   * ------------------------------------------------------------------------- */
  .rodata :
  {
    . = ALIGN(4);
    _srodata = .;
    *(.rodata)
    *(.rodata.*)
    *(.gnu.linkonce.r.*)
    *(.srodata)
    *(.srodata.*)
    . = ALIGN(4);
    _erodata = .;
  } > DSRAM

  .data :
  {
    . = ALIGN(4);
    _sdata = .;
    *(.data)
    *(.data.*)
    *(.gnu.linkonce.d.*)
    . = ALIGN(4);
    _edata = .;
  } > DSRAM

  .sdata :
  {
    . = ALIGN(4);
    __global_pointer$ = . + 0x800;
    *(.sdata)
    *(.sdata.*)
    *(.gnu.linkonce.s.*)
    . = ALIGN(4);
  } > DSRAM

  .sbss :
  {
    . = ALIGN(4);
    _sbss = .;
    *(.sbss)
    *(.sbss.*)
    *(.gnu.linkonce.sb.*)
    . = ALIGN(4);
  } > DSRAM

  .bss :
  {
    . = ALIGN(4);
    *(.bss)
    *(.bss.*)
    *(.gnu.linkonce.b.*)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;
  } > DSRAM

  /* Stack at the top of 32 KB DSRAM (0x0002_8000) */
  .stack (NOLOAD) :
  {
    . = ALIGN(16);
    . = . + 0x2000; /* 8 KB reserved stack */
    _stack_top = .;
  } > DSRAM

  _end = .;
}
