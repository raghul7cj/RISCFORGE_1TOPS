/* =============================================================================
 * RISCFORGE 1TOPS — SoC Verification Linker Script (link.ld)
 * =============================================================================
 * ISRAM (0x0001_0000, 32 KB): .text (Instructions)
 * DSRAM (0x0002_0000, 32 KB): .mailbox (0x0002_0000..0x0002_003F), .rodata, .data, .bss, stack
 * ============================================================================= */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  BOOTROM (rx)  : ORIGIN = 0x00000000, LENGTH = 64
  ISRAM   (rx)  : ORIGIN = 0x00010000, LENGTH = 32K
  DSRAM   (rwx) : ORIGIN = 0x00020000, LENGTH = 32K
}

SECTIONS
{
  /* -------------------------------------------------------------------------
   * ISRAM: Instructions
   * ------------------------------------------------------------------------- */
  .text :
  {
    . = ALIGN(4);
    *(.text.init)          /* _start must be at 0x0001_0000 */
    *(.text .text.*)
    *(.gnu.linkonce.t.*)
    . = ALIGN(4);
    _etext = .;
  } > ISRAM

  /* -------------------------------------------------------------------------
   * DSRAM: Mailbox fixed at base (0x0002_0000 to 0x0002_003F)
   * ------------------------------------------------------------------------- */
  .mailbox (NOLOAD) :
  {
    . = ALIGN(4);
    _mailbox_base = .;
    *(.mailbox)
    . = _mailbox_base + 0x40; /* 64 Bytes reserved */
  } > DSRAM

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

  /* Stack top at end of 32 KB DSRAM */
  _stack_top = ORIGIN(DSRAM) + LENGTH(DSRAM);

  /DISCARD/ :
  {
    *(.note*)
    *(.comment*)
    *(.eh_frame*)
  }
}
