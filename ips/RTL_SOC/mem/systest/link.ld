/* =============================================================================
 * RISCFORGE 1TOPS - linker script for the system test (systest)
 * =============================================================================
 * Same layout as mem/regtest/link.ld: code in ISRAM, everything the program
 * loads (.rodata, .data, .bss, stack) in DSRAM. hybrid_mem_interface does not
 * decode ISRAM for data accesses, so constants must not be left in ISRAM.
 *
 * Added for systest: the DSRAM range the memory test may overwrite.
 *
 *   0x0002_0000     .results  (NOLOAD, 64 B)  result words watched by the TB
 *   0x0002_0040     .rodata / .data            loaded by the bootloader
 *   ...             .bss      (NOLOAD)         zeroed by startup.S
 *   _memtest_start  first free word (16-byte aligned) after .bss
 *   _memtest_end    = _stack_top - 2 KB        (stack lives above it)
 *   0x0002_8000     stack top (grows down)
 * ========================================================================== */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  ISRAM (rx)  : ORIGIN = 0x00010000, LENGTH = 32K
  DSRAM (rw)  : ORIGIN = 0x00020000, LENGTH = 32K
}

SECTIONS {
  .text : {
    KEEP(*(.text.init))          /* _start must be first: BootROM jumps to 0x0001_0000 */
    *(.text .text.*)
  } > ISRAM

  .results (NOLOAD) : {
    . = . + 0x40;
  } > DSRAM

  .rodata : ALIGN(4) {
    _img_start = .;
    *(.rodata .rodata.* .srodata .srodata.*)
  } > DSRAM

  .data : ALIGN(4) {
    *(.data .data.* .sdata .sdata.*)
    . = ALIGN(4);
    _img_end = .;
  } > DSRAM

  .bss (NOLOAD) : ALIGN(4) {
    _bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > DSRAM

  _stack_top     = ORIGIN(DSRAM) + LENGTH(DSRAM);
  _memtest_start = ALIGN(_bss_end, 16);
  _memtest_end   = _stack_top - 0x800;

  ASSERT(ADDR(.text)    == 0x00010000, "_start must be at the ISRAM base (BootROM jump target)")
  ASSERT(ADDR(.results) == 0x00020000, "result words must sit at the DSRAM base (soc_systest_tb.sv)")
  ASSERT(_memtest_end >= _memtest_start + 0x4000, "memory test range is smaller than 16 KB")
}
