`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_core_sanity
// Signoff Items:
//   4.10 - Core sanity TB built (I-MEM & D-MEM models, IRQ stimulus & checker)
//   4.11 - Core sanity tests pass (self-checking: arithmetic, branch, jump,
//          load, store, M ops + IRQ/MRET)
// Compatible with: Synopsys VCS, Cadence Xcelium (xrun), Icarus Verilog
////////////////////////////////////////////////////////////////////////////////

module tb_core_sanity;

    // -------------------------------------------------------------------------
    // Parameters & Memory Map
    // -------------------------------------------------------------------------
    localparam [31:0] RESET_PC      = 32'h8000_0000;
    localparam [31:0] IMEM_BASE     = 32'h8000_0000;
    localparam integer IMEM_WORDS   = 1024; // 4 KB: 0x8000_0000 .. 0x8000_0FFC
    localparam [31:0] DMEM_BASE     = 32'h8000_1000;
    localparam integer DMEM_WORDS   = 1024; // 4 KB: 0x8000_1000 .. 0x8000_1FFF

    localparam [31:0] ISR_PC        = 32'h8000_0400;
    localparam [31:0] SUB_PC        = 32'h8000_0300;
    localparam [31:0] IRQ_TRIG_ADDR = 32'h8000_1F00;
    localparam [31:0] IRQ_ACK_ADDR  = 32'h8000_1F04;
    localparam [31:0] DONE_ADDR     = 32'h8000_1FFC;
    localparam [31:0] DONE_MAGIC    = 32'h600D_C0DE;

    localparam [31:0] NOP           = 32'h0000_0013;

    // -------------------------------------------------------------------------
    // Clock & Reset
    // -------------------------------------------------------------------------
    reg clk;
    reg rst;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Core Interfaces
    // -------------------------------------------------------------------------
    wire        PCSrcE1;

    // I-MEM SRAM interface
    wire        imem_sram_en;
    wire        imem_sram_we;
    wire [3:0]  imem_sram_wmask;
    wire [29:0] imem_sram_addr;
    wire [31:0] imem_sram_wdata;
    wire [31:0] imem_sram_rdata;

    // D-MEM LSU interface
    wire        lsu_mem_req;
    wire        lsu_mem_we;
    wire [31:0] lsu_mem_addr;
    wire [31:0] lsu_mem_wdata;
    wire [3:0]  lsu_mem_be;
    reg  [31:0] lsu_mem_rdata;
    reg         lsu_mem_stall;
    reg         lsu_mem_err;

    // Interrupt inputs
    reg  [15:0] fast_irq_i;
    reg         timer_irq_i;
    reg         ext_irq_i;
    reg         sw_irq_i;

    // -------------------------------------------------------------------------
    // DUT: top (5-stage RV32IM + Zicsr core)
    // -------------------------------------------------------------------------
    top #(
        .RESET_PC    (RESET_PC),
        .FETCH_BASE0 (IMEM_BASE),
        .FETCH_END0  (IMEM_BASE + (IMEM_WORDS * 4)),
        .FETCH_BASE1 (32'h0000_0000),
        .FETCH_END1  (32'h0000_0000)
    ) dut (
        .clk             (clk),
        .rst             (rst),
        .PCSrcE1         (PCSrcE1),
        .imem_sram_en    (imem_sram_en),
        .imem_sram_we    (imem_sram_we),
        .imem_sram_wmask (imem_sram_wmask),
        .imem_sram_addr  (imem_sram_addr),
        .imem_sram_wdata (imem_sram_wdata),
        .imem_sram_rdata (imem_sram_rdata),
        .lsu_mem_req     (lsu_mem_req),
        .lsu_mem_we      (lsu_mem_we),
        .lsu_mem_addr    (lsu_mem_addr),
        .lsu_mem_wdata   (lsu_mem_wdata),
        .lsu_mem_be      (lsu_mem_be),
        .lsu_mem_rdata   (lsu_mem_rdata),
        .lsu_mem_stall   (lsu_mem_stall),
        .lsu_mem_err     (lsu_mem_err),
        .fast_irq_i      (fast_irq_i),
        .timer_irq_i     (timer_irq_i),
        .ext_irq_i       (ext_irq_i),
        .sw_irq_i        (sw_irq_i)
    );

    // -------------------------------------------------------------------------
    // I-MEM Behavioral Model (1-cycle synchronous read latency matching imem_controller)
    // -------------------------------------------------------------------------
    reg [31:0] imem [0:IMEM_WORDS-1];
    reg [29:0] imem_raddr_q;

    wire [29:0] imem_base_word = IMEM_BASE[31:2];
    wire        imem_addr_ok   = (imem_raddr_q >= imem_base_word) &&
                                 (imem_raddr_q < (imem_base_word + IMEM_WORDS));

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            imem_raddr_q <= RESET_PC[31:2];
        end else if (imem_sram_en) begin
            imem_raddr_q <= imem_sram_addr;
        end
    end

    assign imem_sram_rdata = imem_addr_ok ? imem[imem_raddr_q - imem_base_word] : NOP;

    // -------------------------------------------------------------------------
    // D-MEM Behavioral Model (1-cycle read stall, byte-masked write, error on OOB)
    // -------------------------------------------------------------------------
    reg [31:0] dmem [0:DMEM_WORDS-1];
    reg        dmem_wait_q;
    reg [31:0] dmem_rdata_q;
    reg        done_seen;

    wire        dmem_addr_ok = (lsu_mem_addr >= DMEM_BASE) &&
                               (lsu_mem_addr < (DMEM_BASE + (DMEM_WORDS * 4)));
    wire [9:0]  dmem_word_idx = lsu_mem_addr[11:2];

    always @(*) begin
        lsu_mem_stall = 1'b0;
        lsu_mem_err   = 1'b0;
        lsu_mem_rdata = dmem_rdata_q;

        if (lsu_mem_req) begin
            if (!dmem_addr_ok) begin
                lsu_mem_err = 1'b1;
            end else if (!lsu_mem_we && !dmem_wait_q) begin
                // Cycle 0 of synchronous read: stall pipeline for 1 cycle while latching word
                lsu_mem_stall = 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            dmem_wait_q  <= 1'b0;
            dmem_rdata_q <= 32'h0000_0000;
            done_seen    <= 1'b0;
        end else begin
            if (lsu_mem_req && dmem_addr_ok) begin
                if (lsu_mem_we) begin
                    // Byte-lane masked store
                    if (lsu_mem_be[0]) dmem[dmem_word_idx][7:0]   <= lsu_mem_wdata[7:0];
                    if (lsu_mem_be[1]) dmem[dmem_word_idx][15:8]  <= lsu_mem_wdata[15:8];
                    if (lsu_mem_be[2]) dmem[dmem_word_idx][23:16] <= lsu_mem_wdata[23:16];
                    if (lsu_mem_be[3]) dmem[dmem_word_idx][31:24] <= lsu_mem_wdata[31:24];
                    dmem_wait_q <= 1'b0;

                    if (lsu_mem_addr == DONE_ADDR && lsu_mem_wdata == DONE_MAGIC)
                        done_seen <= 1'b1;
                end else if (!dmem_wait_q) begin
                    // Latch read data for next cycle
                    dmem_rdata_q <= dmem[dmem_word_idx];
                    dmem_wait_q  <= 1'b1;
                end else begin
                    dmem_wait_q  <= 1'b0;
                end
            end else begin
                dmem_wait_q <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // IRQ Stimulus & Protocol Checker (4.10)
    // -------------------------------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;
    integer bus_err_cnt = 0;
    integer irq_trap_cnt = 0;
    integer mret_cnt = 0;
    reg [30:0] seen_irq_causes [0:7];

    task automatic check_eq(input [31:0] actual, input [31:0] expected, input string msg);
        begin
            if (actual !== expected) begin
                $display("[FAIL] %s | got=0x%08h exp=0x%08h", msg, actual, expected);
                fail_cnt = fail_cnt + 1;
            end else begin
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    // Monitor I-MEM, D-MEM, and IRQ/MRET protocol events
    always @(posedge clk) begin
        if (rst) begin
            // I-MEM protocol check: fetch path must never assert writes
            if (imem_sram_en && (imem_sram_we !== 1'b0 || imem_sram_wmask !== 4'b0000)) begin
                $display("[FAIL] %0t | I-MEM write asserted during fetch: we=%b wmask=%4b",
                         $time, imem_sram_we, imem_sram_wmask);
                bus_err_cnt = bus_err_cnt + 1;
            end

            // D-MEM protocol check: no X addresses/strobes, no unexpected OOB faults
            if (lsu_mem_req) begin
                if (^lsu_mem_addr === 1'bx || ^lsu_mem_be === 1'bx) begin
                    $display("[FAIL] %0t | D-MEM request has X addr/be: addr=0x%08h be=%4b",
                             $time, lsu_mem_addr, lsu_mem_be);
                    bus_err_cnt = bus_err_cnt + 1;
                end
                if (!dmem_addr_ok) begin
                    $display("[FAIL] %0t | Unexpected out-of-range D-MEM access: addr=0x%08h we=%b",
                             $time, lsu_mem_addr, lsu_mem_we);
                    bus_err_cnt = bus_err_cnt + 1;
                end
            end

            // Mailbox-driven IRQ stimulus:
            //   1 -> assert external IRQ (MEIP, cause 11)
            //   2 -> assert timer IRQ (MTIP, cause 7)
            if (lsu_mem_req && lsu_mem_we && lsu_mem_addr == IRQ_TRIG_ADDR) begin
                if (lsu_mem_wdata == 32'd1) begin
                    ext_irq_i <= 1'b1;
                    $display("[INFO] %0t | IRQ Stimulus: asserted ext_irq_i (MEIP, cause 11)", $time);
                end else if (lsu_mem_wdata == 32'd2) begin
                    timer_irq_i <= 1'b1;
                    $display("[INFO] %0t | IRQ Stimulus: asserted timer_irq_i (MTIP, cause 7)", $time);
                end
            end

            // ISR clears pending interrupt via IRQ_ACK_ADDR before executing MRET
            if (lsu_mem_req && lsu_mem_we && lsu_mem_addr == IRQ_ACK_ADDR) begin
                ext_irq_i   <= 1'b0;
                timer_irq_i <= 1'b0;
                sw_irq_i    <= 1'b0;
                fast_irq_i  <= 16'h0000;
            end

            // IRQ commit checker
            if (dut.trap_commit_valid) begin
                if (dut.trap_commit_is_interrupt) begin
                    if (dut.trap_target !== ISR_PC) begin
                        $display("[FAIL] %0t | IRQ trap_target=0x%08h (exp 0x%08h)",
                                 $time, dut.trap_target, ISR_PC);
                        fail_cnt = fail_cnt + 1;
                    end else begin
                        pass_cnt = pass_cnt + 1;
                    end
                    if (dut.trap_commit_pc < IMEM_BASE || dut.trap_commit_pc >= ISR_PC) begin
                        $display("[FAIL] %0t | IRQ mepc out of main program range: 0x%08h",
                                 $time, dut.trap_commit_pc);
                        fail_cnt = fail_cnt + 1;
                    end else begin
                        pass_cnt = pass_cnt + 1;
                    end
                    if (irq_trap_cnt < 8)
                        seen_irq_causes[irq_trap_cnt] = dut.trap_commit_cause;
                    irq_trap_cnt = irq_trap_cnt + 1;
                    $display("[INFO] %0t | IRQ Checker: interrupt committed cause=%0d mepc=0x%08h -> mtvec=0x%08h",
                             $time, dut.trap_commit_cause, dut.trap_commit_pc, dut.trap_target);
                end else begin
                    $display("[FAIL] %0t | Unexpected synchronous exception cause=%0d pc=0x%08h tval=0x%08h",
                             $time, dut.trap_commit_cause, dut.trap_commit_pc, dut.trap_commit_addr);
                    fail_cnt = fail_cnt + 1;
                end
            end

            // MRET commit checker
            if (dut.mret_commit) begin
                mret_cnt = mret_cnt + 1;
                if (dut.trap_target < IMEM_BASE || dut.trap_target >= ISR_PC) begin
                    $display("[FAIL] %0t | MRET return target=0x%08h out of range",
                             $time, dut.trap_target);
                    fail_cnt = fail_cnt + 1;
                end else begin
                    pass_cnt = pass_cnt + 1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // RV32IM + Zicsr Minimal Assembler Helpers
    // -------------------------------------------------------------------------
    function automatic [31:0] enc_r(
        input [6:0] funct7, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3, input [4:0] rd,  input [6:0] opcode
    );
        enc_r = {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic [31:0] enc_i(
        input integer imm, input [4:0] rs1,
        input [2:0] funct3, input [4:0] rd, input [6:0] opcode
    );
        reg [11:0] imm12;
        begin
            imm12 = imm[11:0];
            enc_i = {imm12, rs1, funct3, rd, opcode};
        end
    endfunction

    function automatic [31:0] enc_s(
        input integer imm, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3, input [6:0] opcode
    );
        reg [11:0] imm12;
        begin
            imm12 = imm[11:0];
            enc_s = {imm12[11:5], rs2, rs1, funct3, imm12[4:0], opcode};
        end
    endfunction

    function automatic [31:0] enc_b(
        input integer imm, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3
    );
        reg [12:0] imm13;
        begin
            imm13 = imm[12:0];
            enc_b = {imm13[12], imm13[10:5], rs2, rs1, funct3, imm13[4:1], imm13[11], 7'b1100011};
        end
    endfunction

    function automatic [31:0] enc_u(
        input [19:0] imm20, input [4:0] rd, input [6:0] opcode
    );
        enc_u = {imm20, rd, opcode};
    endfunction

    function automatic [31:0] enc_j(
        input integer imm, input [4:0] rd
    );
        reg [20:0] imm21;
        begin
            imm21 = imm[20:0];
            enc_j = {imm21[20], imm21[10:1], imm21[11], imm21[19:12], rd, 7'b1101111};
        end
    endfunction

    function automatic [31:0] enc_csr(
        input [11:0] csr, input [4:0] rs1, input [2:0] funct3, input [4:0] rd
    );
        enc_csr = {csr, rs1, funct3, rd, 7'b1110011};
    endfunction

    // Emit instruction sequentially at byte cursor `pc_cur`
    reg [31:0] pc_cur;
    reg [31:0] expected_auipc_val;
    reg [31:0] expected_jal_ra;

    task automatic emit(input [31:0] instr);
        begin
            imem[(pc_cur - IMEM_BASE) >> 2] = instr;
            pc_cur = pc_cur + 4;
        end
    endtask

    // Assemble the self-checking program covering all 6 instruction classes + IRQ
    task automatic build_sanity_program;
        integer idx;
        reg [31:0] sub_target_pc;
        begin
            for (idx = 0; idx < IMEM_WORDS; idx = idx + 1)
                imem[idx] = NOP;
            for (idx = 0; idx < DMEM_WORDS; idx = idx + 1)
                dmem[idx] = 32'h0000_0000;

            pc_cur = RESET_PC;

            // Base registers:
            //   x31 = 0x8000_1000 (D-MEM result/scratch base)
            //   x30 = 0x8000_2000 (Mailbox base: -256=TRIG, -252=ACK, -4=DONE)
            emit(enc_u(20'h80001, 5'd31, 7'b0110111)); // LUI x31, 0x80001
            emit(enc_u(20'h80002, 5'd30, 7'b0110111)); // LUI x30, 0x80002

            // =================================================================
            // CLASS 1: ARITHMETIC (ADDI, ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU, LUI, AUIPC)
            // =================================================================
            emit(enc_i(100,  5'd0, 3'b000, 5'd1, 7'b0010011));           // ADDI x1, x0, 100
            emit(enc_i(-25,  5'd0, 3'b000, 5'd2, 7'b0010011));           // ADDI x2, x0, -25
            emit(enc_r(7'h00, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011));    // ADD  x3, x1, x2 (= 75)
            emit(enc_s(0,    5'd3, 5'd31, 3'b010, 7'b0100011));          // SW   x3, 0(x31)

            emit(enc_i(25,   5'd0, 3'b000, 5'd2, 7'b0010011));           // ADDI x2, x0, 25
            emit(enc_r(7'h20, 5'd1, 5'd2, 3'b000, 5'd3, 7'b0110011));    // SUB  x3, x2, x1 (= -75 = 0xFFFFFFB5)
            emit(enc_s(4,    5'd3, 5'd31, 3'b010, 7'b0100011));          // SW   x3, 4(x31)

            // AND: 0xF0F00F0F & 0x0FF0FF00 = 0x00F00F00
            emit(enc_u(20'hF0F01, 5'd1, 7'b0110111));                    // LUI  x1, 0xF0F01
            emit(enc_i(-241, 5'd1, 3'b000, 5'd1, 7'b0010011));           // ADDI x1, x1, -241 -> 0xF0F00F0F
            emit(enc_u(20'h0FF10, 5'd2, 7'b0110111));                    // LUI  x2, 0x0FF10
            emit(enc_i(-256, 5'd2, 3'b000, 5'd2, 7'b0010011));           // ADDI x2, x2, -256 -> 0x0FF0FF00
            emit(enc_r(7'h00, 5'd2, 5'd1, 3'b111, 5'd3, 7'b0110011));    // AND  x3, x1, x2
            emit(enc_s(8,    5'd3, 5'd31, 3'b010, 7'b0100011));          // SW   x3, 8(x31)

            // OR: 0x12340000 | 0x00005678 = 0x12345678
            emit(enc_u(20'h12340, 5'd1, 7'b0110111));                    // LUI  x1, 0x12340
            emit(enc_u(20'h00005, 5'd2, 7'b0110111));                    // LUI  x2, 0x00005
            emit(enc_i(32'h678, 5'd2, 3'b000, 5'd2, 7'b0010011));        // ADDI x2, x2, 0x678
            emit(enc_r(7'h00, 5'd2, 5'd1, 3'b110, 5'd3, 7'b0110011));    // OR   x3, x1, x2
            emit(enc_s(12,   5'd3, 5'd31, 3'b010, 7'b0100011));          // SW   x3, 12(x31)

            // XOR: 0xAAAA5555 ^ 0xFFFF0000 = 0x55555555
            emit(enc_u(20'hAAAA5, 5'd1, 7'b0110111));
            emit(enc_i(32'h555, 5'd1, 3'b000, 5'd1, 7'b0010011));        // x1 = 0xAAAA5555
            emit(enc_u(20'hFFFF0, 5'd2, 7'b0110111));                    // x2 = 0xFFFF0000
            emit(enc_r(7'h00, 5'd2, 5'd1, 3'b100, 5'd3, 7'b0110011));    // XOR  x3, x1, x2
            emit(enc_s(16,   5'd3, 5'd31, 3'b010, 7'b0100011));          // SW   x3, 16(x31)

            // SLL, SRL, SRA
            emit(enc_i(1,    5'd0, 3'b000, 5'd1, 7'b0010011));           // ADDI x1, x0, 1
            emit(enc_i(16,   5'd1, 3'b001, 5'd3, 7'b0010011));           // SLLI x3, x1, 16 (= 0x00010000)
            emit(enc_s(20,   5'd3, 5'd31, 3'b010, 7'b0100011));          // SW   x3, 20(x31)

            emit(enc_u(20'h80000, 5'd1, 7'b0110111));                    // LUI  x1, 0x80000
            emit(enc_i(4,    5'd0, 3'b000, 5'd2, 7'b0010011));           // ADDI x2, x0, 4
            emit(enc_r(7'h00, 5'd2, 5'd1, 3'b101, 5'd3, 7'b0110011));    // SRL  x3, x1, x2 (= 0x08000000)
            emit(enc_s(24,   5'd3, 5'd31, 3'b010, 7'b0100011));          // SW   x3, 24(x31)
            emit(enc_r(7'h20, 5'd2, 5'd1, 3'b101, 5'd3, 7'b0110011));    // SRA  x3, x1, x2 (= 0xF8000000)
            emit(enc_s(28,   5'd3, 5'd31, 3'b010, 7'b0100011));          // SW   x3, 28(x31)

            // SLT / SLTU (-1 vs +1)
            emit(enc_i(-1,   5'd0, 3'b000, 5'd1, 7'b0010011));           // ADDI x1, x0, -1
            emit(enc_i(1,    5'd0, 3'b000, 5'd2, 7'b0010011));           // ADDI x2, x0, 1
            emit(enc_r(7'h00, 5'd2, 5'd1, 3'b010, 5'd3, 7'b0110011));    // SLT  x3, x1, x2 (= 1)
            emit(enc_s(32,   5'd3, 5'd31, 3'b010, 7'b0100011));          // SW   x3, 32(x31)
            emit(enc_r(7'h00, 5'd2, 5'd1, 3'b011, 5'd3, 7'b0110011));    // SLTU x3, x1, x2 (= 0)
            emit(enc_s(36,   5'd3, 5'd31, 3'b010, 7'b0100011));          // SW   x3, 36(x31)

            // LUI / AUIPC
            emit(enc_u(20'h12345, 5'd3, 7'b0110111));                    // LUI  x3, 0x12345
            emit(enc_s(40,   5'd3, 5'd31, 3'b010, 7'b0100011));          // SW   x3, 40(x31)
            expected_auipc_val = pc_cur + 32'h0000_1000;
            emit(enc_u(20'h00001, 5'd3, 7'b0010111));                    // AUIPC x3, 1
            emit(enc_s(44,   5'd3, 5'd31, 3'b010, 7'b0100011));          // SW   x3, 44(x31)

            // =================================================================
            // CLASS 2: BRANCH (BEQ, BNE, BLT, BGE, BLTU, BGEU - taken & not-taken)
            // =================================================================
            emit(enc_i(0,  5'd0, 3'b000, 5'd20, 7'b0010011)); // x20 = 0 (pass counter, expect 12)
            emit(enc_i(-1, 5'd0, 3'b000, 5'd1,  7'b0010011)); // x1 = -1 (0xFFFFFFFF)
            emit(enc_i(1,  5'd0, 3'b000, 5'd2,  7'b0010011)); // x2 = +1
            emit(enc_i(1,  5'd0, 3'b000, 5'd3,  7'b0010011)); // x3 = +1

            // 1) BEQ taken (x2 == x3): skip poison
            emit(enc_b(8, 5'd3, 5'd2, 3'b000));
            emit(enc_i(256, 5'd20, 3'b110, 5'd20, 7'b0010011)); // poison: ORI x20, 0x100
            emit(enc_i(1,   5'd20, 3'b000, 5'd20, 7'b0010011)); // pass +1

            // 2) BEQ not taken (x1 == x2 false)
            emit(enc_b(8, 5'd2, 5'd1, 3'b000));
            emit(enc_i(1,   5'd20, 3'b000, 5'd20, 7'b0010011)); // pass +1 (must execute)
            emit(enc_b(8, 5'd0, 5'd0, 3'b000));                 // skip next poison
            emit(enc_i(256, 5'd20, 3'b110, 5'd20, 7'b0010011));

            // 3) BNE taken (x1 != x2)
            emit(enc_b(8, 5'd2, 5'd1, 3'b001));
            emit(enc_i(256, 5'd20, 3'b110, 5'd20, 7'b0010011));
            emit(enc_i(1,   5'd20, 3'b000, 5'd20, 7'b0010011)); // pass +1

            // 4) BNE not taken (x2 != x3 false)
            emit(enc_b(8, 5'd3, 5'd2, 3'b001));
            emit(enc_i(1,   5'd20, 3'b000, 5'd20, 7'b0010011)); // pass +1
            emit(enc_b(8, 5'd0, 5'd0, 3'b000));
            emit(enc_i(256, 5'd20, 3'b110, 5'd20, 7'b0010011));

            // 5) BLT taken (-1 < +1 signed)
            emit(enc_b(8, 5'd2, 5'd1, 3'b100));
            emit(enc_i(256, 5'd20, 3'b110, 5'd20, 7'b0010011));
            emit(enc_i(1,   5'd20, 3'b000, 5'd20, 7'b0010011)); // pass +1

            // 6) BLT not taken (+1 < -1 signed false)
            emit(enc_b(8, 5'd1, 5'd2, 3'b100));
            emit(enc_i(1,   5'd20, 3'b000, 5'd20, 7'b0010011)); // pass +1
            emit(enc_b(8, 5'd0, 5'd0, 3'b000));
            emit(enc_i(256, 5'd20, 3'b110, 5'd20, 7'b0010011));

            // 7) BGE taken (+1 >= -1 signed)
            emit(enc_b(8, 5'd1, 5'd2, 3'b101));
            emit(enc_i(256, 5'd20, 3'b110, 5'd20, 7'b0010011));
            emit(enc_i(1,   5'd20, 3'b000, 5'd20, 7'b0010011)); // pass +1

            // 8) BGE not taken (-1 >= +1 signed false)
            emit(enc_b(8, 5'd2, 5'd1, 3'b101));
            emit(enc_i(1,   5'd20, 3'b000, 5'd20, 7'b0010011)); // pass +1
            emit(enc_b(8, 5'd0, 5'd0, 3'b000));
            emit(enc_i(256, 5'd20, 3'b110, 5'd20, 7'b0010011));

            // 9) BLTU taken (1 < 0xFFFFFFFF unsigned)
            emit(enc_b(8, 5'd1, 5'd2, 3'b110));
            emit(enc_i(256, 5'd20, 3'b110, 5'd20, 7'b0010011));
            emit(enc_i(1,   5'd20, 3'b000, 5'd20, 7'b0010011)); // pass +1

            // 10) BLTU not taken (0xFFFFFFFF < 1 unsigned false)
            emit(enc_b(8, 5'd2, 5'd1, 3'b110));
            emit(enc_i(1,   5'd20, 3'b000, 5'd20, 7'b0010011)); // pass +1
            emit(enc_b(8, 5'd0, 5'd0, 3'b000));
            emit(enc_i(256, 5'd20, 3'b110, 5'd20, 7'b0010011));

            // 11) BGEU taken (0xFFFFFFFF >= 1 unsigned)
            emit(enc_b(8, 5'd2, 5'd1, 3'b111));
            emit(enc_i(256, 5'd20, 3'b110, 5'd20, 7'b0010011));
            emit(enc_i(1,   5'd20, 3'b000, 5'd20, 7'b0010011)); // pass +1

            // 12) BGEU not taken (1 >= 0xFFFFFFFF unsigned false)
            emit(enc_b(8, 5'd1, 5'd2, 3'b111));
            emit(enc_i(1,   5'd20, 3'b000, 5'd20, 7'b0010011)); // pass +1
            emit(enc_b(8, 5'd0, 5'd0, 3'b000));
            emit(enc_i(256, 5'd20, 3'b110, 5'd20, 7'b0010011));

            emit(enc_s(64, 5'd20, 5'd31, 3'b010, 7'b0100011)); // SW x20, 64(x31) -> slot 16

            // =================================================================
            // CLASS 3: JUMP (JAL & JALR)
            // =================================================================
            emit(enc_i(0, 5'd0, 3'b000, 5'd21, 7'b0010011));     // x21 = 0
            expected_jal_ra = pc_cur + 4;
            emit(enc_j(8, 5'd1));                                // JAL x1, +8 (skips poison)
            emit(enc_i(32'h5AD, 5'd0, 3'b000, 5'd21, 7'b0010011)); // poison (must skip)
            emit(enc_i(32'h111, 5'd21, 3'b000, 5'd21, 7'b0010011)); // x21 += 0x111
            // Save link register x1 to slot 18 for exact PC+4 check
            emit(enc_s(72, 5'd1, 5'd31, 3'b010, 7'b0100011));    // SW x1, 72(x31) -> slot 18

            // Call subroutine at SUB_PC (adds 0x222 to x21 and returns via JALR x0, 0(x1))
            emit(enc_j(SUB_PC - pc_cur, 5'd1));                  // JAL x1, SUB_PC
            emit(enc_s(68, 5'd21, 5'd31, 3'b010, 7'b0100011));   // SW x21, 68(x31) -> slot 17 (0x333)

            // =================================================================
            // CLASS 4 & 5: STORE (SW, SH, SB) & LOAD (LW, LH, LHU, LB, LBU)
            // Scratch base: x31 + 0x100 = 0x8000_1100
            // =================================================================
            emit(enc_u(20'h89ABD, 5'd1, 7'b0110111));
            emit(enc_i(-273, 5'd1, 3'b000, 5'd1, 7'b0010011));   // x1 = 0x89ABCDEF (0x89ABD000 - 0x111? 0x89ABD000 - 0x321? Wait!)
            // Use exact arithmetic: 0x89ABD000 - 0x211 = 0x89ABCDEF -> -0x211 = -529
            pc_cur = pc_cur - 4;
            emit(enc_i(-529, 5'd1, 3'b000, 5'd1, 7'b0010011));   // x1 = 0x89AB_CDEF
            emit(enc_s(32'h100, 5'd1, 5'd31, 3'b010, 7'b0100011)); // SW x1, 0x100(x31)
            emit(enc_i(32'h100, 5'd31, 3'b010, 5'd2, 7'b0000011)); // LW x2, 0x100(x31)
            emit(enc_s(80, 5'd2, 5'd31, 3'b010, 7'b0100011));      // SW x2, 80(x31) -> slot 20

            // Byte & Halfword stores into 0x8000_1104..0x8000_1107
            emit(enc_i(32'h081, 5'd0, 3'b000, 5'd1, 7'b0010011));  // x1 = 0x81
            emit(enc_s(32'h104, 5'd1, 5'd31, 3'b000, 7'b0100011)); // SB x1, 0x104(x31)
            emit(enc_i(32'h07F, 5'd0, 3'b000, 5'd1, 7'b0010011));  // x1 = 0x7F
            emit(enc_s(32'h105, 5'd1, 5'd31, 3'b000, 7'b0100011)); // SB x1, 0x105(x31)
            emit(enc_u(20'h0000F, 5'd1, 7'b0110111));
            emit(enc_i(32'h123, 5'd1, 3'b000, 5'd1, 7'b0010011));  // x1 = 0x0000F123
            emit(enc_s(32'h106, 5'd1, 5'd31, 3'b001, 7'b0100011)); // SH x1, 0x106(x31)

            // Read back with LB, LBU, LH, LHU, LW
            emit(enc_i(32'h104, 5'd31, 3'b000, 5'd2, 7'b0000011)); // LB  x2, 0x104(x31) -> 0xFFFFFF81
            emit(enc_s(84, 5'd2, 5'd31, 3'b010, 7'b0100011));      // slot 21
            emit(enc_i(32'h104, 5'd31, 3'b100, 5'd2, 7'b0000011)); // LBU x2, 0x104(x31) -> 0x00000081
            emit(enc_s(88, 5'd2, 5'd31, 3'b010, 7'b0100011));      // slot 22
            emit(enc_i(32'h106, 5'd31, 3'b001, 5'd2, 7'b0000011)); // LH  x2, 0x106(x31) -> 0xFFFFF123
            emit(enc_s(92, 5'd2, 5'd31, 3'b010, 7'b0100011));      // slot 23
            emit(enc_i(32'h106, 5'd31, 3'b101, 5'd2, 7'b0000011)); // LHU x2, 0x106(x31) -> 0x0000F123
            emit(enc_s(96, 5'd2, 5'd31, 3'b010, 7'b0100011));      // slot 24
            emit(enc_i(32'h104, 5'd31, 3'b010, 5'd2, 7'b0000011)); // LW  x2, 0x104(x31) -> 0xF1237F81
            emit(enc_s(100, 5'd2, 5'd31, 3'b010, 7'b0100011));     // slot 25

            // =================================================================
            // CLASS 6: M-EXTENSION (MUL, MULH, DIV, REM, DIVU, REMU, DIV-by-0)
            // =================================================================
            emit(enc_i(-7,  5'd0, 3'b000, 5'd1, 7'b0010011));          // x1 = -7
            emit(enc_i(6,   5'd0, 3'b000, 5'd2, 7'b0010011));          // x2 = 6
            emit(enc_r(7'h01, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011));  // MUL  x3, x1, x2 (= -42)
            emit(enc_s(112, 5'd3, 5'd31, 3'b010, 7'b0100011));         // slot 28
            emit(enc_r(7'h01, 5'd2, 5'd1, 3'b001, 5'd3, 7'b0110011));  // MULH x3, x1, x2 (= -1)
            emit(enc_s(116, 5'd3, 5'd31, 3'b010, 7'b0100011));         // slot 29

            emit(enc_i(-100, 5'd0, 3'b000, 5'd1, 7'b0010011));         // x1 = -100
            emit(enc_i(7,    5'd0, 3'b000, 5'd2, 7'b0010011));         // x2 = 7
            emit(enc_r(7'h01, 5'd2, 5'd1, 3'b100, 5'd3, 7'b0110011));  // DIV  x3, x1, x2 (= -14)
            emit(enc_s(120, 5'd3, 5'd31, 3'b010, 7'b0100011));         // slot 30
            emit(enc_r(7'h01, 5'd2, 5'd1, 3'b110, 5'd3, 7'b0110011));  // REM  x3, x1, x2 (= -2)
            emit(enc_s(124, 5'd3, 5'd31, 3'b010, 7'b0100011));         // slot 31

            emit(enc_u(20'h80000, 5'd1, 7'b0110111));                  // x1 = 0x80000000
            emit(enc_i(3,    5'd0, 3'b000, 5'd2, 7'b0010011));         // x2 = 3
            emit(enc_r(7'h01, 5'd2, 5'd1, 3'b101, 5'd3, 7'b0110011));  // DIVU x3, x1, x2 (= 0x2AAAAAAA)
            emit(enc_s(128, 5'd3, 5'd31, 3'b010, 7'b0100011));         // slot 32
            emit(enc_r(7'h01, 5'd2, 5'd1, 3'b111, 5'd3, 7'b0110011));  // REMU x3, x1, x2 (= 2)
            emit(enc_s(132, 5'd3, 5'd31, 3'b010, 7'b0100011));         // slot 33

            emit(enc_i(42,   5'd0, 3'b000, 5'd1, 7'b0010011));         // x1 = 42
            emit(enc_r(7'h01, 5'd0, 5'd1, 3'b100, 5'd3, 7'b0110011));  // DIV  x3, x1, x0 (= -1)
            emit(enc_s(136, 5'd3, 5'd31, 3'b010, 7'b0100011));         // slot 34

            // =================================================================
            // IRQ TEST: Arm mtvec, mie (MEIE|MTIE), mstatus.MIE, trigger ext & timer IRQs
            // =================================================================
            emit(enc_i(0, 5'd0, 3'b000, 5'd27, 7'b0010011));           // x27 = 0 (ISR invocation count)
            emit(enc_u(20'h80000, 5'd1, 7'b0110111));
            emit(enc_i(32'h400, 5'd1, 3'b000, 5'd1, 7'b0010011));      // x1 = 0x8000_0400 (ISR_PC)
            emit(enc_csr(12'h305, 5'd1, 3'b001, 5'd0));                // CSRRW x0, mtvec, x1

            emit(enc_u(20'h00001, 5'd1, 7'b0110111));
            emit(enc_i(-1920, 5'd1, 3'b000, 5'd1, 7'b0010011));        // 0x1000 - 0x780 = 0x0880 (MEIE|MTIE)
            emit(enc_csr(12'h304, 5'd1, 3'b001, 5'd0));                // CSRRW x0, mie, x1

            emit(enc_i(8, 5'd0, 3'b000, 5'd1, 7'b0010011));            // x1 = 0x8 (MIE)
            emit(enc_csr(12'h300, 5'd1, 3'b001, 5'd0));                // CSRRW x0, mstatus, x1

            // Trigger IRQ 1: ext_irq_i (cause 11)
            emit(enc_i(1, 5'd0, 3'b000, 5'd1, 7'b0010011));
            emit(enc_s(-256, 5'd1, 5'd30, 3'b010, 7'b0100011));        // SW x1, IRQ_TRIG_ADDR
            repeat (8) emit(NOP);

            // Trigger IRQ 2: timer_irq_i (cause 7)
            emit(enc_i(2, 5'd0, 3'b000, 5'd1, 7'b0010011));
            emit(enc_s(-256, 5'd1, 5'd30, 3'b010, 7'b0100011));        // SW x1, IRQ_TRIG_ADDR
            repeat (8) emit(NOP);

            // Signal completion & halt loop
            emit(enc_u(20'h600DC, 5'd1, 7'b0110111));
            emit(enc_i(32'h0DE, 5'd1, 3'b000, 5'd1, 7'b0010011));      // x1 = 0x600D_C0DE
            emit(enc_s(-4, 5'd1, 5'd30, 3'b010, 7'b0100011));          // SW x1, DONE_ADDR
            emit(enc_j(0, 5'd0));                                      // JAL x0, 0 (spin)

            // =================================================================
            // SUBROUTINE at SUB_PC (0x8000_0300): x21 += 0x222; JALR x0, 0(x1)
            // =================================================================
            pc_cur = SUB_PC;
            emit(enc_i(32'h222, 5'd21, 3'b000, 5'd21, 7'b0010011));    // ADDI x21, x21, 0x222
            emit(enc_i(0, 5'd1, 3'b000, 5'd0, 7'b1100111));            // JALR x0, 0(x1)

            // =================================================================
            // ISR at ISR_PC (0x8000_0400)
            //   1st entry (x27 == 0): store mcause->slot 40 (0xA0), mepc->slot 41 (0xA4)
            //   2nd entry (x27 == 1): store mcause->slot 42 (0xA8), mepc->slot 43 (0xAC)
            //   ACK IRQ via -252(x30), x27++, store x27->slot 44 (0xB0), MRET
            // =================================================================
            pc_cur = ISR_PC;
            emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd28));               // CSRRS x28, mcause, x0
            emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd29));               // CSRRS x29, mepc, x0

            emit(enc_b(16, 5'd0, 5'd27, 3'b001));                      // BNE x27, x0, +16 (2nd entry)
            emit(enc_s(160, 5'd28, 5'd31, 3'b010, 7'b0100011));        // SW x28, 160(x31) -> slot 40
            emit(enc_s(164, 5'd29, 5'd31, 3'b010, 7'b0100011));        // SW x29, 164(x31) -> slot 41
            emit(enc_j(12, 5'd0));                                     // JAL x0, +12 (skip 2nd branch)
            emit(enc_s(168, 5'd28, 5'd31, 3'b010, 7'b0100011));        // SW x28, 168(x31) -> slot 42
            emit(enc_s(172, 5'd29, 5'd31, 3'b010, 7'b0100011));        // SW x29, 172(x31) -> slot 43

            emit(enc_i(1, 5'd0, 3'b000, 5'd28, 7'b0010011));           // ADDI x28, x0, 1
            emit(enc_s(-252, 5'd28, 5'd30, 3'b010, 7'b0100011));       // SW x28, IRQ_ACK_ADDR
            emit(enc_i(1, 5'd27, 3'b000, 5'd27, 7'b0010011));          // ADDI x27, x27, 1
            emit(enc_s(176, 5'd27, 5'd31, 3'b010, 7'b0100011));        // SW x27, 176(x31) -> slot 44
            emit(NOP);
            emit(NOP);
            emit(32'h3020_0073);                                       // MRET
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Simulation & Self-Checking Verification (4.10 & 4.11)
    // -------------------------------------------------------------------------
    integer cyc;

    initial begin
`ifdef FSDB
        $fsdbDumpfile("tb_core_sanity.fsdb");
        $fsdbDumpvars(0, tb_core_sanity);
