`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: irq_arbiter
// Description:
//   Two-Level Priority Class Interrupt Arbiter for RISCFORGE RV32IM Core.
//
//   Hierarchical Architecture:
//     - Class 2 (Real-Time): Watchdog (mcause 27) > Timer0 (mcause 7) [Strict Fixed Priority]
//     - Class 1 (Stream):    UART (mcause 19) <-> SPI (mcause 18)    [Intra-Class Round-Robin]
//     - Class 0 (Background): I2C (mcause 17) <-> GPIO (mcause 16)   [Intra-Class Round-Robin]
//
//   Anti-Starvation & Preemption:
//     - Inter-class fixed priority: Class 2 > Class 1 > Class 0.
//     - Intra-class round-robin ensures fair alternating throughput under high traffic.
//     - Hardware preemption threshold: irq_pending_o asserted if in main thread
//       (nest_depth_i == 0) or if winning class > cur_class_i during active ISR.
//     - Round-robin pointers advance strictly on Writeback commit to prevent
//       speculative pointer drift on pipeline flushes.
//////////////////////////////////////////////////////////////////////////////////

module irq_arbiter (
    input  wire        clk_i,
    input  wire        rst_ni,

    // Qualified pending vector from irq_gateway
    // [5]: Watchdog (mcause 27, Class 2)
    // [4]: Timer0   (mcause 7,  Class 2)
    // [3]: UART     (mcause 19, Class 1)
    // [2]: SPI      (mcause 18, Class 1)
    // [1]: I2C      (mcause 17, Class 0)
    // [0]: GPIO     (mcause 16, Class 0)
    input  wire [5:0]  pend_i,

    // CSR sidebands
    input  wire [31:0] mie_i,
    input  wire        mstatus_mie_i,
    input  wire [1:0]  cur_class_i,
    input  wire [1:0]  nest_depth_i,

    // Commit feedback from Writeback stage
    input  wire        wb_commit_i,
    input  wire [4:0]  wb_trap_cause_i,

    // Outputs to Execute stage
    output wire        irq_pending_o,
    output wire [4:0]  irq_id_o,
    output wire [1:0]  irq_class_o
);

    // -------------------------------------------------------------------------
    // Step 1: Qualify active vector with mie mask and global MIE
    // -------------------------------------------------------------------------
    wire [5:0] active;
    assign active[5] = pend_i[5] & mie_i[27] & mstatus_mie_i; // Watchdog
    assign active[4] = pend_i[4] & mie_i[7]  & mstatus_mie_i; // Timer0
    assign active[3] = pend_i[3] & mie_i[19] & mstatus_mie_i; // UART
    assign active[2] = pend_i[2] & mie_i[18] & mstatus_mie_i; // SPI
    assign active[1] = pend_i[1] & mie_i[17] & mstatus_mie_i; // I2C
    assign active[0] = pend_i[0] & mie_i[16] & mstatus_mie_i; // GPIO

    // -------------------------------------------------------------------------
    // Step 2: Round-Robin Pointers (updated on WB commit only)
    // -------------------------------------------------------------------------
    reg rr_ptr_c1; // 0: UART preferred, 1: SPI preferred
    reg rr_ptr_c0; // 0: I2C preferred,  1: GPIO preferred

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rr_ptr_c1 <= 1'b0;
            rr_ptr_c0 <= 1'b0;
        end else if (wb_commit_i) begin
            // Class 1 commit rotation
            if (wb_trap_cause_i == 5'd19) begin
                rr_ptr_c1 <= 1'b1; // UART served -> SPI next
            end else if (wb_trap_cause_i == 5'd18) begin
                rr_ptr_c1 <= 1'b0; // SPI served -> UART next
            end

            // Class 0 commit rotation
            if (wb_trap_cause_i == 5'd17) begin
                rr_ptr_c0 <= 1'b1; // I2C served -> GPIO next
            end else if (wb_trap_cause_i == 5'd16) begin
                rr_ptr_c0 <= 1'b0; // GPIO served -> I2C next
            end
        end
    end

    // -------------------------------------------------------------------------
    // Step 3: Intra-Class Candidate Selection
    // -------------------------------------------------------------------------
    // Class 2: Strict Fixed Priority (WD > Timer0)
    wire       c2_active = active[5] | active[4];
    wire [4:0] c2_winner = active[5] ? 5'd27 : 5'd7;

    // Class 1: Round-Robin (UART <-> SPI)
    wire       c1_active = active[3] | active[2];
    reg  [4:0] c1_winner;
    always @(*) begin
        case ({active[3], active[2]})
            2'b11:   c1_winner = (rr_ptr_c1 == 1'b0) ? 5'd19 : 5'd18;
            2'b10:   c1_winner = 5'd19;
            2'b01:   c1_winner = 5'd18;
            default: c1_winner = 5'd0;
        endcase
    end

    // Class 0: Round-Robin (I2C <-> GPIO)
    wire       c0_active = active[1] | active[0];
    reg  [4:0] c0_winner;
    always @(*) begin
        case ({active[1], active[0]})
            2'b11:   c0_winner = (rr_ptr_c0 == 1'b0) ? 5'd17 : 5'd16;
            2'b10:   c0_winner = 5'd17;
            2'b01:   c0_winner = 5'd16;
            default: c0_winner = 5'd0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Step 4: Inter-Class Fixed Priority Arbitration (Class 2 > Class 1 > Class 0)
    // -------------------------------------------------------------------------
    reg       raw_winner_valid;
    reg [1:0] raw_winner_class;
    reg [4:0] raw_winner_id;

    always @(*) begin
        if (c2_active) begin
            raw_winner_valid = 1'b1;
            raw_winner_class = 2'd2;
            raw_winner_id    = c2_winner;
        end else if (c1_active) begin
            raw_winner_valid = 1'b1;
            raw_winner_class = 2'd1;
            raw_winner_id    = c1_winner;
        end else if (c0_active) begin
            raw_winner_valid = 1'b1;
            raw_winner_class = 2'd0;
            raw_winner_id    = c0_winner;
        end else begin
            raw_winner_valid = 1'b0;
            raw_winner_class = 2'd0;
            raw_winner_id    = 5'd0;
        end
    end

    // -------------------------------------------------------------------------
    // Step 5: Hardware Preemption Gating
    // Allow interrupt if in main thread (nest_depth_i == 0) or if winning class > cur_class_i
    // -------------------------------------------------------------------------
    wire preempt_allowed = (nest_depth_i == 2'd0) || (raw_winner_class > cur_class_i);
    assign irq_pending_o = raw_winner_valid && preempt_allowed;
    assign irq_id_o      = raw_winner_id;
    assign irq_class_o   = raw_winner_class;

endmodule
