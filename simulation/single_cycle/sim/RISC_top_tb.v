`timescale 1ns / 1ps
`include "RISC_top.v"

// ============================================================================
// RV32I Single-Cycle Core — Testbench with Halt Detection
// ============================================================================
// Features:
//   - Configurable timeout (MAX_CYCLES)
//   - Automatic halt detection (PC stuck in a loop)
//   - Full register file dump on completion
//   - VCD waveform generation
// ============================================================================

module RISC_top_tb();

    // ===================== PARAMETERS =====================
    parameter MAX_CYCLES   = 2000;    // Timeout: max clock cycles
    parameter HALT_THRESH  = 4;       // # of same-PC cycles to declare halt

    // ===================== SIGNALS ========================
    reg clk, rst;

    // Debug outputs from DUT
    wire [31:0] PC_next1, PC1;
    wire [31:0] A_i1, RD_i1;
    wire [31:0] A11, A21, A31, WD31, RD11, RD21, WE31;
    wire [31:0] operand11, operand21, alu_result1;
    wire [31:0] alu_r1;
    wire [3:0]  ctrl1, flags1;
    wire        ALUSrc1;
    wire        WE1;
    wire [31:0] A_d1, WD_d1, RD_d1;
    wire [3:0]  strobe1;
    wire [31:0] pc_plus1;
    wire        PCSrc1;
    wire [31:0] Imm_Ext1;
    wire [1:0]  ImmSrc1;
    wire        LUISrc1;
    wire        isLUI1;
    wire        isJALR1;
    wire [31:0] pc_target_jb1;
    wire [31:0] lui_result1;
    wire [31:0] result1;
    wire [1:0]  ResultSrc1;
    wire [31:0] in_l1, out_l1;

    // ===================== DUT INSTANTIATION =====================
    RISC_top dut (
        .rst(rst), .clk(clk),
        .PC_next1(PC_next1), .PC1(PC1),
        .A_i1(A_i1), .RD_i1(RD_i1),
        .A11(A11), .A21(A21), .A31(A31),
        .WD31(WD31), .RD11(RD11), .RD21(RD21), .WE31(WE31),
        .operand11(operand11), .operand21(operand21),
        .alu_result1(alu_result1), .alu_r1(alu_r1),
        .ctrl1(ctrl1), .flags1(flags1), .ALUSrc1(ALUSrc1),
        .WE1(WE1), .A_d1(A_d1), .WD_d1(WD_d1), .RD_d1(RD_d1),
        .strobe1(strobe1),
        .pc_plus1(pc_plus1), .PCSrc1(PCSrc1),
        .Imm_Ext1(Imm_Ext1), .ImmSrc1(ImmSrc1),
        .LUISrc1(LUISrc1), .isLUI1(isLUI1),
        .isJALR1(isJALR1), .pc_target_jb1(pc_target_jb1),
        .lui_result1(lui_result1),
        .result1(result1), .ResultSrc1(ResultSrc1),
        .in_l1(in_l1), .out_l1(out_l1)
    );

    // ===================== CLOCK GENERATION =====================
    initial clk = 1'b1;
    always #5 clk = ~clk;  // 100 MHz clock (10ns period)

    // ===================== HALT DETECTION =====================
    reg [31:0] prev_pc;
    integer    halt_count;
    integer    cycle_count;
    reg        halted;

    initial begin
        prev_pc    = 32'hFFFFFFFF;
        halt_count = 0;
        cycle_count = 0;
        halted     = 0;
    end

    always @(posedge clk) begin
        if (rst) begin
            cycle_count <= cycle_count + 1;

            // Detect halt: PC not changing for HALT_THRESH cycles
            if (PC1 == prev_pc) begin
                halt_count <= halt_count + 1;
                if (halt_count >= HALT_THRESH && !halted) begin
                    halted <= 1;
                    $display("");
                    $display("============================================================");
                    $display("  PROGRAM HALTED at PC = 0x%08h  (cycle %0d)", PC1, cycle_count);
                    $display("  Halt instruction: 0x%08h", RD_i1);
                    $display("============================================================");
                    dump_registers;
                    dump_data_memory;
                    #20 $finish;
                end
            end else begin
                halt_count <= 0;
            end

            prev_pc <= PC1;

            // Timeout protection
            if (cycle_count >= MAX_CYCLES) begin
                $display("");
                $display("!!! TIMEOUT: %0d cycles exceeded without halt !!!", MAX_CYCLES);
                dump_registers;
                #10 $finish;
            end
        end
    end

    // ===================== SIMULATION CONTROL =====================
    initial begin
        $dumpfile("build/RISC_Core.vcd");
        $dumpvars(0, RISC_top_tb);

        // Reset sequence
        rst = 1'b0;
        #32;
        rst = 1'b1;

        $display("");
        $display("============================================================");
        $display("  RV32I SINGLE-CYCLE CORE — SIMULATION STARTED");
        $display("============================================================");
        $display("  Waiting for program to halt (max %0d cycles)...", MAX_CYCLES);
        $display("");
    end

    // ===================== INSTRUCTION TRACE (optional) =====================
    // Uncomment the block below for cycle-by-cycle instruction tracing:
    //
    // always @(posedge clk) begin
    //     if (rst && !halted)
    //         $display("  [cycle %4d]  PC=0x%08h  INST=0x%08h  ALU=0x%08h  WB=0x%08h",
    //                  cycle_count, PC1, RD_i1, alu_result1, result1);
    // end

    // ===================== REGISTER DUMP =====================
    task dump_registers;
    begin
        $display("");
        $display("╔══════════════════════════════════════════════════════════╗");
        $display("║               RISC-V REGISTER FILE DUMP                ║");
        $display("╠══════════╤═══════════╤═══════════════════╤═════════════╣");
        $display("║ Reg      │ ABI Name  │ Hex Value         │ Decimal     ║");
        $display("╠══════════╪═══════════╪═══════════════════╪═════════════╣");
        $display("║ x0       │ zero      │ 0x%08h        │ %0d", dut.register_file.Register[0],  dut.register_file.Register[0]);
        $display("║ x1       │ ra        │ 0x%08h        │ %0d", dut.register_file.Register[1],  dut.register_file.Register[1]);
        $display("║ x2       │ sp        │ 0x%08h        │ %0d", dut.register_file.Register[2],  dut.register_file.Register[2]);
        $display("║ x3       │ gp        │ 0x%08h        │ %0d", dut.register_file.Register[3],  dut.register_file.Register[3]);
        $display("║ x4       │ tp        │ 0x%08h        │ %0d", dut.register_file.Register[4],  dut.register_file.Register[4]);
        $display("║ x5       │ t0        │ 0x%08h        │ %0d", dut.register_file.Register[5],  dut.register_file.Register[5]);
        $display("║ x6       │ t1        │ 0x%08h        │ %0d", dut.register_file.Register[6],  dut.register_file.Register[6]);
        $display("║ x7       │ t2        │ 0x%08h        │ %0d", dut.register_file.Register[7],  dut.register_file.Register[7]);
        $display("║ x8       │ s0/fp     │ 0x%08h        │ %0d", dut.register_file.Register[8],  dut.register_file.Register[8]);
        $display("║ x9       │ s1        │ 0x%08h        │ %0d", dut.register_file.Register[9],  dut.register_file.Register[9]);
        $display("║ x10      │ a0  ◄RET  │ 0x%08h        │ %0d", dut.register_file.Register[10], dut.register_file.Register[10]);
        $display("║ x11      │ a1        │ 0x%08h        │ %0d", dut.register_file.Register[11], dut.register_file.Register[11]);
        $display("║ x12      │ a2        │ 0x%08h        │ %0d", dut.register_file.Register[12], dut.register_file.Register[12]);
        $display("║ x13      │ a3        │ 0x%08h        │ %0d", dut.register_file.Register[13], dut.register_file.Register[13]);
        $display("║ x14      │ a4        │ 0x%08h        │ %0d", dut.register_file.Register[14], dut.register_file.Register[14]);
        $display("║ x15      │ a5        │ 0x%08h        │ %0d", dut.register_file.Register[15], dut.register_file.Register[15]);
        $display("║ x16      │ a6        │ 0x%08h        │ %0d", dut.register_file.Register[16], dut.register_file.Register[16]);
        $display("║ x17      │ a7        │ 0x%08h        │ %0d", dut.register_file.Register[17], dut.register_file.Register[17]);
        $display("║ x18      │ s2        │ 0x%08h        │ %0d", dut.register_file.Register[18], dut.register_file.Register[18]);
        $display("║ x19      │ s3        │ 0x%08h        │ %0d", dut.register_file.Register[19], dut.register_file.Register[19]);
        $display("║ x20      │ s4        │ 0x%08h        │ %0d", dut.register_file.Register[20], dut.register_file.Register[20]);
        $display("║ x21      │ s5        │ 0x%08h        │ %0d", dut.register_file.Register[21], dut.register_file.Register[21]);
        $display("║ x22      │ s6        │ 0x%08h        │ %0d", dut.register_file.Register[22], dut.register_file.Register[22]);
        $display("║ x23      │ s7        │ 0x%08h        │ %0d", dut.register_file.Register[23], dut.register_file.Register[23]);
        $display("║ x24      │ s8        │ 0x%08h        │ %0d", dut.register_file.Register[24], dut.register_file.Register[24]);
        $display("║ x25      │ s9        │ 0x%08h        │ %0d", dut.register_file.Register[25], dut.register_file.Register[25]);
        $display("║ x26      │ s10       │ 0x%08h        │ %0d", dut.register_file.Register[26], dut.register_file.Register[26]);
        $display("║ x27      │ s11       │ 0x%08h        │ %0d", dut.register_file.Register[27], dut.register_file.Register[27]);
        $display("║ x28      │ t3        │ 0x%08h        │ %0d", dut.register_file.Register[28], dut.register_file.Register[28]);
        $display("║ x29      │ t4        │ 0x%08h        │ %0d", dut.register_file.Register[29], dut.register_file.Register[29]);
        $display("║ x30      │ t5        │ 0x%08h        │ %0d", dut.register_file.Register[30], dut.register_file.Register[30]);
        $display("║ x31      │ t6        │ 0x%08h        │ %0d", dut.register_file.Register[31], dut.register_file.Register[31]);
        $display("╚══════════╧═══════════╧═══════════════════╧═════════════╝");
        $display("");
        $display("  >>> Return value (a0/x10) = %0d (0x%08h) <<<",
                 dut.register_file.Register[10], dut.register_file.Register[10]);
        $display("");
    end
    endtask

    // ===================== DATA MEMORY DUMP (first 16 words) =====================
    task dump_data_memory;
        integer j;
    begin
        $display("┌──────────────────────────────────────────┐");
        $display("│         DATA MEMORY (first 16 words)     │");
        $display("├──────────┬───────────────────────────────┤");
        for (j = 0; j < 16; j = j + 1) begin
            $display("│ [%3d]    │ 0x%08h                    │", j, dut.data_memory.mem[j]);
        end
        $display("└──────────┴───────────────────────────────┘");
    end
    endtask

endmodule
