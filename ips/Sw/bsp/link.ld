/* =============================================================================
 * RISCFORGE 1TOPS — SoC Linker Script (Direct SRAM Preload Architecture)
 * =============================================================================
 * Hardware Preloader (Bootloader/Testbench) preloads:
 *   - ISRAM (0x0001_0000): .text (Instructions)
 *   - DSRAM (0x0002_0000): .rodata, .data (Constants & Initialized Globals)
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
  /* -------------------------------------------------------------------------
   * ISRAM: Executable instructions only
   * ------------------------------------------------------------------------- */
  .text :
  {
    . = ALIGN(4);
    *(.text.init)          /* Entry point _start at 0x0001_0000 */
    *(.text .text.*)
    *(.gnu.linkonce.t.*)
    . = ALIGN(4);
    _etext = .;
  } > ISRAM

  /* -------------------------------------------------------------------------
   * DSRAM: Preloaded directly by Bootloader / Testbench (No software copy needed)
   * ------------------------------------------------------------------------- */
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

  /* Stack Top: End of 32 KB DSRAM */
  _stack_top = ORIGIN(DSRAM) + LENGTH(DSRAM);

  /DISCARD/ :
  {
    *(.note*)
    *(.comment*)
    *(.eh_frame*)
  }
}
