#!/usr/bin/env python3
"""
RISCFORGE 1TOPS — Robust, Bounds-Checked ELF to Hex Memory Converter (elf_to_hex_clean.py)
Splits ELF segments into separate 32-bit word ISRAM and DSRAM .hex images for Verilog $readmemh.
"""

import sys
import os
import struct

ISRAM_BASE = 0x00010000
ISRAM_SIZE = 0x00008000 # 32 KB
DSRAM_BASE = 0x00020000
DSRAM_SIZE = 0x00008000 # 32 KB

def convert_elf_to_hex(elf_path, imem_hex_path, dmem_hex_path):
    if not os.path.exists(elf_path):
        print(f"Error: ELF file not found at '{elf_path}'")
        sys.exit(1)

    with open(elf_path, 'rb') as f:
        data = f.read()

    # ELF Header check
    if data[:4] != b'\x7fELF':
        print("Error: Invalid ELF magic header")
        sys.exit(1)

    # 32-bit Little-Endian
    e_phoff = struct.unpack_from('<I', data, 28)[0]
    e_phentsize = struct.unpack_from('<H', data, 42)[0]
    e_phnum = struct.unpack_from('<H', data, 44)[0]

    imem_words = {}
    dmem_words = {}

    for i in range(e_phnum):
        ph_offset = e_phoff + i * e_phentsize
        p_type = struct.unpack_from('<I', data, ph_offset)[0]
        p_offset = struct.unpack_from('<I', data, ph_offset + 4)[0]
        p_vaddr = struct.unpack_from('<I', data, ph_offset + 8)[0]
        p_paddr = struct.unpack_from('<I', data, ph_offset + 12)[0]
        p_filesz = struct.unpack_from('<I', data, ph_offset + 16)[0]

        if p_type != 1 or p_filesz == 0: # PT_LOAD
            continue

        target_base = p_paddr if p_paddr != 0 else p_vaddr
        seg_bytes = data[p_offset : p_offset + p_filesz]

        for byte_idx in range(0, len(seg_bytes), 4):
            chunk = seg_bytes[byte_idx : byte_idx + 4]
            if len(chunk) < 4:
                chunk = chunk.ljust(4, b'\x00')
            word = struct.unpack('<I', chunk)[0]
            addr = target_base + byte_idx

            # Strict bounds checking
            if ISRAM_BASE <= addr < (ISRAM_BASE + ISRAM_SIZE):
                word_idx = (addr - ISRAM_BASE) >> 2
                imem_words[word_idx] = word
            elif DSRAM_BASE <= addr < (DSRAM_BASE + DSRAM_SIZE):
                word_idx = (addr - DSRAM_BASE) >> 2
                dmem_words[word_idx] = word
            else:
                # Silently ignore unmapped / discarded headers
                pass

    # Write ISRAM .hex
    with open(imem_hex_path, 'w') as f:
        max_idx = max(imem_words.keys()) if imem_words else 0
        for idx in sorted(imem_words.keys()):
            f.write(f"@{idx:04X}\n{imem_words[idx]:08X}\n")

    # Write DSRAM .hex
    with open(dmem_hex_path, 'w') as f:
        for idx in sorted(dmem_words.keys()):
            f.write(f"@{idx:04X}\n{dmem_words[idx]:08X}\n")

    print(f"[elf_to_hex] Successfully extracted {len(imem_words)} ISRAM words -> '{imem_hex_path}'")
    print(f"[elf_to_hex] Successfully extracted {len(dmem_words)} DSRAM words -> '{dmem_hex_path}'")

if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("Usage: python elf_to_hex_clean.py <input.elf> <output_imem.hex> <output_dmem.hex>")
        sys.exit(1)
    convert_elf_to_hex(sys.argv[1], sys.argv[2], sys.argv[3])
