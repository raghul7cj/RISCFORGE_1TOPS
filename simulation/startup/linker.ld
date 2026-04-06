/* Linker script for RV32I single-cycle core
 *
 * Memory architecture:
 *   - IMEM: Separate hardware, 1024 words, loaded from memfile.hex
 *   - DMEM: Separate hardware, 1024 words, byte addresses 0x0000–0x0FFF
 *
 * Both memories physically occupy address range 0–0xFFF.
 * The linker sees a flat address space, so we must arrange
 * sections to avoid overlap:
 *   .text at 0x0000 (goes into IMEM via PC bus)
 *   .data at 0x0800 (goes into DMEM via ALU bus)
 *
 * In hardware, loads/stores go through alu_result → DMEM,
 * while fetches go through PC → IMEM. No real conflict.
 * We set .data at 0x800 just to keep the linker happy.
 * Stack (sp=0x0FFC) grows down from top of DMEM range.
 */

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 2K
    DMEM (rwx) : ORIGIN = 0x00000800, LENGTH = 2K
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
