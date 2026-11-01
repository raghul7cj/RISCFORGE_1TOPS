`timescale 1ns / 1ps
// [0] is cause 7; [12:1] are causes 27:16.
// Class 2: fixed 7,22,24,26,20,21,23,25 (highest first).
// Class 1: cyclic round robin 19,18,27. Class 0: round robin 17,16.
// Threshold and round-robin history are independent: history advances only
// when the selected interrupt commits, using its transported cause ID.
module irq_arbiter (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [12:0] pend_i,
    input  wire [31:0] mie_i,
    input  wire        mstatus_mie_i,
    input  wire [1:0]  mintprio_i,
    input  wire        wb_commit_i,
    input  wire [4:0]  wb_trap_cause_i,
    output wire        irq_pending_o,
    output wire [4:0]  irq_id_o,
    output wire [1:0]  irq_class_o
);
    wire [12:0] active = pend_i & {mie_i[27:16], mie_i[7]} &
                         {13{mstatus_mie_i}};

    // Pointer denotes the first candidate in the cyclic search.
    reg [1:0] rr_ptr_c1; // 0: 19, 1: 18, 2: 27
    reg       rr_ptr_c0; // 0: 17, 1: 16
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rr_ptr_c1 <= 2'd0;
            rr_ptr_c0 <= 1'b0;
        end else if (wb_commit_i) begin
            case (wb_trap_cause_i)
                5'd19: rr_ptr_c1 <= 2'd1;
                5'd18: rr_ptr_c1 <= 2'd2;
                5'd27: rr_ptr_c1 <= 2'd0;
                5'd17: rr_ptr_c0 <= 1'b1;
                5'd16: rr_ptr_c0 <= 1'b0;
                default: ;
            endcase
        end
    end

    reg c1_valid;
    reg [4:0] c1_id;
    always @(*) begin
        c1_valid = 1'b1;
        c1_id = 5'd0;
        case (rr_ptr_c1)
            2'd0: begin
                if      (active[4])  c1_id = 5'd19;
                else if (active[3])  c1_id = 5'd18;
                else if (active[12]) c1_id = 5'd27;
                else c1_valid = 1'b0;
            end
            2'd1: begin
                if      (active[3])  c1_id = 5'd18;
                else if (active[12]) c1_id = 5'd27;
                else if (active[4])  c1_id = 5'd19;
                else c1_valid = 1'b0;
            end
            default: begin
                if      (active[12]) c1_id = 5'd27;
                else if (active[4])  c1_id = 5'd19;
                else if (active[3])  c1_id = 5'd18;
                else c1_valid = 1'b0;
            end
        endcase
    end

    reg winner_valid;
    reg [4:0] winner_id;
    reg [1:0] winner_class;
    always @(*) begin
        winner_valid = 1'b1;
        winner_class = 2'd2;
        if      (active[0])  winner_id = 5'd7;
        else if (active[7])  winner_id = 5'd22;
        else if (active[9])  winner_id = 5'd24;
        else if (active[11]) winner_id = 5'd26;
        else if (active[5])  winner_id = 5'd20;
        else if (active[6])  winner_id = 5'd21;
        else if (active[8])  winner_id = 5'd23;
        else if (active[10]) winner_id = 5'd25;
        else if (c1_valid) begin
            winner_class = 2'd1;
            winner_id = c1_id;
        end else if (active[2] || active[1]) begin
            winner_class = 2'd0;
            if (rr_ptr_c0 == 1'b0)
                winner_id = active[2] ? 5'd17 : 5'd16;
            else
                winner_id = active[1] ? 5'd16 : 5'd17;
        end else begin
            winner_valid = 1'b0;
            winner_class = 2'd0;
            winner_id = 5'd0;
        end
    end

    assign irq_pending_o = winner_valid &&
                           (({1'b0, winner_class} + 3'd1) > {1'b0, mintprio_i});
    assign irq_id_o = winner_id;
    assign irq_class_o = winner_class;
endmodule
