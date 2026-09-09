#!/usr/bin/env python3
"""
elf_to_hex.py — Standalone RISC-V ELF to Word-Addressed Hex Converter
Splits binary sections into ISRAM (0x0001_0000) and DSRAM (0x0002_0000) hex images.
"""

import sys
import struct

def parse_elf(elf_filename):
    with open(elf_filename, 'rb') as f:
        data = f.read()

    # ELF Header Validation
    if data[0:4] != b'\x7fELF':
        raise ValueError(f"{elf_filename} is not a valid ELF file")

    e_type, e_machine, e_version, e_entry, e_phoff, e_shoff, e_flags, e_ehsize, \
    e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx = struct.unpack('<HHIIIIIHHHHHH', data[16:52])

    # Section Headers
    sections = []
    shstrtab_offset = e_shoff + e_shstrndx * e_shentsize
    shstr_sh_offset, shstr_sh_size = struct.unpack('<II', data[shstrtab_offset+16:shstrtab_offset+24])
    shstrtab = data[shstr_sh_offset:shstr_sh_offset+shstr_sh_size]

    for i in range(e_shnum):
        sh_offset = e_shoff + i * e_shentsize
        sh_name_idx, sh_type, sh_flags, sh_addr, sh_offset_bytes, sh_size, \
        sh_link, sh_info, sh_addralign, sh_entsize = struct.unpack('<IIIIIIIIII', data[sh_offset:sh_offset+40])

        null_pos = shstrtab.find(b'\x00', sh_name_idx)
        name = shstrtab[sh_name_idx:null_pos].decode('ascii', errors='ignore')

        if sh_type in (1, 8) and (sh_flags & 2): # SHT_PROGBITS / SHT_NOBITS & SHF_ALLOC
            sec_data = data[sh_offset_bytes:sh_offset_bytes+sh_size] if sh_type == 1 else b'\x00' * sh_size
            sections.append({
                'name': name,
                'addr': sh_addr,
                'size': sh_size,
                'data': sec_data
            })
    return sections

def generate_hex(sections, imem_hex_path, dmem_hex_path):
    # ISRAM: Base 0x0001_0000, 32 KB (8192 words)
    # DSRAM: Base 0x0002_0000, 32 KB (8192 words)
    isram = {}
    dsram = {}

    for sec in sections:
        addr = sec['addr']
        sec_data = sec['data']
        for i in range(0, len(sec_data), 4):
            chunk = sec_data[i:i+4]
            if len(chunk) < 4:
                chunk = chunk + b'\x00' * (4 - len(chunk))
            word = struct.unpack('<I', chunk)[0]
            cur_addr = addr + i

            if 0x00010000 <= cur_addr < 0x00018000:
                word_idx = (cur_addr - 0x00010000) >> 2
                isram[word_idx] = word
            elif 0x00020000 <= cur_addr < 0x00028000:
                word_idx = (cur_addr - 0x00020000) >> 2
                dsram[word_idx] = word

    # Write ISRAM Hex
    with open(imem_hex_path, 'w') as f:
        for idx in sorted(isram.keys()):
            f.write(f"@{idx:08x}\n{isram[idx]:08x}\n")

    # Write DSRAM Hex
    with open(dmem_hex_path, 'w') as f:
        for idx in sorted(dsram.keys()):
            f.write(f"@{idx:08x}\n{dsram[idx]:08x}\n")

    print(f"[elf_to_hex] Output generated:")
    print(f"  ISRAM Hex: {imem_hex_path} ({len(isram)} words)")
    print(f"  DSRAM Hex: {dmem_hex_path} ({len(dsram)} words)")

if __name__ == '__main__':
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <input.elf> <imem.hex> <dmem.hex>")
        sys.exit(1)
    secs = parse_elf(sys.argv[1])
    generate_hex(secs, sys.argv[2], sys.argv[3])

