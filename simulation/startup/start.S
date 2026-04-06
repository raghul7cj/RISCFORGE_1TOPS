.section .text.init
.global _start

_start:
    # Initialize stack pointer
    # Data memory is 1024 words = 4KB, indexed by A[31:2]
    # Stack pointer must produce addresses where A[31:2] < 1024
    # i.e., byte address < 0x1000 (4096)
    # Set SP to top of data memory range
    li sp, 0x0FFC

    # Jump to main C function
    call main

    # Program has finished — halt by spinning
end_loop:
    j end_loop
