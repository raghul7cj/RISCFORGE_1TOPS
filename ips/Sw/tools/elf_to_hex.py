#!/usr/bin/env python3
"""
=============================================================================
RISCFORGE 1TOPS — Standalone ELF to Hex Converter (Zero Dependencies)
=============================================================================
Parses standard 32-bit ELF binaries directly without requiring pyelftools.
Extracts PT_LOAD segments and formats them into word-addressed Verilog $readmemh hex.
=============================================================================
"""

import sys
import struct
import os

ISRAM_BASE = 0x00010000
DSRAM_BASE = 0x00020000

def parse_elf32(elf_path):
    with open(elf_path, 'rb') as f:
        data = f.read()

    # Verify ELF Magic
    if data[:4] != b'\x7fELF':
        raise ValueError("Not a valid ELF file")

    ei_class = data[4]
    is_64 = (ei_class != 1)

    imem_dict = {}
    dmem_dict = {}

    if not is_64:
        e_phoff = struct.unpack_from('<I', data, 0x1C)[0]
        e_phentsize = struct.unpack_from('<H', data, 0x2A)[0]
        e_phnum = struct.unpack_from('<H', data, 0x2C)[0]

        for i in range(e_phnum):
            ph_offset = e_phoff + (i * e_phentsize)
            p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = struct.unpack_from('<IIIIIIII', data, ph_offset)

            if p_type == 1 and p_filesz > 0:  # PT_LOAD = 1
                seg_data = data[p_offset : p_offset + p_filesz]
                pad = (4 - (len(seg_data) % 4)) % 4
                seg_data += b'\x00' * pad

                for byte_idx in range(0, len(seg_data), 4):
                    addr = p_paddr + byte_idx
                    word = struct.unpack_from('<I', seg_data, byte_idx)[0]

                    if ISRAM_BASE <= addr < DSRAM_BASE:
                        word_idx = (addr - ISRAM_BASE) >> 2
                        imem_dict[word_idx] = word
                    elif addr >= DSRAM_BASE:
                        word_idx = (addr - DSRAM_BASE) >> 2
                        dmem_dict[word_idx] = word
                    else:
                        word_idx = addr >> 2
                        imem_dict[word_idx] = word
    else:
        e_phoff = struct.unpack_from('<Q', data, 0x20)[0]
        e_phentsize = struct.unpack_from('<H', data, 0x36)[0]
        e_phnum = struct.unpack_from('<H', data, 0x38)[0]

        for i in range(e_phnum):
            ph_offset = e_phoff + (i * e_phentsize)
            p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = struct.unpack_from('<IIQQQQQQ', data, ph_offset)

            if p_type == 1 and p_filesz > 0:
                seg_data = data[p_offset : p_offset + p_filesz]
                pad = (4 - (len(seg_data) % 4)) % 4
                seg_data += b'\x00' * pad

                for byte_idx in range(0, len(seg_data), 4):
                    addr = p_paddr + byte_idx
                    word = struct.unpack_from('<I', seg_data, byte_idx)[0]

                    if ISRAM_BASE <= addr < DSRAM_BASE:
                        word_idx = (addr - ISRAM_BASE) >> 2
                        imem_dict[word_idx] = word
                    elif addr >= DSRAM_BASE:
                        word_idx = (addr - DSRAM_BASE) >> 2
                        dmem_dict[word_idx] = word
                    else:
                        word_idx = addr >> 2
                        imem_dict[word_idx] = word

    return imem_dict, dmem_dict


def write_hex(file_path, mem_dict):
    with open(file_path, 'w') as f:
        if not mem_dict:
            f.write("00000000\n")
            return
        for idx in sorted(mem_dict.keys()):
            f.write(f"@{idx:08x}\n{mem_dict[idx]:08x}\n")


def main():
    if len(sys.argv) < 4:
        print("Usage: python3 elf_to_hex.py <input.elf> <imem_out.hex> <dmem_out.hex>")
        sys.exit(1)

    elf_file = sys.argv[1]
    imem_file = sys.argv[2]
    dmem_file = sys.argv[3]

    if not os.path.exists(elf_file):
        print(f"Error: {elf_file} not found")
        sys.exit(1)

    imem_dict, dmem_dict = parse_elf32(elf_file)

    write_hex(imem_file, imem_dict)
    write_hex(dmem_file, dmem_dict)

    print(f"[elf_to_hex] Output generated:")
    print(f"  ISRAM Hex: {imem_file} ({len(imem_dict)} words)")
    print(f"  DSRAM Hex: {dmem_file} ({len(dmem_dict)} words)")


if __name__ == '__main__':
    main()
