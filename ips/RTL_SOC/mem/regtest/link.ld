/* =============================================================================
 * RISCFORGE 1TOPS - linker script for the register access test
 * =============================================================================
 * Code goes to ISRAM; EVERYTHING the program loads (.rodata, .data, .bss,
 * stack) goes to DSRAM. hybrid_mem_interface does not decode ISRAM for data
 * accesses, so a load from 0x0001_xxxx raises a load access fault: constants
 * and tables must not be left in ISRAM.
 *
 * There is no LMA/VMA split and no .data copy loop. The bootloader writes the
 * first NUM_INSTR_WORDS image words to ISRAM and the rest straight to DSRAM,
 * so the DSRAM part of the image is laid out exactly as it must sit in DSRAM,
 * starting at ORIGIN(DSRAM).
 *
 *   0x0002_0000  .results  (NOLOAD, 64 B)  result words watched by the TB
 *   0x0002_0040  .rodata / .data            loaded by the bootloader
 *   ...          .bss      (NOLOAD)        zeroed by startup.S
 *   0x0002_8000  stack top (grows down)
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
    *(.rodata .rodata.* .srodata .srodata.*)
  } > DSRAM

  .data : ALIGN(4) {
    *(.data .data.* .sdata .sdata.*)
  } > DSRAM

  .bss (NOLOAD) : ALIGN(4) {
    _bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > DSRAM

  _stack_top = ORIGIN(DSRAM) + LENGTH(DSRAM);

  ASSERT(ADDR(.text)    == 0x00010000, "_start must be at the ISRAM base (BootROM jump target)")
  ASSERT(ADDR(.results) == 0x00020000, "result words must sit at the DSRAM base (soc_regtest_tb.sv)")
  ASSERT(_bss_end <= _stack_top - 0x800, "less than 2 KB left for the stack")
}
