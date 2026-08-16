# Reads ebreak_imem.hex
# Writes flash.mem compatible with the Cypress SPI flash model
#Example
# Input:
#   @00000000
#   00000097
#   13408093
#   ...
#
# Output:
#   @0000000
#   97
#   00
#   00
#   00
#   ...
#
# Converts a 32-bit word-oriented RISC-V .mem file
# into a byte-oriented Cypress SPI flash preload file.

import os
import sys

INPUT_FILE = "ebreak_imem.mem"
OUTPUT_FILE = INPUT_FILE.replace(".mem","_spi.mem")
if not os.path.isfile(INPUT_FILE):
    print(f'Error: "{INPUT_FILE}" file does not exist.')
    sys.exit(1)

flash = {}

with open(INPUT_FILE, "r") as fin:
    addr = 0

    for line in fin:
        line = line.strip()

        if line == "" or line.startswith("//"):
            continue

        # Word address -> byte address
        if line.startswith("@"):
            try:
                addr = int(line[1:], 16) * 4
            except ValueError:
                print(f'Error: Invalid address "{line}" in "{INPUT_FILE}".')
                sys.exit(1)
            continue

        # Read 32-bit instruction
        try:
            word = int(line, 16)
        except ValueError:
            print(f'Error: Invalid hexadecimal value "{line}" in "{INPUT_FILE}".')
            sys.exit(1)
            
        # Store as little-endian bytes
        flash[addr]     = word & 0xFF
        flash[addr + 1] = (word >> 8) & 0xFF
        flash[addr + 2] = (word >> 16) & 0xFF
        flash[addr + 3] = (word >> 24) & 0xFF

        addr += 4

with open(OUTPUT_FILE, "w") as fout:
    current_addr = None

    for byte_addr in sorted(flash.keys()):

        if current_addr != byte_addr:
            fout.write(f"@{byte_addr:07X}\n")
            current_addr = byte_addr

        fout.write(f"{flash[byte_addr]:02X}\n")
        current_addr += 1

print("Done!")
print("Created:", OUTPUT_FILE)