#!/usr/bin/env python3
"""
gen_tb1_hex.py — Directed RISC-V Hex Test Generator for Core Interrupt Verification
Generates paired <test>_imem.hex and <test>_dmem.hex memory files for tb1_interrupts.sv.

Scenarios:
  Test 1: Basic Timer Interrupt (MTIP, mepc, mcause, flush, mret, DMEM write)
  Test 2: All 7 Interrupt Sources Sequentially (UART, SPI, I2C, GPIO, MEIP, MTIP, MSIP)
  Test 3: Priority Resolution (Simultaneous multi-line assertion, DMEM order table)
  Test 4: mintprio Priority Threshold Gate (CSR 0x7C0, blocked vs accepted)
  Test 5: Multi-cycle DIV Stall Collision (stallMUL hazard, DMEM quotient write)
  Test 6: Interrupt vs Synchronous Exception Collision (2 Continuous Branch Misaligned instructions)
  Test 7: Full MRET Roundtrip & State Preservation (DMEM preloaded operands, checksum write)
"""

import os
import sys

# ==============================================================================
# RISC-V RV32I / Zicsr Instruction Encoders
# ==============================================================================

def NOP():
    return 0x00000013  # addi x0, x0, 0

def ADDI(rd, rs1, imm):
    imm12 = imm & 0xFFF
    return (imm12 << 20) | ((rs1 & 0x1F) << 15) | (0x0 << 12) | ((rd & 0x1F) << 7) | 0x13

