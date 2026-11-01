/* =============================================================================
 * RISCFORGE 1TOPS — Canonical SoC Linker Script (Direct SRAM Preload)
 * =============================================================================
 * Memory Architecture:
 *   - BootROM : 0x0000_0000 (64 Bytes = 16 words)
 *   - ISRAM   : 0x0001_0000 (32 KiB) - Executable instructions (.text)
 *   - DSRAM   : 0x0002_0000 (32 KiB) - Data, rodata, bss, heap, and stack
 *   - MMIO    : 0x4000_0000 (256 MB) - APB Peripherals window
 * ============================================================================= */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  BOOTROM (rx)  : ORIGIN = 0x00000000, LENGTH = 64
  ISRAM   (rx)  : ORIGIN = 0x00010000, LENGTH = 32K
  DSRAM   (rwx) : ORIGIN = 0x00020000, LENGTH = 32K
  MMIO    (rw)  : ORIGIN = 0x40000000, LENGTH = 256M
}

SECTIONS
{
  /* -------------------------------------------------------------------------
   * ISRAM: Instructions only
   * ------------------------------------------------------------------------- */
  .text :
  {
    . = ALIGN(4);
    _stext = .;
    KEEP(*(.text.init))        /* Mandatory: _start strictly at 0x0001_0000 */
    *(.text .text.*)
    *(.gnu.linkonce.t.*)
    . = ALIGN(4);
    _etext = .;
  } > ISRAM

  /* -------------------------------------------------------------------------
   * DSRAM: Read-only data, initialized data, BSS, stack
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

  /* Reserved 16-byte aligned stack top at end of DSRAM (0x0002_8000) */
  . = ALIGN(16);
  _stack_top = ORIGIN(DSRAM) + LENGTH(DSRAM);

  /* Trap observation signature words at top of DSRAM */
  _trap_sig_cause = _stack_top - 8;
  _trap_sig_epc   = _stack_top - 4;

  /* Discard non-allocatable sections */
  /DISCARD/ :
  {
    *(.note*)
    *(.comment*)
    *(.eh_frame*)
    *(.riscv.attributes)
  }
}

/* ---------------------------------------------------------------------------
 * Boundary Assertions: Enforce Zero Section Overflows & Minimum 1KB Stack
 * --------------------------------------------------------------------------- */
ASSERT(_etext <= (ORIGIN(ISRAM) + LENGTH(ISRAM)), "Error: ISRAM image overflow!");
ASSERT(_ebss <= (ORIGIN(DSRAM) + LENGTH(DSRAM) - 1024), "Error: DSRAM image exceeds boundary, leaves <1KB stack!");
ASSERT(ORIGIN(ISRAM) == 0x00010000, "Error: ISRAM origin must be 0x00010000!");
ASSERT(ORIGIN(DSRAM) == 0x00020000, "Error: DSRAM origin must be 0x00020000!");
