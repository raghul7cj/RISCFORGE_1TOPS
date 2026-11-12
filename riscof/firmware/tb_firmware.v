`timescale 1ns / 1ps

module tb_firmware();

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

    initial begin
        if (!$value$plusargs("tohost_addr=%x", tohost_addr)) tohost_addr = 32'h80010000;

        $dumpfile("firmware.vcd");
        $dumpvars(0, tb_firmware);

        clk = 0;
        rst_n = 0;
        cycle_count = 0;

        #20;
        @(posedge clk);
        rst_n = 1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;

            if (cycle_count > 50000) begin
                $display("[TB_FIRMWARE] Timeout reached after %0d cycles at PC=0x%08x", cycle_count, dut.PCD);
                dump_registers;
                $finish;
            end

            // Detect halt: store to tohost
            if (lsu_mem_we && (lsu_mem_addr == tohost_addr)) begin
                $display("\n========================================================");
                $display("[TB_FIRMWARE] Program completed at cycle %0d!", cycle_count);
                $display("[TB_FIRMWARE] Write to tohost (0x%08x) = 0x%08x (%0d)", lsu_mem_addr, lsu_mem_wdata, $signed(lsu_mem_wdata));
                $display("========================================================");
                repeat (5) @(posedge clk);
                dump_registers;
                $finish;
            end
        end
    end

    task dump_registers;
        integer i;
    begin
        $display("");
        $display("================================================");
        $display("         REGISTER FILE DUMP  (x0 - x31)         ");
        $display("================================================");
        for (i = 0; i < 32; i = i + 1) begin
            $display("  x%-2d   |   0x%08h  |  %0d",
                     i,
                     dut.Decode.rf.Register[i],
                     $signed(dut.Decode.rf.Register[i]));
        end
        $display("================================================");
    end
    endtask

endmodule
