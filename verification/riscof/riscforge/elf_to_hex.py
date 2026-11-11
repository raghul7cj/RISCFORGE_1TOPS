import sys
import os
from elftools.elf.elffile import ELFFile

# ─── Memory map (must match RTL parameters) ───────────────────────────────
IMEM_BASE  = 0x80000000   # Instruction_Memory_new: IMEM_BASE_BYTE
DMEM_BASE  = 0x80001000   # Data_Memory:            DMEM_BASE_BYTE
# ──────────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 4:
        print("Usage: python elf_to_hex.py <elf_file> <imem_hex_out> <dmem_hex_out>")
        sys.exit(1)
        
    elf_path = sys.argv[1]
    imem_out = sys.argv[2]
    dmem_out = sys.argv[3]
    
    imem_dict = {}
    dmem_dict = {}
    
    with open(elf_path, 'rb') as f:
        elffile = ELFFile(f)
        
        # Dynamically find the boundary between IMEM (code) and DMEM (data)
        # Default fallback is DMEM_BASE so any address below it is treated as code.
        data_boundary = DMEM_BASE
        for section in elffile.iter_sections():
            if section.name in ['.tohost', '.data']:
                data_boundary = section['sh_addr']
                break

        for segment in elffile.iter_segments():
            if segment['p_type'] == 'PT_LOAD':
                paddr = segment['p_paddr']
                data = segment.data()
                
                # Zero-pad data to 4-byte boundary if needed
                pad_len = (4 - (len(data) % 4)) % 4
                if pad_len > 0:
                    data = data + b'\x00' * pad_len
                    
                for i in range(0, len(data), 4):
                    addr = paddr + i
                    word = int.from_bytes(data[i:i+4], byteorder='little')
                    
                    # Map to IMEM or DMEM based on dynamically found boundary
                    if addr < data_boundary:
                        # IMEM: index relative to IMEM_BASE (word address)
                        word_index = (addr - IMEM_BASE) >> 2
                        imem_dict[word_index] = word
                    else:
                        # DMEM: index relative to DMEM_BASE (word address)
                        word_index = (addr - DMEM_BASE) >> 2
                        dmem_dict[word_index] = word
                        
    # Write imem_out
    with open(imem_out, 'w') as f:
        if imem_dict:
            for idx in sorted(imem_dict.keys()):
                f.write(f"@{idx:08x}\n{imem_dict[idx]:08x}\n")
                
    # Write dmem_out
    with open(dmem_out, 'w') as f:
        if dmem_dict:
            for idx in sorted(dmem_dict.keys()):
                f.write(f"@{idx:08x}\n{dmem_dict[idx]:08x}\n")
                
    print(f"Generated {imem_out} and {dmem_out} successfully.")

if __name__ == '__main__':
    main()
