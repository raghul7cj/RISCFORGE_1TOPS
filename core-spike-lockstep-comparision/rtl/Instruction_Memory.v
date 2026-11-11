`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : Instruction_Memory_new
// Description : Synchronous SRAM — 1-cycle read latency, byte-enable write.
//               Parameterized depth for easy resizing.
//
// ── Memory Map ──────────────────────────────────────────────────────────────
//   IMEM_BASE_BYTE : First byte address of this SRAM (default 0x8000_0000)
//   MEM_DEPTH      : Number of 32-bit words  (default 262144 = 1 MB)
//   Address range  : IMEM_BASE_BYTE  ..  IMEM_BASE_BYTE + MEM_DEPTH*4 - 1
//                    0x8000_0000     ..  0x800F_FFFF  (1 MB default)
//
//  Read latency model:
//    Cycle T   : sram_en=1, sram_addr → raddr_q latched
//    Cycle T+1 : sram_rdata = mem[raddr_q]  (combinational on latched addr)
//
//  During stall (sram_en=0): raddr_q holds → sram_rdata is stable.
//  During reset (!rst_n):    raddr_q=0, sram_rdata forced to 0.
////////////////////////////////////////////////////////////////////////////////

module Instruction_Memory_new #(
    // ── Sizing parameters — change ONE place to resize ──────────────────────
    parameter integer MEM_DEPTH      = 1048576,       // words  (4 MB default)
    parameter [31:0]  IMEM_BASE_BYTE = 32'h8000_0000  // byte base address
) (
    input             clk,
    input             rst_n,        // Active-low reset

    // ---- Port signals (shared by read and write) ----
    input             sram_en,      // Chip enable: latch address / allow write
    input             sram_we,      // Write enable (0 = read-only fetch path)
    input      [3:0]  sram_wmask,   // Byte write mask [3]=MSB byte, [0]=LSB byte
    input      [29:0] sram_addr,    // Word address (PC[31:2])
    input      [31:0] sram_wdata,   // Write data (unused in fetch path)

    output     [31:0] sram_rdata    // Instruction word, valid 1 cycle after addr
);

    // ── Derived constants ────────────────────────────────────────────────────
    // Word-aligned base: strip the 2 LSBs of the byte address
    localparam [29:0] IMEM_BASE_WORD = IMEM_BASE_BYTE[31:2];

    // Address width required to index MEM_DEPTH words  ($clog2(262144) = 18)
    localparam ADDR_W = $clog2(MEM_DEPTH);

    // ── Internal memory array ────────────────────────────────────────────────
    reg [31:0] mem_array [0:MEM_DEPTH-1];

    // Byte→word offset inside this SRAM
    wire [29:0] local_addr_full = sram_addr - IMEM_BASE_WORD;
    wire [ADDR_W-1:0] local_addr = local_addr_full[ADDR_W-1:0];

    // Address latch for synchronous 1-cycle read latency
    reg [ADDR_W-1:0] raddr_q;
    always @(posedge clk) begin
        if (!rst_n) raddr_q <= 'b0;
        else if (sram_en) raddr_q <= local_addr;
    end

    // Byte-masked write (used for programming / runtime loader)
    always @(posedge clk) begin
        if (rst_n && sram_en && sram_we) begin
            if (sram_wmask[0]) mem_array[local_addr][ 7: 0] <= sram_wdata[ 7: 0];
            if (sram_wmask[1]) mem_array[local_addr][15: 8] <= sram_wdata[15: 8];
            if (sram_wmask[2]) mem_array[local_addr][23:16] <= sram_wdata[23:16];
            if (sram_wmask[3]) mem_array[local_addr][31:24] <= sram_wdata[31:24];
        end
    end

    // Synchronous 1-cycle read latency (matches imem_controller pre-fetch contract)
    assign sram_rdata = (!rst_n) ? 32'd0 : mem_array[raddr_q];

    // ── Simulation initialisation ────────────────────────────────────────────
`ifndef SYNTHESIS
    initial begin : init_mem
        integer i;
        reg [1023:0] hex_path;
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            mem_array[i] = 32'h0000_0013;   // default: NOP (ADDI x0,x0,0)

        if ($value$plusargs("imem_hex=%s", hex_path)) begin
            $display("[IMEM] Loading %0s", hex_path);
            $readmemh(hex_path, mem_array);
        end else begin
            $display("[IMEM] Loading imem.hex");
            $readmemh("imem.hex", mem_array);
        end
    end
`endif

endmodule
