/* Linker script for Spike ISA simulator
 *
 * Spike requires memory at 0x80000000 (default DRAM base).
 * This script mirrors the RTL linker layout but rebased.
 *
 * IMEM: 0x80000000 (2KB for instructions)
 * DMEM: 0x80000800 (2KB for data + stack)
 */

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x80000000, LENGTH = 2K
    DMEM (rwx) : ORIGIN = 0x80000800, LENGTH = 2K
}

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text*)
    } > IMEM

    .rodata : {
        *(.rodata*)
    } > DMEM

    .data : {
        *(.data*)
    } > DMEM

    .bss : {
        *(.bss*)
        *(COMMON)
    } > DMEM
}
