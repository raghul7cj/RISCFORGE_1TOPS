.section .text.init
.global _start

_start:
    # Initialize stack pointer for Spike
    # DMEM region: 0x80000800 – 0x80000FFF
    # Stack at top of DMEM range
    lui sp, 0x80001
    addi sp, sp, -4    # sp = 0x80000FFC

    # Jump to main C function
    call main

    # Program has finished — halt
    # Write a known marker and use ebreak to stop Spike
end_loop:
    j end_loop
