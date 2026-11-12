/* ==============================================================================
 * File: link.ld
 * Description: Linker script for RV32I Processor Core (0x8000_0000 base)
 * ============================================================================== */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x80000000, LENGTH = 64K   /* Instruction Memory */
    DMEM (rwx) : ORIGIN = 0x80010000, LENGTH = 64K   /* Data Memory        */
}

SECTIONS
{
    /* Executable Code & Read-Only Data in IMEM */
    .text : ALIGN(4)
    {
        *(.text.init)        /* Entry point _start */
        *(.text .text.*)     /* All C functions */
        *(.rodata .rodata.*) /* Read-only constants */
    } > IMEM

    _sidata = LOADADDR(.data);

    /* Initialized Global Variables in DMEM */
    .data : ALIGN(4)
    {
        _sdata = .;
        PROVIDE(__global_pointer$ = . + 0x800);
        *(.data .data.*)
        *(.sdata .sdata.*)
        _edata = .;
    } > DMEM AT > IMEM

    /* Uninitialized Global Variables (Zero-fill) */
    .bss : ALIGN(4)
    {
        _sbss = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        _ebss = .;
    } > DMEM

    /* Separate section for tohost status */
    .tohost 0x80011000 : ALIGN(4)
    {
        *(.tohost)
    } > DMEM

    /* Stack Top set to end of DMEM */
    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
}
