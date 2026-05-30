`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : ls_unit
//
// Description:
//  Load/Store data alignment and formatting unit for RV32I.
//
//  Responsibilities:
//      1. Format load data (byte/half/word)
//      2. Generate byte-enable strobes for stores
//      3. Align store data to correct byte lanes
//
//  lsunit Encoding:
//      lsunit[4]   : Load/Store enable
//      lsunit[3]   : Opcode bit[5] (distinguishes load vs store)
//      lsunit[2:0] : funct3 field
//
//      lsunit[4:3] = 2'b10 → LOAD
//      lsunit[4:3] = 2'b11 → STORE
//
//  Inputs:
//      in       : 32-bit data read from memory
//      address  : Effective memory address
//      in_s     : Store data (register value)
//
//  Outputs:
//      out      : Formatted load result
//      strobe   : Byte write enable signals
//      out_s    : Aligned store data
//
//////////////////////////////////////////////////////////////////////////////////

module ls_unit(in, lsunit, out, strobe, address, in_s,out_s);

    // --------------------------------------------------
    // Inputs
    // --------------------------------------------------
    input  [31:0] in;        // Data from memory (for loads)
    //input  [31:0] address;   // Effective memory address
    input  [1:0] address;   // Effective memory address
    input  [31:0] in_s;      // Store data from register
    input  [4:0]  lsunit;    // Load/Store control bus

    // --------------------------------------------------
    // Outputs
    // --------------------------------------------------
    output [31:0] out;       // Formatted load result
    output [31:0] out_s;     // Aligned store data
    output [3:0]  strobe;    // Byte-enable signals

    // ==================================================
    // LOAD DATA FORMATTING
    // ==================================================
    // Active when lsunit[4:3] == 2'b10
    // Uses funct3 (lsunit[2:0]) to determine width/type

    assign out = (lsunit[4:3] == 2'b10) ?

        // --------------------------------------------------
        // LB  (funct3 = 000) - Load Byte (sign-extended)
        // --------------------------------------------------
        (lsunit[2:0] == 3'b000) ?
            (address[1:0] == 2'b00) ? {{24{in[7]}},  in[7:0]}   :
            (address[1:0] == 2'b01) ? {{24{in[15]}}, in[15:8]}  :
            (address[1:0] == 2'b10) ? {{24{in[23]}}, in[23:16]} :
                                      {{24{in[31]}}, in[31:24]} :

        // --------------------------------------------------
        // LH  (funct3 = 001) - Load Halfword (sign-extended)
        // --------------------------------------------------
        (lsunit[2:0] == 3'b001) ?
            (address[1] == 1'b0) ?
                {{16{in[15]}}, in[15:0]} :
                {{16{in[31]}}, in[31:16]} :

        // --------------------------------------------------
        // LW  (funct3 = 010) - Load Word
        // --------------------------------------------------
        (lsunit[2:0] == 3'b010) ?
            in :

        // --------------------------------------------------
        // LBU (funct3 = 100) - Load Byte (zero-extended)
        // --------------------------------------------------
        (lsunit[2:0] == 3'b100) ?
            (address[1:0] == 2'b00) ? {{24{1'b0}}, in[7:0]}   :
            (address[1:0] == 2'b01) ? {{24{1'b0}}, in[15:8]}  :
            (address[1:0] == 2'b10) ? {{24{1'b0}}, in[23:16]} :
                                      {{24{1'b0}}, in[31:24]} :

        // --------------------------------------------------
        // LHU (funct3 = 101) - Load Halfword (zero-extended)
        // --------------------------------------------------
            (address[1] == 1'b0) ?
                {{16{1'b0}}, in[15:0]} :
                {{16{1'b0}}, in[31:16]} :

        // Not a load → output zero
        32'd0;


    // ==================================================
    // STORE BYTE-ENABLE (STROBE) GENERATION
    // ==================================================
    // Active when lsunit[4:3] == 2'b11

    assign strobe = (lsunit[4:3] == 2'b11) ?

        // --------------------------------------------------
        // SB (funct3 = 000)
        // --------------------------------------------------
        (lsunit[2:0] == 3'b000) ?
            (address[1:0] == 2'b00) ? 4'b0001 :
            (address[1:0] == 2'b01) ? 4'b0010 :
            (address[1:0] == 2'b10) ? 4'b0100 :
                                      4'b1000 :

        // --------------------------------------------------
        // SH (funct3 = 001)
        // --------------------------------------------------
        (lsunit[2:0] == 3'b001) ?
            (address[1] == 1'b0) ? 4'b0011 :
                                   4'b1100 :

        // --------------------------------------------------
        // SW (default)
        // --------------------------------------------------
            4'b1111 :

        // Not a store → default strobe
        4'b1111;


    // ==================================================
    // STORE DATA ALIGNMENT
    // ==================================================
    // Aligns store data to correct byte lanes

    assign out_s = (lsunit[4:3] == 2'b11) ?

        // --------------------------------------------------
        // SB
        // --------------------------------------------------
        (lsunit[2:0] == 3'b000) ?
            (address[1:0] == 2'b00) ? in_s :
            (address[1:0] == 2'b01) ? in_s << 8  :
            (address[1:0] == 2'b10) ? in_s << 16 :
                                      in_s << 24 :

        // --------------------------------------------------
        // SH
        // --------------------------------------------------
        (lsunit[2:0] == 3'b001) ?
            (address[1] == 1'b0) ? in_s :
                                   (in_s << 16) :

        // --------------------------------------------------
        // SW
        // --------------------------------------------------
            in_s :

        // Not a store → pass-through
        in_s;

endmodule
