#!/usr/bin/env python3
"""
elf_to_hex.py — Authoritative ELF to Simulation Memory Hex Converter
Extracts loadable (SHF_ALLOC) sections from a RISC-V 32-bit ELF file and emits:
  - ISRAM hex file (word index 0 = 0x0001_0000)
  - DSRAM hex file (word index 0 = 0x0002_0000)
Each line contains an 8-character lowercase hexadecimal 32-bit little-endian word.
"""

import sys
import os
import struct

ISRAM_BASE = 0x00010000
ISRAM_SIZE = 0x00008000  # 32 KiB

DSRAM_BASE = 0x00020000
DSRAM_SIZE = 0x00008000  # 32 KiB

SHF_WRITE     = 0x1
SHF_ALLOC     = 0x2
SHF_EXECINSTR = 0x4

SHT_PROGBITS  = 1
SHT_NOBITS    = 8

def parse_elf32(elf_path):
    with open(elf_path, "rb") as f:
        data = f.read()

    # Verify ELF Magic
    if data[0:4] != b"\x7fELF":
        raise ValueError("Not a valid ELF file (missing magic)")
    if data[4] != 1:  # ELFCLASS32
        raise ValueError("Not a 32-bit ELF file")
    if data[5] != 1:  # ELFDATA2LSB (little endian)
        raise ValueError("Not a little-endian ELF file")

    e_shoff     = struct.unpack_from("<I", data, 32)[0]
    e_shentsize = struct.unpack_from("<H", data, 46)[0]
    e_shnum     = struct.unpack_from("<H", data, 48)[0]
    e_shstrndx  = struct.unpack_from("<H", data, 50)[0]

    # Read section headers
    sections = []
    for i in range(e_shnum):
        offset = e_shoff + i * e_shentsize
        sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size = struct.unpack_from("<IIIIII", data, offset)
        sections.append({
            "name_idx": sh_name,
            "type": sh_type,
            "flags": sh_flags,
            "addr": sh_addr,
            "offset": sh_offset,
            "size": sh_size,
        })

    # Read string table
    shstr = sections[e_shstrndx]
    shstr_data = data[shstr["offset"]:shstr["offset"] + shstr["size"]]

    for s in sections:
        name_end = shstr_data.find(b"\x00", s["name_idx"])
        s["name"] = shstr_data[s["name_idx"]:name_end].decode("latin-1")
        if s["type"] == SHT_PROGBITS:
            s["data"] = data[s["offset"]:s["offset"] + s["size"]]
        elif s["type"] == SHT_NOBITS:
            s["data"] = b"\x00" * s["size"]
        else:
            s["data"] = b""

    return sections

def emit_hex(sections, base_addr, size_bytes, out_path, mem_name):
    mem_bytes = bytearray(size_bytes)
    occupied = bytearray(size_bytes)
    max_extent = 0

    alloc_sections = [s for s in sections if (s["flags"] & SHF_ALLOC) and s["size"] > 0]

    for s in alloc_sections:
        addr = s["addr"]
        sz = s["size"]
        
        # Check if section falls within this memory region
        if base_addr <= addr < (base_addr + size_bytes):
            if (addr + sz) > (base_addr + size_bytes):
                raise ValueError(f"Section {s['name']} overflows {mem_name}: addr 0x{addr:08x} + sz {sz} > 0x{base_addr + size_bytes:08x}")
            
            rel_offset = addr - base_addr
            
            # Check for overlap with already populated sections
            for b in range(rel_offset, rel_offset + sz):
                if occupied[b]:
                    raise ValueError(f"Section overlap detected in {mem_name} at address 0x{base_addr + b:08x}")
                occupied[b] = 1
                
            mem_bytes[rel_offset:rel_offset + sz] = s["data"]
            if (rel_offset + sz) > max_extent:
                max_extent = rel_offset + sz

    # Pad max_extent to 4-byte multiple
    if max_extent % 4 != 0:
        max_extent += 4 - (max_extent % 4)

    # Convert to 32-bit little endian words
    words = []
    for i in range(0, max_extent, 4):
        w = struct.unpack_from("<I", mem_bytes, i)[0]
        words.append(f"{w:08x}\n")

    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.writelines(words)

    return len(words)

def main():
    if len(sys.argv) < 4:
        print("Usage: elf_to_hex.py <elf_file> <imem_hex_out> <dmem_hex_out>")
        sys.exit(1)

    elf_file  = sys.argv[1]
    imem_out  = sys.argv[2]
    dmem_out  = sys.argv[3]

    sections = parse_elf32(elf_file)

    num_iwords = emit_hex(sections, ISRAM_BASE, ISRAM_SIZE, imem_out, "ISRAM")
    num_dwords = emit_hex(sections, DSRAM_BASE, DSRAM_SIZE, dmem_out, "DSRAM")

    print(f"[elf_to_hex] Success: {elf_file}")
    print(f"  -> ISRAM: {imem_out} ({num_iwords} words = {num_iwords*4} bytes)")
    print(f"  -> DSRAM: {dmem_out} ({num_dwords} words = {num_dwords*4} bytes)")

if __name__ == "__main__":
    main()
