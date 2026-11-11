`timescale 1ns / 1ps

module tb_top();

    reg clk;
    reg rst_n;

    wire        imem_sram_en;
    wire        imem_sram_we;
    wire [3:0]  imem_sram_wmask;
    wire [29:0] imem_sram_addr;
    wire [31:0] imem_sram_wdata;
    wire [31:0] imem_sram_rdata;

    wire        lsu_mem_req;
    wire        lsu_mem_we;
    wire [31:0] lsu_mem_addr;
    wire [31:0] lsu_mem_wdata;
    wire [3:0]  lsu_mem_be;
    wire [31:0] lsu_mem_rdata;

    top #(
        .RESET_PC (32'h80000000)
    ) dut (
        .clk             (clk),
        .rst             (rst_n),
        .PCSrcE1         (),

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
        .lsu_mem_stall   (1'b0),
        .lsu_mem_err     (1'b0),

        .fast_irq_i      (16'h0),
        .timer_irq_i     (1'b0),
        .ext_irq_i       (1'b0),
        .sw_irq_i        (1'b0)
    );

    Instruction_Memory_new #(
        .MEM_DEPTH      (262144),
        .IMEM_BASE_BYTE (32'h80000000)
    ) imem (
        .clk        (clk),
        .rst_n      (rst_n),
        .sram_en    (imem_sram_en),
        .sram_we    (imem_sram_we),
        .sram_wmask (imem_sram_wmask),
        .sram_addr  (imem_sram_addr),
        .sram_wdata (imem_sram_wdata),
        .sram_rdata (imem_sram_rdata)
    );

    Data_Memory #(
        .MEM_DEPTH      (262144),
        .DMEM_BASE_BYTE (32'h80000000)
    ) dmem (
        .clk        (clk),
        .rst_n      (rst_n),
        .sram_en    (lsu_mem_req),
        .sram_we    (lsu_mem_we),
        .sram_wmask (lsu_mem_be),
        .sram_addr  (lsu_mem_addr[31:2]),
        .sram_wdata (lsu_mem_wdata),
        .sram_rdata (lsu_mem_rdata)
    );

    always #5 clk = ~clk;

    integer tohost_addr;
    integer cycle_count;
    integer max_cycles;
    integer log_fd;
    reg [8*256:1] log_file;
    reg dump_vcd;
    reg halt_pending;
    reg [2:0] halt_countdown;

    // Track stores across MEM -> WB pipeline stage
    reg [31:0] store_wdata_W;
    always @(negedge clk) begin
        if (!rst_n) begin
            store_wdata_W <= 32'b0;
        end else if (!dut.Memory.core_stall_gated) begin
            store_wdata_W <= dut.Memory.WriteDataM;
        end
    end

    initial begin
        if (!$value$plusargs("tohost_addr=%x", tohost_addr)) tohost_addr = 32'h80000100;
        if (!$value$plusargs("max_cycles=%d", max_cycles))   max_cycles = 50000;
        if (!$value$plusargs("log_file=%s", log_file))       log_file = "rtl_commits.log";
        if (!$value$plusargs("dump_vcd=%d", dump_vcd))       dump_vcd = 0;

        if (dump_vcd) begin
            $dumpfile("rtl_sim.vcd");
            $dumpvars(0, tb_top);
        end

        log_fd = $fopen(log_file, "w");
        if (log_fd == 0) begin
            $display("ERROR: Failed to open %s for writing", log_file);
            $finish;
        end

        clk = 0;
        rst_n = 0;
        cycle_count = 0;
        halt_pending = 0;
        halt_countdown = 3'd0;

        #20;
        @(negedge clk);
        rst_n = 1;
    end

    // Instruction Commit Monitor at WB stage
    wire [31:0] cur_pc_w = dut.PC_W;
    wire [31:0] cur_instr = imem.mem_array[(cur_pc_w - 32'h80000000) >> 2];
    wire [6:0]  cur_opcode = cur_instr[6:0];
    wire        is_store_op = (cur_opcode == 7'b0100011);

    always @(negedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;

            // Commit logging when instruction retires
            if (dut.valid_W && !dut.exc_valid_W) begin
                if (dut.RegWriteW_gated && (dut.RDW != 5'd0)) begin
                    // Register writeback commit
                    $fwrite(log_fd, "core   0: 3 0x%08x (0x%08x) x%-2d 0x%08x\n",
                            cur_pc_w, cur_instr, dut.RDW, dut.ResultW);
                end else if (is_store_op) begin
                    // Store commit: log memory address and formatted/written data
                    $fwrite(log_fd, "core   0: 3 0x%08x (0x%08x) mem 0x%08x 0x%08x\n",
                            cur_pc_w, cur_instr, dut.ALU_ResultW, store_wdata_W);
                end else begin
                    // Instruction without register or memory commit (branches, CSR without writeback, etc.)
                    $fwrite(log_fd, "core   0: 3 0x%08x (0x%08x)\n",
                            cur_pc_w, cur_instr);
                end
            end

            // Timeout detection
            if (cycle_count > max_cycles) begin
                $display("[TB_TOP] TIMEOUT: Exceeded %0d cycles at PC=0x%08x", max_cycles, dut.PC_W);
                $fclose(log_fd);
                $finish;
            end

            // Detect halt: store to tohost
            if (lsu_mem_we && (lsu_mem_addr == tohost_addr) && !halt_pending) begin
                $display("[TB_TOP] tohost write detected at cycle %0d: addr=0x%08x data=0x%08x",
                         cycle_count, lsu_mem_addr, lsu_mem_wdata);
                halt_pending <= 1'b1;
                halt_countdown <= 3'd3;
            end

            if (halt_pending) begin
                if (halt_countdown == 3'd0) begin
                    $fclose(log_fd);
                    $display("[TB_TOP] RTL simulation completed successfully.");
                    $finish;
                end else begin
                    halt_countdown <= halt_countdown - 1'b1;
                end
            end
        end
    end

endmodule
