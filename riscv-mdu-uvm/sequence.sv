// =============================================================================
// File: sequence.sv
// Description: UVM Sequences (Directed, Corner, Random, and Stress) for RV32M
// =============================================================================
`ifndef SEQUENCE_SV
`define SEQUENCE_SV

// ── Base Sequence ────────────────────────────────────────────────────────────
class rv32m_base_seq extends uvm_sequence #(rv32m_transaction);
    `uvm_object_utils(rv32m_base_seq)

    int no_of_tr = 50;

    function new(string name = "rv32m_base_seq");
        super.new(name);
    endfunction

    function void set_no_of_tr(int no_of_tr);
        this.no_of_tr = no_of_tr;
    endfunction

    task send_item(input bit [2:0]  f3,
                   input bit [31:0] a,
                   input bit [31:0] b,
                   input bit [4:0]  d);
        rv32m_transaction tr = rv32m_transaction::type_id::create("tr");
        start_item(tr);
        tr.funct3 = f3;
        tr.rs1    = a;
        tr.rs2    = b;
        tr.rd_in  = d;
        finish_item(tr);
    endtask

    virtual task body();
        // Overridden by derived sequences
    endtask
endclass

// ── Random Sequence ──────────────────────────────────────────────────────────
class rv32m_rand_seq extends rv32m_base_seq;
    `uvm_object_utils(rv32m_rand_seq)

    function new(string name = "rv32m_rand_seq");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("RAND_SEQ", $sformatf("Starting randomized sequence with %0d transactions", no_of_tr), UVM_MEDIUM)
        repeat (no_of_tr) begin
            rv32m_transaction tr = rv32m_transaction::type_id::create("tr");
            start_item(tr);
            if (!tr.randomize()) begin
                `uvm_fatal("RAND_SEQ", "Randomization failed in rv32m_rand_seq")
            end
            finish_item(tr);
        end
    endtask
endclass

// ── Exhaustive 79-Vector Directed Corner Sequence ────────────────────────────
class rv32m_directed_corner_seq extends rv32m_base_seq;
    `uvm_object_utils(rv32m_directed_corner_seq)

    function new(string name = "rv32m_directed_corner_seq");
        super.new(name);
    endfunction

    virtual task body();
        `uvm_info("CORNER_SEQ", "Starting exhaustive 79-vector directed & corner sequence", UVM_LOW)

        // ---------------------------------------------------------------------
        // 1. MUL (funct3 = 3'b000)
        // ---------------------------------------------------------------------
        send_item(3'b000, 32'd0,          32'd0,          5'd1);  // zero x zero
        send_item(3'b000, 32'd1,          32'd1,          5'd2);  // one x one
        send_item(3'b000, -32'd1,         -32'd1,         5'd3);  // -1 x -1
        send_item(3'b000, 32'h7FFF_FFFF,  32'h7FFF_FFFF,  5'd4);  // MaxPos x MaxPos
        send_item(3'b000, 32'h8000_0000,  32'h8000_0000,  5'd5);  // MaxNeg x MaxNeg
        send_item(3'b000, 32'd16,         32'd8,          5'd6);  // Powers of 2
        send_item(3'b000, 32'd45,         -32'd12,        5'd7);  // + x -
        send_item(3'b000, -32'd45,        32'd12,         5'd8);  // - x +
        send_item(3'b000, 32'd1000,       32'd0,          5'd9);  // Result zero

        // ---------------------------------------------------------------------
        // 2. MULH (funct3 = 3'b001)
        // ---------------------------------------------------------------------
        send_item(3'b001, 32'd0,          32'd50,         5'd10);
        send_item(3'b001, 32'd50,         32'd0,          5'd10);
        send_item(3'b001, 32'h7FFF_FFFF,  32'h7FFF_FFFF,  5'd11);
        send_item(3'b001, 32'h8000_0000,  32'h8000_0000,  5'd12); // MaxNeg x MaxNeg -> upper 0x40000000
        send_item(3'b001, -32'd1,         32'd1,          5'd13); // -1 * 1 -> upper 0xFFFFFFFF
        send_item(3'b001, -32'd1,         32'hFFFF_FFFF,  5'd13);
        send_item(3'b001, -32'd2,         -32'd2,         5'd14);
        send_item(3'b001, 32'd100,        32'd200,        5'd15);
        send_item(3'b001, -32'd100,       -32'd200,       5'd16);

        // ---------------------------------------------------------------------
        // 3. MULHSU (funct3 = 3'b010)
        // ---------------------------------------------------------------------
        send_item(3'b010, 32'd0,          32'd0,          5'd17);
        send_item(3'b010, 32'd50,         32'd1,          5'd17);
        send_item(3'b010, 32'h7FFF_FFFF,  32'hFFFF_FFFF,  5'd18);
        send_item(3'b010, 32'h8000_0000,  32'd2,          5'd19);
        send_item(3'b010, -32'd1,         32'd2,          5'd20); // Upper -1
        send_item(3'b010, -32'd50,        32'h8000_0000,  5'd21);
        send_item(3'b010, 32'd50,         32'h8000_0000,  5'd22);
        send_item(3'b010, 32'd2,          32'd2,          5'd23);

        // ---------------------------------------------------------------------
        // 4. MULHU (funct3 = 3'b011)
        // ---------------------------------------------------------------------
        send_item(3'b011, 32'hFFFF_FFFF,  32'd0,          5'd24);
        send_item(3'b011, 32'd0,          32'hFFFF_FFFF,  5'd24);
        send_item(3'b011, 32'd1,          32'd1,          5'd25);
        send_item(3'b011, 32'hFFFF_FFFF,  32'hFFFF_FFFF,  5'd26); // 0xFFFFFFFE corner
        send_item(3'b011, 32'h4000_0000,  32'h4000_0000,  5'd27);
        send_item(3'b011, 32'h9000_0000,  32'h9000_0000,  5'd28);
        send_item(3'b011, 32'd10,         32'd10,         5'd29);

        // ---------------------------------------------------------------------
        // 5. DIV (funct3 = 3'b100)
        // ---------------------------------------------------------------------
        send_item(3'b100, 32'd42,         32'd0,          5'd30); // DIV-BY-ZERO -> -1
        send_item(3'b100, 32'h8000_0000,  32'hFFFF_FFFF,  5'd31); // SIGNED OVERFLOW -> -2^31
        send_item(3'b100, 32'h8000_0000,  32'd2,          5'd31);
        send_item(3'b100, 32'd1,          32'd1,          5'd1);
        send_item(3'b100, -32'd1,         32'd1,          5'd1);
        send_item(3'b100, 32'd50,         32'hFFFF_FFFF,  5'd1);
        send_item(3'b100, 32'd50,         32'd50,         5'd1);  // Self div (A/A=1)
        send_item(3'b100, 32'd2,          32'd50,         5'd2);  // A < B (Q=0)
        send_item(3'b100, 32'd100,        32'd1,          5'd3);  // Identity (A/1=A)
        send_item(3'b100, 32'd64,         32'd8,          5'd4);  // Power of 2
        send_item(3'b100, 32'd100,        32'd5,          5'd5);  // + / +
        send_item(3'b100, 32'd100,        -32'd5,         5'd6);  // + / -
        send_item(3'b100, -32'd100,       32'd5,          5'd7);  // - / +
        send_item(3'b100, -32'd100,       -32'd5,         5'd8);  // - / -
        send_item(3'b100, 32'd0,          32'd10,         5'd9);  // 0 / B = 0
        send_item(3'b100, 32'h7FFF_FFFF,  32'd2,          5'd10); // MaxPos

        // ---------------------------------------------------------------------
        // 6. DIVU (funct3 = 3'b101)
        // ---------------------------------------------------------------------
        send_item(3'b101, 32'd0,          32'd50,         5'd11);
        send_item(3'b101, 32'd1,          32'd1,          5'd11);
        send_item(3'b101, 32'd42,         32'd0,          5'd11); // Unsigned DIV-BY-ZERO -> 0xFFFFFFFF
        send_item(3'b101, 32'd10,         32'd10,         5'd12);
        send_item(3'b101, 32'd5,          32'd100,        5'd13);
        send_item(3'b101, 32'hFFFF_FFFF,  32'd2,          5'd14);
        send_item(3'b101, 32'd100,        32'd1,          5'd15);
        send_item(3'b101, 32'd256,        32'd16,         5'd16);
        send_item(3'b101, 32'h9000_0000,  32'h8000_0000,  5'd17);

        // ---------------------------------------------------------------------
        // 7. REM (funct3 = 3'b110)
        // ---------------------------------------------------------------------
        send_item(3'b110, 32'd42,         32'd0,          5'd18); // REM-BY-ZERO -> dividend
        send_item(3'b110, 32'h8000_0000,  32'hFFFF_FFFF,  5'd19); // OVERFLOW REM -> 0
        send_item(3'b110, 32'hFFFF_FFFF,  32'd5,          5'd19);
        send_item(3'b110, 32'd5,          32'hFFFF_FFFF,  5'd19);
        send_item(3'b110, 32'd5,          32'd1,          5'd19);
        send_item(3'b110, 32'd100,        32'd10,         5'd20); // Exact div (Rem=0)
        send_item(3'b110, 32'd25,         32'd4,          5'd21); // Pos / Pos -> Pos Rem (+1)
        send_item(3'b110, 32'd25,         -32'd4,         5'd22); // Pos / Neg -> Pos Rem (+1)
        send_item(3'b110, -32'd25,        32'd4,          5'd23); // Neg / Pos -> Neg Rem (-1)
        send_item(3'b110, -32'd25,        -32'd4,         5'd24); // Neg / Neg -> Neg Rem (-1)
        send_item(3'b110, 32'h7FFF_FFFF,  32'd10,         5'd25);
        send_item(3'b110, 32'd0,          32'd5,          5'd26);

        // ---------------------------------------------------------------------
        // 8. REMU (funct3 = 3'b111)
        // ---------------------------------------------------------------------
        send_item(3'b111, 32'd0,          32'd5,          5'd27);
        send_item(3'b111, 32'd42,         32'd0,          5'd27); // REMU-BY-ZERO -> dividend
        send_item(3'b111, 32'd100,        32'd1,          5'd28);
        send_item(3'b111, 32'd100,        32'd10,         5'd28);
        send_item(3'b111, 32'd5,          32'd20,         5'd29);
        send_item(3'b111, 32'd5,          32'hFFFF_FFFF,  5'd29);
        send_item(3'b111, 32'hFFFF_FFFF,  32'd10,         5'd30);
        send_item(3'b111, 32'hFFFF_FFFF,  32'h8000_0000,  5'd31);
        send_item(3'b111, 32'hFFFF_FFFF,  32'd0,          5'd1);

        `uvm_info("CORNER_SEQ", "Completed all 79 directed & corner transactions", UVM_LOW)
    endtask
