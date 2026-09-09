#!/usr/bin/env python3
"""
compile_asm.py — Standard RISC-V Assembler & Hex Generator for RISCFORGE Interrupt Suite
Parses standard RISC-V assembly (.S) files and generates 100% architecturally ratified
IMEM (0x8000_0000) and DMEM (0x8000_1000) hex images.
"""

import os
import re
import sys

# Standard Register Mapping
REG_MAP = {
    'zero': 0, 'x0': 0,
    'ra': 1,   'x1': 1,
    'sp': 2,   'x2': 2,
    'gp': 3,   'x3': 3,
    'tp': 4,   'x4': 4,
    't0': 5,   'x5': 5,
    't1': 6,   'x6': 6,
    't2': 7,   'x7': 7,
    's0': 8,   'x8': 8,  'fp': 8,
    's1': 9,   'x9': 9,
    'a0': 10,  'x10': 10,
    'a1': 11,  'x11': 11,
    'a2': 12,  'x12': 12,
    'a3': 13,  'x13': 13,
    'a4': 14,  'x14': 14,
    'a5': 15,  'x15': 15,
    'a6': 16,  'x16': 16,
    'a7': 17,  'x17': 17,
    's2': 18,  'x18': 18,
    's3': 19,  'x19': 19,
    's4': 20,  'x20': 20,
    's5': 21,  'x21': 21,
    's6': 22,  'x22': 22,
    's7': 23,  'x23': 23,
    's8': 24,  'x24': 24,
    's9': 25,  'x25': 25,
    's10': 26, 'x26': 26,
    's11': 27, 'x27': 27,
    't3': 28,  'x28': 28,
    't4': 29,  'x29': 29,
    't5': 30,  'x30': 30,
    't6': 31,  'x31': 31,
}

CSR_MAP = {
    'mstatus':  0x300,
    'mie':      0x304,
    'mtvec':    0x305,
    'mscratch': 0x340,
    'mepc':     0x341,
    'mcause':   0x342,
    'mtval':    0x343,
    'mip':      0x344,
    'mintprio': 0x7C0,
}

def parse_reg(s):
    s = s.strip().lower()
    if s in REG_MAP:
        return REG_MAP[s]
    raise ValueError(f"Unknown register: {s}")

def parse_csr(s):
    s = s.strip().lower()
    if s in CSR_MAP:
        return CSR_MAP[s]
    if s.startswith("0x") or s.startswith("0X") or s.isdigit():
        return int(s, 0)
    raise ValueError(f"Unknown CSR: {s}")

def parse_imm(s):
    s = s.strip()
    return int(s, 0)

