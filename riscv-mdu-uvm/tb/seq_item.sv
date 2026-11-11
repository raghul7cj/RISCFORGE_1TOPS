// =============================================================================
// File: seq_item.sv
// Description: UVM Sequence Item (Transaction) for RV32M Coprocessor Unit
// =============================================================================
`ifndef SEQ_ITEM_SV
`define SEQ_ITEM_SV

typedef enum logic [2:0] {
    OP_MUL    = 3'b000,
    OP_MULH   = 3'b001,
    OP_MULHSU = 3'b010,
    OP_MULHU  = 3'b011,
    OP_DIV    = 3'b100,
    OP_DIVU   = 3'b101,
    OP_REM    = 3'b110,
    OP_REMU   = 3'b111
} rv32m_op_e;

class rv32m_transaction extends uvm_sequence_item;

    // ── Random Inputs ───────────────────────────────────────────────────────
    rand bit [31:0] rs1;
    rand bit [31:0] rs2;
    rand bit [2:0]  funct3;
    rand bit [4:0]  rd_in;

    // ── Observed DUT Outputs ────────────────────────────────────────────────
    logic [31:0]    result;
    logic [4:0]     rd_out;
    int unsigned    actual_cycles;

    // ── Metadata / Control Flags ────────────────────────────────────────────
    rand bit        bias_corner_cases;

    `uvm_object_utils_begin(rv32m_transaction)
        `uvm_field_int (rs1,               UVM_ALL_ON | UVM_HEX)
        `uvm_field_int (rs2,               UVM_ALL_ON | UVM_HEX)
        `uvm_field_int (funct3,            UVM_ALL_ON | UVM_BIN)
        `uvm_field_int (rd_in,             UVM_ALL_ON | UVM_DEC)
        `uvm_field_int (result,            UVM_ALL_ON | UVM_HEX)
        `uvm_field_int (rd_out,            UVM_ALL_ON | UVM_DEC)
        `uvm_field_int (actual_cycles,     UVM_ALL_ON | UVM_DEC)
        `uvm_field_int (bias_corner_cases, UVM_ALL_ON | UVM_BIN)
    `uvm_object_utils_end

    // ── Constraints ─────────────────────────────────────────────────────────
    constraint c_rd {
        rd_in dist {
            5'd0       := 2,   // x0 zero register write
            [5'd1:5'd31] := 98  // General purpose registers x1..x31
        };
    }

    constraint c_funct3 {
        funct3 inside {[3'b000:3'b111]};
    }

    // Operand distribution: balance typical values, boundary limits, and corners
    constraint c_operands {
        rs1 dist {
            32'h0000_0000 := 8,
            32'h0000_0001 := 8,
            32'hFFFF_FFFF := 8,
            32'h7FFF_FFFF := 8,  // Max positive signed
            32'h8000_0000 := 8,  // Max negative signed
            [32'h2 : 32'hFF] := 15,
            [32'h100 : 32'h7FFF_FFFE] := 25,
            [32'h8000_0001 : 32'hFFFF_FFFE] := 20
        };

        rs2 dist {
            32'h0000_0000 := 10, // Div-by-zero & Mul-by-zero
            32'h0000_0001 := 8,  // Identity div & mul
            32'hFFFF_FFFF := 10, // Signed overflow divisor (-1)
            32'h7FFF_FFFF := 8,  // Max positive
            32'h8000_0000 := 8,  // Max negative
            [32'h2 : 32'hFF] := 15,
            [32'h100 : 32'h7FFF_FFFE] := 21,
            [32'h8000_0001 : 32'hFFFF_FFFE] := 20
        };
    }

    // High bias on signed overflow when bias_corner_cases is active
    constraint c_corner_bias {
        if (bias_corner_cases) {
            (rs1 == 32'h8000_0000 && rs2 == 32'hFFFF_FFFF) ||
            (rs2 == 32'h0000_0000) ||
            (rs1 == rs2);
        }
    }

    function new(string name = "rv32m_transaction");
        super.new(name);
        bias_corner_cases = 0;
    endfunction

    // ── Helper Inspection Methods ───────────────────────────────────────────
    function string get_op_name();
        case (funct3)
            OP_MUL:    return "MUL";
            OP_MULH:   return "MULH";
            OP_MULHSU: return "MULHSU";
            OP_MULHU:  return "MULHU";
            OP_DIV:    return "DIV";
            OP_DIVU:   return "DIVU";
            OP_REM:    return "REM";
            OP_REMU:   return "REMU";
            default:   return "UNKNOWN";
        endcase
    endfunction

    function bit is_mul();
        return ~funct3[2];
    endfunction

    function bit is_div();
        return funct3[2];
    endfunction

    function bit is_div_by_zero();
        return is_div() && (rs2 == 32'b0);
    endfunction

    function bit is_signed_overflow();
        return (funct3 == OP_DIV || funct3 == OP_REM) &&
               (rs1 == 32'h8000_0000) && (rs2 == 32'hFFFF_FFFF);
    endfunction

    // ── Standard UVM Methods ────────────────────────────────────────────────
    virtual function void do_copy(uvm_object rhs);
        rv32m_transaction rhs_;
        if (!$cast(rhs_, rhs)) begin
            `uvm_fatal("DO_COPY", "Cast failed in rv32m_transaction::do_copy")
            return;
        end
        super.do_copy(rhs);
        this.rs1               = rhs_.rs1;
        this.rs2               = rhs_.rs2;
        this.funct3            = rhs_.funct3;
        this.rd_in             = rhs_.rd_in;
        this.result            = rhs_.result;
        this.rd_out            = rhs_.rd_out;
        this.actual_cycles     = rhs_.actual_cycles;
        this.bias_corner_cases = rhs_.bias_corner_cases;
    endfunction

    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        rv32m_transaction rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (super.do_compare(rhs, comparer) &&
                (this.rs1    === rhs_.rs1) &&
                (this.rs2    === rhs_.rs2) &&
                (this.funct3 === rhs_.funct3) &&
                (this.rd_in  === rhs_.rd_in) &&
                (this.result === rhs_.result) &&
                (this.rd_out === rhs_.rd_out));
    endfunction

    virtual function string convert2string();
        return $sformatf("[%s] rs1=0x%08h (%0d), rs2=0x%08h (%0d) | rd_in=x%0d -> res=0x%08h (rd_out=x%0d) [%0d cycles]",
                         get_op_name(), rs1, $signed(rs1), rs2, $signed(rs2), rd_in, result, rd_out, actual_cycles);
    endfunction

    virtual function void do_print(uvm_printer printer);
        super.do_print(printer);
        printer.print_string("instruction", get_op_name());
        printer.print_field("rs1", rs1, 32, UVM_HEX);
        printer.print_field("rs2", rs2, 32, UVM_HEX);
        printer.print_field("funct3", funct3, 3, UVM_BIN);
        printer.print_field("rd_in", rd_in, 5, UVM_DEC);
        printer.print_field("result", result, 32, UVM_HEX);
        printer.print_field("rd_out", rd_out, 5, UVM_DEC);
        printer.print_field("actual_cycles", actual_cycles, 32, UVM_DEC);
    endfunction

endclass : rv32m_transaction

// Backward compatibility alias for template integration
typedef rv32m_transaction transaction;

`endif // SEQ_ITEM_SV
