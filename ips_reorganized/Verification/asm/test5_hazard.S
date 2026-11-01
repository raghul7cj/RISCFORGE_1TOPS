# ==============================================================================
# RISCFORGE Test 5: Multi-Cycle DIV Stall Collision
# ==============================================================================
.section .text
.globl _start

_start:
    la      t0, isr_handler
    csrw    mtvec, t0

    li      t0, 0x00000080             # Enable MTIE
    csrw    mie, t0
    csrsi   mstatus, 0x8               # Enable global MIE

    li      t0, 0x80001000             # DMEM Base
    li      a1, 1000000                # Dividend
    li      a2, 7                      # Divisor
    li      s0, 0                      # Quotient destination

    j       div_target

.org 0x40
div_target:
    div     s0, a1, a2                 # 0x8000_0040: Multi-cycle DIV in EX stage (stallMUL)
    sw      s0, 4(t0)                  # 0x8000_0044: Store quotient (142857) to DMEM[1]
    nop
    nop

    # Write completion sentinel
    li      gp, 0xCAFEBABE
    sw      gp, 0(t0)                  # Store sentinel to DMEM[0]
park:
    j       park

.org 0x100
isr_handler:
    csrr    s1, mcause                 # Expected: 0x8000_0007
    csrr    s2, mepc                   # Expected: 0x8000_0044 (instruction following completed DIV)
    sw      s1, 8(t0)                  # Store mcause to DMEM[2]
    sw      s2, 12(t0)                 # Store mepc to DMEM[3]
    csrci   mie, 0x80                  # Clear MTIE
    mret                               # Return to resume store & retirement