# ==============================================================================
# 100% Ratified RISC-V RV32IM_Zicsr Encoders
# ==============================================================================
def enc_r(funct7, rs2, rs1, funct3, rd, opcode=0x33):
    return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def enc_i(imm12, rs1, funct3, rd, opcode):
    return ((imm12 & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def enc_s(imm12, rs2, rs1, funct3, opcode=0x23):
    imm12 = imm12 & 0xFFF
    imm11_5 = (imm12 >> 5) & 0x7F
    imm4_0 = imm12 & 0x1F
    return (imm11_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | (imm4_0 << 7) | (opcode & 0x7F)

def enc_b(offset, rs2, rs1, funct3, opcode=0x63):
    imm = offset & 0x1FFF
    imm12 = (imm >> 12) & 0x1
    imm10_5 = (imm >> 5) & 0x3F
    imm4_1 = (imm >> 1) & 0xF
    imm11 = (imm >> 11) & 0x1
    instr_31_25 = (imm12 << 6) | imm10_5
    instr_11_7 = (imm4_1 << 1) | imm11
    return (instr_31_25 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | (instr_11_7 << 7) | (opcode & 0x7F)

def enc_u(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def enc_j(offset, rd, opcode=0x6F):
    imm = offset & 0x1FFFFF
    imm20 = (imm >> 20) & 0x1
    imm10_1 = (imm >> 1) & 0x3FF
    imm11 = (imm >> 11) & 0x1
    imm19_12 = (imm >> 12) & 0xFF
    instr_31_12 = (imm20 << 19) | (imm10_1 << 9) | (imm11 << 8) | imm19_12
    return (instr_31_12 << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)


# ==============================================================================
# Two-Pass Assembly Compiler
# ==============================================================================
class RISCVAssembler:
    def __init__(self, base_addr=0x80000000):
        self.base_addr = base_addr

    def assemble_file(self, asm_path):
        with open(asm_path, 'r') as f:
            lines = f.readlines()

        # Pass 1: Expand pseudoinstructions & collect label addresses
        current_addr = self.base_addr
        labels = {}
        parsed_items = [] # list of (addr, type, tokens)

        for line_num, line in enumerate(lines, 1):
            line = line.split('#')[0].strip()
            if not line:
                continue

            # Check for label
            if ':' in line:
                parts = line.split(':', 1)
                lbl = parts[0].strip()
                labels[lbl] = current_addr
                line = parts[1].strip()
                if not line:
                    continue

            # Check for directives
            if line.startswith('.'):
                tokens = line.split()
                directive = tokens[0]
                if directive == '.org':
                    offset = parse_imm(tokens[1])
                    current_addr = self.base_addr + offset
                continue

            # Tokenize instruction
            parts = re.split(r'[\s,()]+', line)
            tokens = [p for p in parts if p]
            if not tokens:
                continue

            mnemonic = tokens[0].lower()
            args = tokens[1:]

            # Pseudoinstruction expansions
            if mnemonic == 'nop':
                parsed_items.append((current_addr, 'instr', ['addi', 'zero', 'zero', '0']))
                current_addr += 4
            elif mnemonic == 'li':
                rd = args[0]
                val = parse_imm(args[1]) & 0xFFFFFFFF
                hi20 = (val + 0x800) >> 12
                lo12 = (val - (hi20 << 12)) & 0xFFF
                # Sign extend lo12 for addi representation
                if lo12 >= 0x800:
                    lo12_val = lo12 - 0x1000
                else:
                    lo12_val = lo12
                parsed_items.append((current_addr, 'instr', ['lui', rd, str(hi20)]))
                current_addr += 4
                parsed_items.append((current_addr, 'instr', ['addi', rd, rd, str(lo12_val)]))
                current_addr += 4
            elif mnemonic == 'la':
                rd = args[0]
                target_lbl = args[1]
                parsed_items.append((current_addr, 'la', [rd, target_lbl]))
                current_addr += 8 # lui + addi
            elif mnemonic == 'j':
                target = args[0]
                parsed_items.append((current_addr, 'instr', ['jal', 'zero', target]))
                current_addr += 4
            elif mnemonic == 'bnez':
                rs = args[0]
                target = args[1]
                parsed_items.append((current_addr, 'instr', ['bne', rs, 'zero', target]))
                current_addr += 4
            elif mnemonic == 'beqz':
                rs = args[0]
                target = args[1]
                parsed_items.append((current_addr, 'instr', ['beq', rs, 'zero', target]))
                current_addr += 4
            elif mnemonic == 'csrr':
                rd = args[0]
                csr = args[1]
                parsed_items.append((current_addr, 'instr', ['csrrs', rd, csr, 'zero']))
                current_addr += 4
            elif mnemonic == 'csrw':
                csr = args[0]
                rs1 = args[1]
                parsed_items.append((current_addr, 'instr', ['csrrw', 'zero', csr, rs1]))
                current_addr += 4
            elif mnemonic == 'csrc':
                csr = args[0]
                rs1 = args[1]
                parsed_items.append((current_addr, 'instr', ['csrrc', 'zero', csr, rs1]))
                current_addr += 4
            elif mnemonic == 'csrs':
                csr = args[0]
                rs1 = args[1]
                parsed_items.append((current_addr, 'instr', ['csrrs', 'zero', csr, rs1]))
                current_addr += 4
            else:
                parsed_items.append((current_addr, 'instr', tokens))
                current_addr += 4

        # Pass 2: Assemble to machine words
        mem_words = {}

        for addr, item_type, tokens in parsed_items:
            if item_type == 'la':
                rd = parse_reg(tokens[0])
                target_lbl = tokens[1]
                if target_lbl not in labels:
                    raise ValueError(f"Undefined label: {target_lbl}")
                target_addr = labels[target_lbl]
                hi20 = (target_addr + 0x800) >> 12
                lo12 = (target_addr - (hi20 << 12)) & 0xFFF
                word_lui = enc_u(hi20, rd, 0x37)
                word_addi = enc_i(lo12, rd, 0x0, rd, 0x13)
                word_idx = (addr - self.base_addr) // 4
                mem_words[word_idx] = word_lui
                mem_words[word_idx + 1] = word_addi
                continue

            mnemonic = tokens[0].lower()
            args = tokens[1:]
            word = 0

            if mnemonic == 'lui':
                rd = parse_reg(args[0])
                imm = parse_imm(args[1])
                word = enc_u(imm, rd, 0x37)
            elif mnemonic == 'addi':
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                imm = parse_imm(args[2])
                word = enc_i(imm, rs1, 0x0, rd, 0x13)
            elif mnemonic == 'slli':
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                shamt = parse_imm(args[2]) & 0x1F
                word = enc_i(shamt, rs1, 0x1, rd, 0x13)
            elif mnemonic == 'andi':
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                imm = parse_imm(args[2])
                word = enc_i(imm, rs1, 0x7, rd, 0x13)
            elif mnemonic == 'add':
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                rs2 = parse_reg(args[2])
                word = enc_r(0x00, rs2, rs1, 0x0, rd, 0x33)
            elif mnemonic == 'sub':
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                rs2 = parse_reg(args[2])
                word = enc_r(0x20, rs2, rs1, 0x0, rd, 0x33)
            elif mnemonic == 'sll':
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                rs2 = parse_reg(args[2])
                word = enc_r(0x00, rs2, rs1, 0x1, rd, 0x33)
            elif mnemonic == 'div':
                rd = parse_reg(args[0])
                rs1 = parse_reg(args[1])
                rs2 = parse_reg(args[2])
                word = enc_r(0x01, rs2, rs1, 0x4, rd, 0x33)
            elif mnemonic == 'lw':
                rd = parse_reg(args[0])
                imm = parse_imm(args[1])
                rs1 = parse_reg(args[2])
                word = enc_i(imm, rs1, 0x2, rd, 0x03)
            elif mnemonic == 'sw':
                rs2 = parse_reg(args[0])
                imm = parse_imm(args[1])
                rs1 = parse_reg(args[2])
                word = enc_s(imm, rs2, rs1, 0x2, 0x23)
            elif mnemonic == 'jal':
                rd = parse_reg(args[0])
                target = args[1]
                if target in labels:
                    offset = labels[target] - addr
                else:
                    offset = parse_imm(target)
                word = enc_j(offset, rd, 0x6F)
            elif mnemonic == 'beq':
                rs1 = parse_reg(args[0])
                rs2 = parse_reg(args[1])
                target = args[2]
                if target in labels:
                    offset = labels[target] - addr
                else:
                    offset = parse_imm(target)
                word = enc_b(offset, rs2, rs1, 0x0, 0x63)
            elif mnemonic == 'bne':
                rs1 = parse_reg(args[0])
                rs2 = parse_reg(args[1])
                target = args[2]
                if target in labels:
                    offset = labels[target] - addr
                else:
                    offset = parse_imm(target)
                word = enc_b(offset, rs2, rs1, 0x1, 0x63)
            elif mnemonic == 'csrrs':
                rd = parse_reg(args[0])
                csr = parse_csr(args[1])
                rs1 = parse_reg(args[2])
                word = enc_i(csr, rs1, 0x2, rd, 0x73)
            elif mnemonic == 'csrrw':
                rd = parse_reg(args[0])
                csr = parse_csr(args[1])
                rs1 = parse_reg(args[2])
                word = enc_i(csr, rs1, 0x1, rd, 0x73)
            elif mnemonic == 'csrrc':
                rd = parse_reg(args[0])
                csr = parse_csr(args[1])
                rs1 = parse_reg(args[2])
                word = enc_i(csr, rs1, 0x3, rd, 0x73)
            elif mnemonic == 'csrsi':
                csr = parse_csr(args[0])
                uimm = parse_imm(args[1])
                word = enc_i(csr, uimm, 0x6, 0, 0x73)
            elif mnemonic == 'csrci':
                csr = parse_csr(args[0])
                uimm = parse_imm(args[1])
                word = enc_i(csr, uimm, 0x7, 0, 0x73)
            elif mnemonic == 'mret':
                word = 0x30200073
            else:
                raise ValueError(f"Unsupported instruction mnemonic: {mnemonic}")

            word_idx = (addr - self.base_addr) // 4
            mem_words[word_idx] = word

        return mem_words


def write_hex(filename, word_dict, total_words=1024, default_val=0x00000013):
    words = [default_val] * total_words
    for idx, val in word_dict.items():
        if idx < total_words:
            words[idx] = val & 0xFFFFFFFF
    with open(filename, 'w') as f:
        for w in words:
            f.write(f"{w:08x}\n")
    print(f"[HEX] Wrote {filename} ({len(words)} words)")


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    asm_dir = os.path.join(script_dir, "asm")
    
    # Preloaded DMEM initializations per test
    dmem_inits = {
        "test1_timer":       {0: 0x00000000},
        "test2_all_sources": {0: 0x00000000},
        "test3_priority":    {0: 0x00000000},
        "test4_mintprio":    {0: 0x00000000},
        "test5_hazard":      {0: 0x00000000},
        "test6_collision":   {0: 0x00000000},
        "test7_mret": {
            0: 0x00000000,
            1: 0x11111111, # DMEM[1]
            2: 0x22222222, # DMEM[2]
            3: 0x33333333, # DMEM[3]
            4: 0x44444444  # DMEM[4]
        }
    }

    assembler = RISCVAssembler(base_addr=0x80000000)

    for test_key, dmem_map in dmem_inits.items():
        asm_file = os.path.join(asm_dir, f"{test_key}.S")
        imem_words = assembler.assemble_file(asm_file)
        
        imem_hex = os.path.join(script_dir, f"tb1_{test_key}_imem.hex")
        dmem_hex = os.path.join(script_dir, f"tb1_{test_key}_dmem.hex")
        
        write_hex(imem_hex, imem_words, default_val=0x00000013) # NOP
        write_hex(dmem_hex, dmem_map, default_val=0x00000000)

    # Also write default imem.hex and dmem.hex
    write_hex(os.path.join(script_dir, "imem.hex"), {}, default_val=0x00000013)
    write_hex(os.path.join(script_dir, "dmem.hex"), {}, default_val=0x00000000)
    
    print("\n[SUCCESS] All 7 assembly test files successfully assembled to ratified RISC-V hex images!")

if __name__ == "__main__":
    main()

