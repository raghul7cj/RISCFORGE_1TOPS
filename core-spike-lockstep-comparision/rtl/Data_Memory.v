`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : Data_Memory
// Description : Synchronous 1-cycle Native SRAM Data Memory for RV32I.
//               Parameterized depth for easy resizing. Base-subtraction maps
//               the byte address space to zero-indexed array.
//
// ── Memory Map ──────────────────────────────────────────────────────────────
//   DMEM_BASE_BYTE : First byte address of this SRAM (default 0x8000_1000)
//   MEM_DEPTH      : Number of 32-bit words  (default 262144 = 1 MB)
//   Address range  : DMEM_BASE_BYTE  ..  DMEM_BASE_BYTE + MEM_DEPTH*4 - 1
//                    0x8000_1000     ..  0x8010_0FFF  (1 MB default)
//////////////////////////////////////////////////////////////////////////////////

module Data_Memory #(
    // ── Sizing parameters — change ONE place to resize ──────────────────────
    parameter integer MEM_DEPTH      = 6048576,       // words  (4 MB default)
    parameter [31:0]  DMEM_BASE_BYTE = 32'h8000_1000  // byte base address
) (
    input             clk,
    input             rst_n,          // Active-low reset
    input             sram_en,        // Chip Enable / Request
    input             sram_we,        // Write Enable (1=Write, 0=Read)
    input      [3:0]  sram_wmask,     // Byte-write strobes
    input      [29:0] sram_addr,      // Word address (core_addr[31:2])
    input      [31:0] sram_wdata,     // Write data
    output     [31:0] sram_rdata      // Read data — valid 1 cycle after request
);

    // ── Derived constants ────────────────────────────────────────────────────
    // Word-aligned base: strip the 2 LSBs of the byte address
    localparam [29:0] DMEM_BASE_WORD = DMEM_BASE_BYTE[31:2];

    // Address width required to index MEM_DEPTH words
    // $clog2(262144) = 18 bits
    localparam ADDR_W = $clog2(MEM_DEPTH);

    // ── Internal memory array ────────────────────────────────────────────────
    reg [31:0] mem_array [0:MEM_DEPTH-1];

    // Byte→word offset inside this SRAM
    wire [29:0] local_addr_full = sram_addr - DMEM_BASE_WORD;
    wire [ADDR_W-1:0] local_addr = local_addr_full[ADDR_W-1:0];

    // ── Synchronous byte-enable write ────────────────────────────────────────
    always @(posedge clk) begin
        if (rst_n && sram_en && sram_we) begin
            if (sram_wmask[0]) mem_array[local_addr][ 7: 0] <= sram_wdata[ 7: 0];
            if (sram_wmask[1]) mem_array[local_addr][15: 8] <= sram_wdata[15: 8];
            if (sram_wmask[2]) mem_array[local_addr][23:16] <= sram_wdata[23:16];
            if (sram_wmask[3]) mem_array[local_addr][31:24] <= sram_wdata[31:24];
        end
    end

    // ── Combinational read (0-cycle, matches hybrid_mem_interface and OLD) ────
    assign sram_rdata = (!rst_n) ? 32'd0 : mem_array[local_addr];

    // ── Simulation initialisation ────────────────────────────────────────────
`ifndef SYNTHESIS
    initial begin : init_block
        integer i;
        reg [1023:0] hex_path;
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            mem_array[i] = 32'h0;

        if ($value$plusargs("dmem_hex=%s", hex_path)) begin
            $readmemh(hex_path, mem_array);
        end else begin
            $readmemh("dmem.hex", mem_array);
        end
    end
`endif

endmodule
