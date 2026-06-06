`timescale 1ns / 1ps

module tb_riscof();

    reg clk;
    reg rst;
    wire PCSrcE1;

    top uut (
        .clk(clk),
        .rst(rst),
        .PCSrcE1(PCSrcE1)
    );

    always #5 clk = ~clk;

    integer begin_sig, end_sig, tohost_addr;
    reg [8*256:1] sig_file;
    integer fd, i;
    integer cycle_count;

    initial begin
        if (!$value$plusargs("begin_sig=%x", begin_sig)) begin_sig = 0;
        if (!$value$plusargs("end_sig=%x", end_sig)) end_sig = 0;
        if (!$value$plusargs("tohost_addr=%x", tohost_addr)) tohost_addr = 0;
        if (!$value$plusargs("sig_file=%s", sig_file)) sig_file = "signature.txt";

        clk = 0;
        rst = 0;
        cycle_count = 0;

        $dumpfile("sim_trace.vcd");
        $dumpvars(0, tb_riscof);

        #20;
        rst = 1;
    end

    // Monitor: detect write to tohost address
    // dmem.A is the 30-bit WORD address (= byte_addr >> 2)
    // tohost_addr from plusarg is the BYTE address from nm
    // So match when: (dmem.A << 2) == tohost_addr
    wire [31:0] dmem_byte_addr = {uut.Memory.dmem.A, 2'b00};

    always @(posedge clk) begin
        if (rst) begin
            cycle_count = cycle_count + 1;
            
            $display("[DEBUG-TB] Cycle=%0d PC_W=0x%08x valid_W=%b exc_valid_W=%b is_mret_W=%b", cycle_count, uut.PC_W, uut.valid_W, uut.exc_valid_W, uut.is_mret_W);

            if (uut.Memory.dmem.WE) begin
                $display("[DEBUG-TB] Mem Write: Addr=0x%08x, Val=0x%08x at cycle %0d", {uut.Memory.dmem.A, 2'b00}, uut.Memory.dmem.WD, cycle_count);
            end

            // Timeout: 50k cycles is plenty for RV32I compliance tests
            if (cycle_count > 50000) begin
                $display("[RISCOF-TB] TIMEOUT after %0d cycles - test may be stuck", cycle_count);
                dump_signature();
                $finish;
            end

            // Detect write to tohost (byte address match)
            if (uut.Memory.dmem.WE && tohost_addr != 0 && (dmem_byte_addr == tohost_addr)) begin
                $display("[RISCOF-TB] tohost write detected at cycle %0d (addr=0x%08x)", cycle_count, dmem_byte_addr);
                dump_signature();
                $finish;
            end
        end
    end

    task dump_signature;
        integer word_addr;
        integer debug_fd;
    begin
        fd = $fopen(sig_file, "w");
        debug_fd = $fopen("debug_riscof.log", "w");
        if (fd == 0) begin
            $display("Error: Could not open signature file %s", sig_file);
        end else begin
            $display("Dumping signature to %s", sig_file);
            $fwrite(debug_fd, "begin_sig=%08x end_sig=%08x tohost=%08x cycle_count=%d\n", begin_sig, end_sig, tohost_addr, cycle_count);
            // Dump the words between begin_sig and end_sig
            for (i = begin_sig; i < end_sig; i = i + 4) begin
                $fwrite(fd, "%08x\n", uut.Memory.dmem.mem[(i - 32'h1000) >> 2]);
            end
            $fclose(fd);
            $fclose(debug_fd);
            $display("Signature dumped to %s", sig_file);
        end
    end
    endtask

endmodule
