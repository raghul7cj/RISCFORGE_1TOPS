/* Header and entry point */
OUTPUT_ARCH("riscv")
OUTPUT_FORMAT("elf32-littleriscv")
ENTRY(_start)

MEMORY {
    /* Instruction Memory: Read + Execute only (No Write) */
    IMEM (rx) : ORIGIN = 0x80000000, LENGTH = 32K

    /* Data Memory: Read + Write only (No Execute) */
    DMEM (rw) : ORIGIN = 0x80008000, LENGTH = 32K
}

SECTIONS {
    .text : {
        . = ALIGN(4);
        *(.text.init)        /* Startup and reset code first */
        *(.text .text.*)     /* General C functions */
        . = ALIGN(4);
        _etext = .;
    } > IMEM

    .rodata : {
        . = ALIGN(4);
        *(.rodata .rodata.*) /* Constant strings like "hello world !\n" */
        . = ALIGN(4);
    } > DMEM

    .data : {
        . = ALIGN(4);
        _sdata = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        PROVIDE(__global_pointer$ = . + 0x800);
        _edata = .;
    } > DMEM

    .tohost : {
        . = ALIGN(64);
        *(.tohost)
        . = ALIGN(64);
    } > DMEM

    .bss : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > DMEM

    . = ALIGN(16);
    _stack_bottom = .;
    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
}
