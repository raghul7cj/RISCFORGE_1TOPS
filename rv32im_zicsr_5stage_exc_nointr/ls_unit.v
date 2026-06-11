`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : ls_unit
// Description : Clean, non-nested, highly debuggable Load/Store Unit for RV32I
//////////////////////////////////////////////////////////////////////////////////

module ls_unit(
    input  [31:0] in,       // Data read from memory (for loads)
    input  [1:0]  address,  // Effective memory address lower bits [1:0]
    input  [31:0] in_s,     // Store data from register
    input  [4:0]  lsunit,   // Load/Store control bus: [4]=en, [3]=is_store, [2:0]=funct3
    
    output reg [31:0] out,    // Formatted load result
    output reg [31:0] out_s,  // Aligned store data
    output reg [3:0]  strobe  // Byte-enable signals
);

    // Unpack control lines for readability
    wire        ls_en    = lsunit[4];
    wire        is_store = lsunit[4] & lsunit[3] ;
    wire        is_load  = lsunit[4] & !lsunit[3] ;
    wire [2:0]  funct3   = lsunit[2:0];

    // ==================================================
    // LOAD DATA FORMATTING (Behavioral Mux)
    // ==================================================
    always @(*) begin
        if (is_load) begin
            case (funct3)
                3'b000: begin // LB (Load Byte, Sign-Extended)
                    case (address)
                        2'b00:   out = {{24{in[7]}},  in[7:0]};
                        2'b01:   out = {{24{in[15]}}, in[15:8]};
                        2'b10:   out = {{24{in[23]}}, in[23:16]};
                        default: out = {{24{in[31]}}, in[31:24]};
                    endcase
                end
                
                3'b001: begin // LH (Load Halfword, Sign-Extended)
                    if (address[1] == 1'b0)
                        out = {{16{in[15]}}, in[15:0]};
                    else
                        out = {{16{in[31]}}, in[31:16]};
                end
                
                3'b010: begin // LW (Load Word)
                    out = in; 
                end
                
                3'b100: begin // LBU (Load Byte, Zero-Extended)
                    case (address)
                        2'b00:   out = {24'b0, in[7:0]};
                        2'b01:   out = {24'b0, in[15:8]};
                        2'b10:   out = {24'b0, in[23:16]};
                        default: out = {24'b0, in[31:24]};
                    endcase
                end
                
                3'b101: begin // LHU (Load Halfword, Zero-Extended)
                    if (address[1] == 1'b0)
                        out = {16'b0, in[15:0]};
                    else
                        out = {16'b0, in[31:16]};
                end
                
                default: out = 32'd0; // Safe fallback for undefined loads
            endcase
        end else begin
            out = 32'd0;
        end
    end

    // ==================================================
    // STORE DATA ALIGNMENT & STROBE GENERATION
    // ==================================================
    always @(*) begin
        if (is_store) begin
            case (funct3)
                3'b000: begin // SB (Store Byte)
                    case (address)
                        2'b00:   begin strobe = 4'b0001; out_s = in_s;         end
                        2'b01:   begin strobe = 4'b0010; out_s = in_s << 8;    end
                        2'b10:   begin strobe = 4'b0100; out_s = in_s << 16;   end
                        default: begin strobe = 4'b1000; out_s = in_s << 24;   end
                    endcase
                end
                
                3'b001: begin // SH (Store Halfword)
                    if (address[1] == 1'b0) begin
                        strobe = 4'b0011;
                        out_s  = in_s;
                    end else begin
                        strobe = 4'b1100;
                        out_s  = in_s << 16;
                    end
                end
                
                3'b010: begin // SW (Store Word)
                    strobe = 4'b1111;
                    out_s  = in_s;
                end
                
                default: begin // Safe fallback if control bus is garbage/corrupted
                    strobe = 4'b0000; 
                    out_s  = 32'd0;
                end
            endcase
        end else begin
            strobe = 4'b0000; // Force zero write enables when not executing a store
            out_s  = in_s;    // Default pass-through
        end
    end

endmodule