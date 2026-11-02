#!/usr/bin/env python3
"""
RISCFORGE 1TOPS - flash preload file for soc_nexys4ddr_tb.sv.

    python make_sim_flash.py              # Pong simulation build
    python make_sim_flash.py <flash.mem>  # any <fw>_flash.mem

Writes pong_flash_at_400000.mem next to this script: the same bytes as the
firmware's flash.mem, preceded by an "@0400000" address line so the
S25FS512S model preloads them at the board's image offset (FLASH_IMAGE_ADDR
in nexys4ddr_top.sv). Everything below 0x400000 stays erased (0xFF), as the
bitstream area would look to the bootloader if it read the wrong address.

Use the SIMULATION build (mem/pong/sim_build), which the testbench decodes at
UART divisor 2.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
IMAGE_ADDR = 0x40_0000
DEFAULT_SRC = HERE.parents[2] / "mem" / "pong" / "sim_build" / "pong_flash.mem"


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    if not src.is_file():
        sys.exit(f"Error: {src} not found (run: cd mem/pong && python build.py --sim)")
    data = [ln.strip() for ln in src.read_text().splitlines() if ln.strip()]
    dst = HERE / "pong_flash_at_400000.mem"
    # s25fs512s.sv reads exactly preload_address_width = 7 hex digits after '@'
    dst.write_text(f"@{IMAGE_ADDR:07X}\n" + "".join(f"{b}\n" for b in data))
    print(f"{len(data)} bytes from {src}")
    print(f"  -> {dst} at 0x{IMAGE_ADDR:06X}")


if __name__ == "__main__":
    main()