`elsif SHM
        $shm_open("tb_core_sanity.shm");
        $shm_probe("AS");
`elsif VCD
        $dumpfile("tb_core_sanity.vcd");
        $dumpvars(0, tb_core_sanity);
`endif

        rst         = 1'b0;
        fast_irq_i  = 16'h0000;
        timer_irq_i = 1'b0;
        ext_irq_i   = 1'b0;
        sw_irq_i    = 1'b0;

        build_sanity_program();

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b1;

        // Run until completion sentinel or timeout
        for (cyc = 0; cyc < 2000; cyc = cyc + 1) begin
            @(posedge clk);
            if (done_seen) begin
                repeat (4) @(posedge clk);
                cyc = 2000;
            end
        end

        if (!done_seen) begin
            $display("[FAIL] Core sanity program timed out waiting for DONE_MAGIC at 0x%08h", DONE_ADDR);
            fail_cnt = fail_cnt + 1;
        end else begin
            pass_cnt = pass_cnt + 1;
        end

        // -----------------------------------------------------------------
        // Verify Class 1: Arithmetic
        // -----------------------------------------------------------------
        check_eq(dmem[0],  32'd75,              "ARITH: ADDI/ADD (100 + -25)");
        check_eq(dmem[1],  32'hFFFF_FFB5,       "ARITH: SUB (25 - 100)");
        check_eq(dmem[2],  32'h00F0_0F00,       "ARITH: AND");
        check_eq(dmem[3],  32'h1234_5678,       "ARITH: OR");
        check_eq(dmem[4],  32'h5555_5555,       "ARITH: XOR");
        check_eq(dmem[5],  32'h0001_0000,       "ARITH: SLLI");
        check_eq(dmem[6],  32'h0800_0000,       "ARITH: SRL");
        check_eq(dmem[7],  32'hF800_0000,       "ARITH: SRA");
        check_eq(dmem[8],  32'd1,               "ARITH: SLT (-1 < 1)");
        check_eq(dmem[9],  32'd0,               "ARITH: SLTU (0xFFFFFFFF < 1)");
        check_eq(dmem[10], 32'h1234_5000,       "ARITH: LUI");
        check_eq(dmem[11], expected_auipc_val,  "ARITH: AUIPC");

        // -----------------------------------------------------------------
        // Verify Class 2: Branch (taken + not-taken across all 6 ops)
        // -----------------------------------------------------------------
        check_eq(dmem[16], 32'd12,              "BRANCH: BEQ/BNE/BLT/BGE/BLTU/BGEU (12/12)");

        // -----------------------------------------------------------------
        // Verify Class 3: Jump (JAL + JALR)
        // -----------------------------------------------------------------
        check_eq(dmem[17], 32'h0000_0333,       "JUMP: JAL forward + subroutine + JALR return");
        check_eq(dmem[18], expected_jal_ra,     "JUMP: JAL link register (PC + 4)");

        // -----------------------------------------------------------------
        // Verify Class 4 & 5: Store & Load (SW/SH/SB, LW/LH/LHU/LB/LBU)
        // -----------------------------------------------------------------
        check_eq(dmem[20], 32'h89AB_CDEF,       "LSU: SW + LW");
        check_eq(dmem[21], 32'hFFFF_FF81,       "LSU: SB + LB (sign-extended)");
        check_eq(dmem[22], 32'h0000_0081,       "LSU: SB + LBU (zero-extended)");
        check_eq(dmem[23], 32'hFFFF_F123,       "LSU: SH + LH (sign-extended)");
        check_eq(dmem[24], 32'h0000_F123,       "LSU: SH + LHU (zero-extended)");
        check_eq(dmem[25], 32'hF123_7F81,       "LSU: Byte/Halfword strobe merge LW");

        // -----------------------------------------------------------------
        // Verify Class 6: M-extension (MUL/MULH/DIV/REM/DIVU/REMU)
        // -----------------------------------------------------------------
        check_eq(dmem[28], 32'hFFFF_FFD6,       "M-EXT: MUL (-7 * 6 = -42)");
        check_eq(dmem[29], 32'hFFFF_FFFF,       "M-EXT: MULH (-7 * 6 upper = -1)");
        check_eq(dmem[30], 32'hFFFF_FFF2,       "M-EXT: DIV (-100 / 7 = -14)");
        check_eq(dmem[31], 32'hFFFF_FFFE,       "M-EXT: REM (-100 % 7 = -2)");
        check_eq(dmem[32], 32'h2AAA_AAAA,       "M-EXT: DIVU (0x80000000 / 3)");
        check_eq(dmem[33], 32'd2,               "M-EXT: REMU (0x80000000 % 3)");
        check_eq(dmem[34], 32'hFFFF_FFFF,       "M-EXT: DIV by zero (-1)");

        // -----------------------------------------------------------------
        // Verify IRQ Stimulus, ISR, CSRs, and MRET
        // -----------------------------------------------------------------
        check_eq(irq_trap_cnt, 32'd2,           "IRQ: 2 interrupts committed");
        check_eq(mret_cnt,     32'd2,           "IRQ: 2 MRETs committed");
        check_eq(dmem[40],     32'h8000_000B,   "IRQ: ISR #1 mcause = MEIP (0x8000000B)");
        check_eq(dmem[42],     32'h8000_0007,   "IRQ: ISR #2 mcause = MTIP (0x80000007)");
        check_eq(dmem[44],     32'd2,           "IRQ: ISR executed twice");
        if (dmem[41] < IMEM_BASE || dmem[41] >= ISR_PC ||
            dmem[43] < IMEM_BASE || dmem[43] >= ISR_PC) begin
            $display("[FAIL] IRQ saved mepc invalid: irq1=0x%08h irq2=0x%08h", dmem[41], dmem[43]);
            fail_cnt = fail_cnt + 1;
        end else begin
            pass_cnt = pass_cnt + 1;
        end
        check_eq(bus_err_cnt,  32'd0,           "BUS: Zero I-MEM/D-MEM protocol errors");

        // Summary
        $display("============================================================");
        $display("tb_core_sanity SUMMARY: PASS=%0d, FAIL=%0d", pass_cnt, fail_cnt);
        $display("============================================================");
        if (fail_cnt != 0)
            $fatal(1, "tb_core_sanity FAILED with %0d error(s)", fail_cnt);
        $finish;
    end

endmodule