def ADD(rd, rs1, rs2):
    return (0x00 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | (0x0 << 12) | ((rd & 0x1F) << 7) | 0x33

def SUB(rd, rs1, rs2):
    return (0x20 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | (0x0 << 12) | ((rd & 0x1F) << 7) | 0x33

def SLLI(rd, rs1, shamt):
    return ((shamt & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | (0x1 << 12) | ((rd & 0x1F) << 7) | 0x13

def LUI(rd, imm20):
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | 0x37

def JAL(rd, byte_offset):
    # RISC-V J-immediate layout: imm[20] | imm[10:1] | imm[11] | imm[19:12]
    imm = byte_offset & 0x1FFFFF
    imm20 = (imm >> 20) & 0x1
    imm10_1 = (imm >> 1) & 0x3FF
    imm11 = (imm >> 11) & 0x1
    imm19_12 = (imm >> 12) & 0xFF
    instr_31_12 = (imm20 << 19) | (imm10_1 << 9) | (imm11 << 8) | imm19_12
    return (instr_31_12 << 12) | ((rd & 0x1F) << 7) | 0x6F

def JALR(rd, rs1, imm):
    imm12 = imm & 0xFFF
    return (imm12 << 20) | ((rs1 & 0x1F) << 15) | (0x0 << 12) | ((rd & 0x1F) << 7) | 0x67

def B_TYPE(rs1, rs2, byte_offset, funct3):
    imm = byte_offset & 0x1FFF
    imm12 = (imm >> 12) & 0x1
    imm10_5 = (imm >> 5) & 0x3F
    imm4_1 = (imm >> 1) & 0xF
    imm11 = (imm >> 11) & 0x1
    instr_31_25 = (imm12 << 6) | imm10_5
    instr_11_7 = (imm4_1 << 1) | imm11
    return (instr_31_25 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | (instr_11_7 << 7) | 0x63

def BEQ(rs1, rs2, byte_offset):
    return B_TYPE(rs1, rs2, byte_offset, 0x0)

def BNE(rs1, rs2, byte_offset):
    return B_TYPE(rs1, rs2, byte_offset, 0x1)

def LW(rd, rs1, imm):
    imm12 = imm & 0xFFF
    return (imm12 << 20) | ((rs1 & 0x1F) << 15) | (0x2 << 12) | ((rd & 0x1F) << 7) | 0x03

def SW(rs2, rs1, imm):
    imm12 = imm & 0xFFF
    imm11_5 = (imm12 >> 5) & 0x7F
    imm4_0 = imm12 & 0x1F
    return (imm11_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | (0x2 << 12) | (imm4_0 << 7) | 0x23

# CSR instructions
def CSRRW(rd, csr, rs1):
    return ((csr & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | (0x1 << 12) | ((rd & 0x1F) << 7) | 0x73

def CSRRS(rd, csr, rs1):
    return ((csr & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | (0x2 << 12) | ((rd & 0x1F) << 7) | 0x73

def CSRRC(rd, csr, rs1):
    return ((csr & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | (0x3 << 12) | ((rd & 0x1F) << 7) | 0x73

def CSRRWI(rd, csr, uimm):
    return ((csr & 0xFFF) << 20) | ((uimm & 0x1F) << 15) | (0x5 << 12) | ((rd & 0x1F) << 7) | 0x73

def CSRRSI(rd, csr, uimm):
    return ((csr & 0xFFF) << 20) | ((uimm & 0x1F) << 15) | (0x6 << 12) | ((rd & 0x1F) << 7) | 0x73

def CSRRCI(rd, csr, uimm):
    return ((csr & 0xFFF) << 20) | ((uimm & 0x1F) << 15) | (0x7 << 12) | ((rd & 0x1F) << 7) | 0x73

def MRET():
    return 0x30200073

# M-Extension
def MUL(rd, rs1, rs2):
    return (0x01 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | (0x0 << 12) | ((rd & 0x1F) << 7) | 0x33

def DIV(rd, rs1, rs2):
    return (0x01 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | (0x4 << 12) | ((rd & 0x1F) << 7) | 0x33

# Pseudo instructions
def LI(rd, imm32):
    """Generates LUI + ADDI sequence for 32-bit constant."""
    imm32 = imm32 & 0xFFFFFFFF
    hi20 = (imm32 + 0x800) >> 12
    lo12 = imm32 - (hi20 << 12)
    lo12 = lo12 & 0xFFF
    return [
        LUI(rd, hi20 & 0xFFFFF),
        ADDI(rd, rd, lo12)
    ]

# CSR Constants
CSR_MSTATUS  = 0x300
CSR_MIE      = 0x304
CSR_MTVEC    = 0x305
CSR_MEPC     = 0x341
CSR_MCAUSE   = 0x342
CSR_MIP      = 0x344
CSR_MINTPRIO = 0x7C0

# Register aliases
zero = 0; ra = 1; sp = 2; gp = 3; tp = 4
t0 = 5;   t1 = 6; t2 = 7; s0 = 8; s1 = 9
a0 = 10;  a1 = 11; a2 = 12; a3 = 13; a4 = 14; a5 = 15; a6 = 16; a7 = 17
s2 = 18;  s3 = 19; s4 = 20; s5 = 21; s6 = 22; s7 = 23; s8 = 24; s9 = 25; s10 = 26; s11 = 27
t3 = 28;  t4 = 29; t5 = 30; t6 = 31

# Sentinel constants
SENTINEL_PASS = 0xCAFEBABE
DMEM_BASE     = 0x80001000

# ==============================================================================
# Memory Array Writers
# ==============================================================================
def write_hex_file(filename, data_dict, total_words=1024, default_val=NOP()):
    words = [default_val] * total_words
    for idx, val in data_dict.items():
        if idx < total_words:
            words[idx] = val & 0xFFFFFFFF
            
    with open(filename, 'w') as f:
        for w in words:
            f.write(f"{w:08x}\n")
    print(f"[HEX] Generated {filename} ({len(words)} words)")


# ==============================================================================
# Test 1: Basic Timer Interrupt (MTIP)
# ==============================================================================
def build_test1():
    imem = {}
    dmem = {0: 0x00000000}
    
    # 0x8000_0000: Setup mtvec -> 0x8000_0100
    instrs = []
    instrs.extend(LI(t0, 0x80000100))
    instrs.append(CSRRW(zero, CSR_MTVEC, t0))     # mtvec = 0x8000_0100
    instrs.extend(LI(t0, 0x00000080))             # MTIE
    instrs.append(CSRRW(zero, CSR_MIE, t0))
    instrs.append(CSRRSI(zero, CSR_MSTATUS, 0x8)) # mstatus.MIE = 1
    instrs.extend(LI(t0, DMEM_BASE))              # t0 = DMEM base (0x8000_1000)
    instrs.append(ADDI(s0, zero, 0x100))          # s0 marker
    
    for i, inst in enumerate(instrs):
        imem[i] = inst
        
    loop_start_word = 16 # 0x8000_0040
    imem[len(instrs)] = JAL(zero, (loop_start_word - len(instrs)) * 4)
    
    # Target execution block padded with NOPs
    imem[loop_start_word + 0] = ADDI(s0, s0, 1)          # 0x8000_0040: Target instruction for IRQ
    imem[loop_start_word + 1] = NOP()                    # 0x8000_0044
    imem[loop_start_word + 2] = NOP()                    # 0x8000_0048
    imem[loop_start_word + 3] = SW(s0, t0, 4)            # 0x8000_004C: Store result to DMEM[1]
    
    # Write sentinel indicating background thread reached completion
    imem[loop_start_word + 4] = LUI(gp, 0xCAFEB)
    imem[loop_start_word + 5] = ADDI(gp, gp, -0x542)     # gp = 0xCAFEBABE
    imem[loop_start_word + 6] = SW(gp, t0, 0)            # Store sentinel to DMEM[0]
    imem[loop_start_word + 7] = JAL(zero, 0)             # Park
    
    # ISR Handler at 0x8000_0100 (word 64)
    isr_word = 64
    imem[isr_word + 0] = CSRRS(s1, CSR_MCAUSE, zero)      # s1 = mcause
    imem[isr_word + 1] = CSRRS(s2, CSR_MEPC, zero)        # s2 = mepc
    imem[isr_word + 2] = SW(s1, t0, 8)                    # Store mcause to DMEM[2]
    imem[isr_word + 3] = SW(s2, t0, 12)                   # Store mepc to DMEM[3]
    imem[isr_word + 4] = CSRRCI(zero, CSR_MIE, 0x80)      # Clear MTIE
    imem[isr_word + 5] = MRET()                           # Return to background!
    
    return imem, dmem


# ==============================================================================
# Test 2: All 7 Interrupt Sources Sequentially
# ==============================================================================
def build_test2():
    imem = {}
    dmem = {0: 0x00000000}
    
    instrs = []
    instrs.extend(LI(t0, 0x80000100))
    instrs.append(CSRRW(zero, CSR_MTVEC, t0))
    instrs.extend(LI(t0, 0x000F0888))                    # Enable all 7 IRQ lines in mie
    instrs.append(CSRRW(zero, CSR_MIE, t0))
    instrs.append(CSRRSI(zero, CSR_MSTATUS, 0x8))         # Enable global MIE
    instrs.extend(LI(t0, DMEM_BASE))
    instrs.append(ADDI(s0, zero, 0))
    instrs.append(ADDI(s3, zero, 0))                     # Interrupt hit counter
    instrs.append(ADDI(a0, zero, 7))                     # Expected total interrupts = 7
    
    for i, inst in enumerate(instrs):
        imem[i] = inst
        
    loop_start_word = 16 # 0x8000_0040
    imem[len(instrs)] = JAL(zero, (loop_start_word - len(instrs)) * 4)
    
    # Background spin loop
    imem[loop_start_word + 0] = ADDI(s0, s0, 1)          # 0x8000_0040
    imem[loop_start_word + 1] = NOP()
    imem[loop_start_word + 2] = BEQ(s3, a0, 12)          # If s3 == 7, branch to finish (offset +12)
    imem[loop_start_word + 3] = JAL(zero, -12)           # Loop back to 0x8000_0040
    
    # Finish block: write sentinel to DMEM[0]
    imem[loop_start_word + 4] = LUI(gp, 0xCAFEB)
    imem[loop_start_word + 5] = ADDI(gp, gp, -0x542)     # gp = 0xCAFEBABE
    imem[loop_start_word + 6] = SW(gp, t0, 0)            # Store sentinel to DMEM[0]
    imem[loop_start_word + 7] = JAL(zero, 0)
    
    # ISR at word 64 (0x8000_0100)
    isr_word = 64
    imem[isr_word + 0] = CSRRS(s1, CSR_MCAUSE, zero)      # Read mcause
    imem[isr_word + 1] = SLLI(t1, s3, 2)                  # t1 = s3 * 4
    imem[isr_word + 2] = ADD(t2, t0, t1)                  # t2 = DMEM_BASE + s3*4
    imem[isr_word + 3] = SW(s1, t2, 16)                   # Store mcause to DMEM table starting at offset 16
    imem[isr_word + 4] = ADDI(s3, s3, 1)                  # Increment hit count
    imem[isr_word + 5] = MRET()
    
    return imem, dmem


# ==============================================================================
# Test 3: Priority Resolution (Simultaneous multi-line assertion)
# ==============================================================================
def build_test3():
    imem = {}
    dmem = {0: 0x00000000}
    
    instrs = []
    instrs.extend(LI(t0, 0x80000100))
    instrs.append(CSRRW(zero, CSR_MTVEC, t0))
    instrs.extend(LI(t0, 0x000F0888))
    instrs.append(CSRRW(zero, CSR_MIE, t0))
    instrs.append(CSRRSI(zero, CSR_MSTATUS, 0x8))
    instrs.extend(LI(t0, DMEM_BASE))
    instrs.append(ADDI(s3, zero, 0))                     # Serviced counter
    instrs.append(ADDI(a0, zero, 7))                     # Expected count = 7
    
    for i, inst in enumerate(instrs):
        imem[i] = inst
        
    loop_start_word = 16
    imem[len(instrs)] = JAL(zero, (loop_start_word - len(instrs)) * 4)
    
    imem[loop_start_word + 0] = ADDI(s0, s0, 1)
    imem[loop_start_word + 1] = NOP()
    imem[loop_start_word + 2] = BEQ(s3, a0, 12)
    imem[loop_start_word + 3] = JAL(zero, -12)
    
    imem[loop_start_word + 4] = LUI(gp, 0xCAFEB)
    imem[loop_start_word + 5] = ADDI(gp, gp, -0x542)
    imem[loop_start_word + 6] = SW(gp, t0, 0)
    imem[loop_start_word + 7] = JAL(zero, 0)
    
    # ISR at word 64: logs priority resolution sequence
    isr_word = 64
    imem[isr_word + 0] = CSRRS(s1, CSR_MCAUSE, zero)
    imem[isr_word + 1] = SLLI(t1, s3, 2)
    imem[isr_word + 2] = ADD(t2, t0, t1)
    imem[isr_word + 3] = SW(s1, t2, 16)                   # Log each resolved mcause in order
    imem[isr_word + 4] = ADDI(s3, s3, 1)
    imem[isr_word + 5] = MRET()
    
    return imem, dmem


# ==============================================================================
# Test 4: mintprio Priority Threshold Gate (CSR 0x7C0)
# ==============================================================================
def build_test4():
    imem = {}
    dmem = {0: 0x00000000}
    
    instrs = []
    instrs.extend(LI(t0, 0x80000100))
    instrs.append(CSRRW(zero, CSR_MTVEC, t0))
    instrs.extend(LI(t0, 0x000F0888))
    instrs.append(CSRRW(zero, CSR_MIE, t0))
    
    # Set mintprio threshold = 16 (GPIO level)
    instrs.extend(LI(t0, 16))
    instrs.append(CSRRW(zero, CSR_MINTPRIO, t0))
    instrs.append(CSRRSI(zero, CSR_MSTATUS, 0x8))
    instrs.extend(LI(t0, DMEM_BASE))
    instrs.append(ADDI(s3, zero, 0))
    
    for i, inst in enumerate(instrs):
        imem[i] = inst
        
    loop_start_word = 16
    imem[len(instrs)] = JAL(zero, (loop_start_word - len(instrs)) * 4)
    
    imem[loop_start_word + 0] = ADDI(s0, s0, 1)
    imem[loop_start_word + 1] = NOP()
    imem[loop_start_word + 2] = BNE(s3, zero, 12)        # Once accepted IRQ hits, s3 != 0 -> branch finish
    imem[loop_start_word + 3] = JAL(zero, -12)
    
    imem[loop_start_word + 4] = LUI(gp, 0xCAFEB)
    imem[loop_start_word + 5] = ADDI(gp, gp, -0x542)
    imem[loop_start_word + 6] = SW(gp, t0, 0)            # Store sentinel to DMEM[0]
    imem[loop_start_word + 7] = JAL(zero, 0)
    
    # ISR at word 64: must only be reached by above-threshold IRQ (UART 19)
    isr_word = 64
    imem[isr_word + 0] = CSRRS(s1, CSR_MCAUSE, zero)
    imem[isr_word + 1] = SW(s1, t0, 4)                    # Store mcause to DMEM[1]
    imem[isr_word + 2] = ADDI(s3, s3, 1)
    imem[isr_word + 3] = MRET()
    
    return imem, dmem


# ==============================================================================
# Test 5: Multi-cycle DIV Stall Collision (stallMUL Hazard)
# ==============================================================================
def build_test5():
    imem = {}
    dmem = {0: 0x00000000}
    
    instrs = []
    instrs.extend(LI(t0, 0x80000100))
    instrs.append(CSRRW(zero, CSR_MTVEC, t0))
    instrs.extend(LI(t0, 0x00000080))                    # MTIE
    instrs.append(CSRRW(zero, CSR_MIE, t0))
    instrs.append(CSRRSI(zero, CSR_MSTATUS, 0x8))
    instrs.extend(LI(t0, DMEM_BASE))
    
    # Load division operands: 100000 / 3 = 33333
    instrs.extend(LI(t1, 100000))
    instrs.extend(LI(t2, 3))
    
    for i, inst in enumerate(instrs):
        imem[i] = inst
        
    div_start_word = 16
    imem[len(instrs)] = JAL(zero, (div_start_word - len(instrs)) * 4)
    
    # Word 16: Multi-cycle DIV instruction
    imem[div_start_word + 0] = DIV(s4, t1, t2)            # Takes ~34 cycles in EX
    imem[div_start_word + 1] = SW(s4, t0, 4)              # Store division result (33333) to DMEM[1]
    imem[div_start_word + 2] = NOP()
    imem[div_start_word + 3] = NOP()
    imem[div_start_word + 4] = LUI(gp, 0xCAFEB)
    imem[div_start_word + 5] = ADDI(gp, gp, -0x542)
    imem[div_start_word + 6] = SW(gp, t0, 0)              # Store sentinel to DMEM[0]
    imem[div_start_word + 7] = JAL(zero, 0)
    
    # ISR at word 64
    isr_word = 64
    imem[isr_word + 0] = CSRRS(s1, CSR_MCAUSE, zero)
    imem[isr_word + 1] = CSRRS(s2, CSR_MEPC, zero)
    imem[isr_word + 2] = SW(s1, t0, 8)                    # Store mcause to DMEM[2]
    imem[isr_word + 3] = SW(s2, t0, 12)                   # Store mepc to DMEM[3]
    imem[isr_word + 4] = CSRRCI(zero, CSR_MIE, 0x80)      # Disable MTIE
    imem[isr_word + 5] = MRET()
    
    return imem, dmem


# ==============================================================================
# Test 6: Interrupt vs Synchronous Exception Collision (Branch Misaligned)
# ==============================================================================
def build_test6():
    imem = {}
    dmem = {0: 0x00000000}
    
    instrs = []
    instrs.extend(LI(t0, 0x80000100))
    instrs.append(CSRRW(zero, CSR_MTVEC, t0))
    instrs.extend(LI(t0, 0x00000080))                    # MTIE
    instrs.append(CSRRW(zero, CSR_MIE, t0))
    instrs.append(CSRRSI(zero, CSR_MSTATUS, 0x8))
    instrs.extend(LI(t0, DMEM_BASE))
    
    for i, inst in enumerate(instrs):
        imem[i] = inst
        
    exc_start_word = 16
    imem[len(instrs)] = JAL(zero, (exc_start_word - len(instrs)) * 4)
    
    # 2 Continuous branch misalign instructions at EX and ID:
    # 0x8000_0040: JAL to misaligned target (+2 bytes -> 0x8000_0042)
    # 0x8000_0044: Second JAL to misaligned target (+2 bytes -> 0x8000_0046)
    imem[exc_start_word + 0] = JAL(ra, 2)                 # Instruction 1 (misaligned branch)
    imem[exc_start_word + 1] = JAL(ra, 2)                 # Instruction 2 (continuous misaligned in pipeline)
    imem[exc_start_word + 2] = NOP()
    imem[exc_start_word + 3] = NOP()
    
    # Trap handler at word 64 (0x8000_0100)
    isr_word = 64
    imem[isr_word + 0] = CSRRS(s1, CSR_MCAUSE, zero)      # Must be 0x0000_0000 (Exception)
    imem[isr_word + 1] = CSRRS(s2, CSR_MEPC, zero)        # mepc = 0x8000_0040
    imem[isr_word + 2] = SW(s1, t0, 4)                    # Store mcause to DMEM[1]
    imem[isr_word + 3] = SW(s2, t0, 8)                    # Store mepc to DMEM[2]
    imem[isr_word + 4] = LUI(gp, 0xCAFEB)
    imem[isr_word + 5] = ADDI(gp, gp, -0x542)
    imem[isr_word + 6] = SW(gp, t0, 0)                    # Store sentinel to DMEM[0]
    imem[isr_word + 7] = JAL(zero, 0)                     # Park
    
    return imem, dmem


# ==============================================================================
# Test 7: Full MRET Roundtrip & State Preservation (DMEM preloaded operands)
# ==============================================================================
def build_test7():
    imem = {}
    # Preload unique operand values into DMEM
    dmem = {
        0: 0x00000000,
        1: 0x11111111,  # DMEM[1]
        2: 0x22222222,  # DMEM[2]
        3: 0x33333333,  # DMEM[3]
        4: 0x44444444   # DMEM[4]
    }
    
    instrs = []
    instrs.extend(LI(t0, 0x80000100))
    instrs.append(CSRRW(zero, CSR_MTVEC, t0))
    instrs.extend(LI(t0, 0x00000080))                    # MTIE
    instrs.append(CSRRW(zero, CSR_MIE, t0))
    instrs.append(CSRRSI(zero, CSR_MSTATUS, 0x8))
    instrs.extend(LI(t0, DMEM_BASE))
    
    # Load operands from preloaded DMEM locations
    instrs.append(LW(s0, t0, 4))                         # s0 = 0x11111111
    instrs.append(LW(s1, t0, 8))                         # s1 = 0x22222222
    instrs.append(LW(s2, t0, 12))                        # s2 = 0x33333333
    instrs.append(LW(s4, t0, 16))                        # s4 = 0x44444444
    
    for i, inst in enumerate(instrs):
        imem[i] = inst
        
    loop_start_word = 20 # 0x8000_0050
    imem[len(instrs)] = JAL(zero, (loop_start_word - len(instrs)) * 4)
    
    # Arithmetic pipeline
    imem[loop_start_word + 0] = ADDI(s0, s0, 1)          # Target IRQ injection (s0 = 0x11111112)
    imem[loop_start_word + 1] = ADDI(s1, s1, 2)          # s1 = 0x22222224
    imem[loop_start_word + 2] = ADDI(s2, s2, 3)          # s2 = 0x33333336
    imem[loop_start_word + 3] = ADDI(s4, s4, 4)          # s4 = 0x44444448
    
    # Compute checksum: (0x11111112 + 0x22222224 + 0x33333336 + 0x44444448) = 0xAAAAAAB4
    imem[loop_start_word + 4] = ADD(gp, s0, s1)
    imem[loop_start_word + 5] = ADD(gp, gp, s2)
    imem[loop_start_word + 6] = ADD(gp, gp, s4)          # gp = 0xAAAAAAB4
    imem[loop_start_word + 7] = SW(gp, t0, 0)            # Store checksum to DMEM[0]
    imem[loop_start_word + 8] = JAL(zero, 0)             # Park
    
    # ISR at word 64
    isr_word = 64
    imem[isr_word + 0] = CSRRS(t1, CSR_MCAUSE, zero)
    imem[isr_word + 1] = CSRRS(t2, CSR_MEPC, zero)
    imem[isr_word + 2] = ADDI(t3, zero, 1)
    imem[isr_word + 3] = CSRRCI(zero, CSR_MIE, 0x80)      # Disable MTIE
    imem[isr_word + 4] = MRET()                           # Resume execution!
    
    return imem, dmem


# ==============================================================================
# Main Generator Entry Point
# ==============================================================================
def main():
    out_dir = os.path.dirname(os.path.abspath(__file__))
    
    tests = {
        "tb1_test1_timer":       build_test1(),
        "tb1_test2_all_sources": build_test2(),
        "tb1_test3_priority":    build_test3(),
        "tb1_test4_mintprio":    build_test4(),
        "tb1_test5_hazard":      build_test5(),
        "tb1_test6_collision":   build_test6(),
        "tb1_test7_mret":        build_test7()
    }
    
    for prefix, (imem_map, dmem_map) in tests.items():
        imem_file = os.path.join(out_dir, f"{prefix}_imem.hex")
        dmem_file = os.path.join(out_dir, f"{prefix}_dmem.hex")
        write_hex_file(imem_file, imem_map, default_val=NOP())
        write_hex_file(dmem_file, dmem_map, default_val=0x00000000)

    # Also generate default imem.hex and dmem.hex
    write_hex_file(os.path.join(out_dir, "imem.hex"), {}, default_val=NOP())
    write_hex_file(os.path.join(out_dir, "dmem.hex"), {}, default_val=0x00000000)
        
    print("\n[SUCCESS] All paired IMEM and DMEM hex files generated successfully.")

if __name__ == "__main__":
    main()