endclass

// ── Multiplier Stress Sequence ───────────────────────────────────────────────
class rv32m_mul_stress_seq extends rv32m_base_seq;
    `uvm_object_utils(rv32m_mul_stress_seq)

    function new(string name = "rv32m_mul_stress_seq");
        super.new(name);
        no_of_tr = 100;
    endfunction

    virtual task body();
        `uvm_info("MUL_STRESS", $sformatf("Driving %0d continuous back-to-back multiplications", no_of_tr), UVM_MEDIUM)
        repeat (no_of_tr) begin
            rv32m_transaction tr = rv32m_transaction::type_id::create("tr");
            start_item(tr);
            if (!tr.randomize() with { funct3 inside {3'b000, 3'b001, 3'b010, 3'b011}; }) begin
                `uvm_fatal("MUL_STRESS", "Randomization failed")
            end
            finish_item(tr);
        end
    endtask
endclass

// ── Divider Stress Sequence ──────────────────────────────────────────────────
class rv32m_div_stress_seq extends rv32m_base_seq;
    `uvm_object_utils(rv32m_div_stress_seq)

    function new(string name = "rv32m_div_stress_seq");
        super.new(name);
        no_of_tr = 60;
    endfunction

    virtual task body();
        `uvm_info("DIV_STRESS", $sformatf("Driving %0d divider FSM stress transactions", no_of_tr), UVM_MEDIUM)
        repeat (no_of_tr) begin
            rv32m_transaction tr = rv32m_transaction::type_id::create("tr");
            start_item(tr);
            if (!tr.randomize() with { funct3 inside {3'b100, 3'b101, 3'b110, 3'b111}; }) begin
                `uvm_fatal("DIV_STRESS", "Randomization failed")
            end
            finish_item(tr);
        end
    endtask
endclass

// Backward compatibility alias for template integration
typedef rv32m_rand_seq dummy_seq;

`endif // SEQUENCE_SV
