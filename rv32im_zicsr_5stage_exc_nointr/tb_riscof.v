`timescale 1ns / 1ps

module tb_riscof();

    reg clk;
    reg rst_n;

    riscforge_soc_subsystem_tb #(
        .ISRAM_NUM_WORDS(1048576),
        .DSRAM_NUM_WORDS(1048576),
        .ISRAM_BASE_ADDR(32'h8000_0000),
        .DSRAM_BASE_ADDR(32'h8000_1000)
    ) uut (
        .clk_i          (clk),
        .hard_rst_ni    (rst_n),
        .soft_rst_ni    (rst_n),
        .test_mode_i    (1'b0),
        .fetch_enable_i (1'b1),
        .boot_addr_i    (32'h8000_0000),
        .core_pc_w_o    (),
        .boot_done_o    (),
        .i2c_scl_i      (1'b1),
        .i2c_scl_o      (),
        .i2c_scl_oen_o  (),
        .i2c_sda_i      (1'b1),
        .i2c_sda_o      (),
        .i2c_sda_oen_o  (),
        .i2c_interrupt_o(),
        .timer_irq_o    (),
        .uart_sin_i     (1'b1),
        .uart_sout_o    (),
        .uart_int_o     (),
        .uart_out1n_o   (),
        .uart_out2n_o   (),
        .uart_rtsn_o    (),
        .uart_dtrn_o    (),
        .uart_ctsn_i    (1'b0),
        .uart_dsrn_i    (1'b0),
        .uart_dcdn_i    (1'b0),
        .uart_rin_i     (1'b0),
        .gpio_in_i      (32'b0),
        .gpio_out_o     (),
        .gpio_tx_en_o   (),
        .gpio_in_sync_o (),
        .gpio_global_interrupt_o(),
        .gpio_pin_level_interrupts_o(),
        .spi_clk_o      (),
        .spi_csn0_o     (),
        .spi_csn1_o     (),
        .spi_csn2_o     (),
        .spi_csn3_o     (),
        .spi_mode_o     (),
        .spi_sdo0_o     (),
        .spi_sdo1_o     (),
        .spi_sdo2_o     (),
        .spi_sdo3_o     (),
        .spi_sdi0_i     (1'b0),
        .spi_sdi1_i     (1'b0),
        .spi_sdi2_i     (1'b0),
        .spi_sdi3_i     (1'b0),
        .spi_events_o   ()
    );

    always #5 clk = ~clk;

    integer begin_sig, end_sig, tohost_addr;
    reg [8*256:1] sig_file;
    integer fd, i;
    integer cycle_count;
    integer max_cycles;
    reg [31:0] last_PC_W;
    integer stuck_cycles;
    reg dump_vcd;
    integer timeout_value;
    integer hard_timeout_ns;

    initial begin
        if (!$value$plusargs("begin_sig=%x", begin_sig)) begin_sig = 0;
        if (!$value$plusargs("end_sig=%x", end_sig)) end_sig = 0;
        if (!$value$plusargs("tohost_addr=%x", tohost_addr)) tohost_addr = 0;
        if (!$value$plusargs("sig_file=%s", sig_file)) sig_file = "signature.txt";
        if (!$value$plusargs("max_cycles=%d", max_cycles)) max_cycles = 50000;
        if (!$value$plusargs("dump_vcd=%d", dump_vcd)) dump_vcd = 0;

        clk = 0;
        rst_n = 0;
        cycle_count = 0;
        last_PC_W = 0;
        stuck_cycles = 0;

        // Diagnostic: print parsed plusargs
        $display("[RISCOF-TB] Config: max_cycles=%0d begin_sig=%08x end_sig=%08x tohost=%08x dump_vcd=%0d",
                 max_cycles, begin_sig, end_sig, tohost_addr, dump_vcd);

        if (dump_vcd) begin
            $dumpfile("sim_trace.vcd");
            $dumpvars(0, tb_riscof);
        end

        #20;
        rst_n = 1;
    end

    // Hardware timeout timer (separate initial block, runs in parallel)
    // Forces $finish after (max_cycles + 500) * 10 ns — independent of posedge clk
    initial begin
        integer dummy_fd;
        #5;  // wait for plusargs to be parsed
        timeout_value = (max_cycles + 500) * 10;
        hard_timeout_ns = timeout_value;
        #(hard_timeout_ns);
        $display("[RISCOF-TB] HARD TIME LIMIT reached at %0t ns — forcing finish", $time);
        // Dump dummy signature so RISCOF can proceed to next test
        dummy_fd = $fopen(sig_file, "w");
        if (dummy_fd != 0) begin
            $fwrite(dummy_fd, "00000000\n");
            $fclose(dummy_fd);
            $display("[RISCOF-TB] Dummy signature written to %s so RISCOF can continue", sig_file);
        end
        // Always dump debug log for diagnosis
        dummy_fd = $fopen("debug_riscof.log", "w");
        if (dummy_fd != 0) begin
            $fwrite(dummy_fd, "HARD TIMEOUT at cycle_count=%0d time=%0t\n", cycle_count, $time);
            $fwrite(dummy_fd, "begin_sig=%08x end_sig=%08x tohost=%08x max_cycles=%0d\n", begin_sig, end_sig, tohost_addr, max_cycles);
            $fclose(dummy_fd);
        end
        $finish;
    end

    // Monitor: detect write to tohost address
    // i_dsram.sram_addr is the 30-bit WORD address (= byte_addr >> 2)
    // tohost_addr from plusarg is the BYTE address from nm
    // So match when: (i_dsram.sram_addr << 2) == tohost_addr
    wire [31:0] dmem_byte_addr = {uut.i_dsram.sram_addr, 2'b00};
    wire [31:0] current_pc_w   = uut.i_riscv_core.PC_W;

    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;

            // Progress: print every 500 cycles to show simulation is alive
            if ((cycle_count % 500) == 0)
                $display("[RISCOF-TB] Progress: cycle %0d, PC_W=0x%08x, max_cycles=%0d", cycle_count, current_pc_w, max_cycles);

            if (uut.i_dsram.sram_en && uut.i_dsram.sram_we) begin
                $display("[DEBUG-TB] Mem Write: Addr=0x%08x, Val=0x%08x at cycle %0d", dmem_byte_addr, uut.i_dsram.sram_wdata, cycle_count);
            end

            // PC stagnation detection: if PC_W unchanged for 500 cycles, core is stuck
            stuck_cycles = (current_pc_w == last_PC_W) ? stuck_cycles + 1 : 0;
            last_PC_W = current_pc_w;
            if (stuck_cycles > 500) begin
                $display("[RISCOF-TB] STUCK at PC=0x%08x unchanged for %0d cycles at cycle %0d", last_PC_W, stuck_cycles, cycle_count);
                dump_signature();
                $finish;
            end

            // Timeout: max_cycles (configurable via +max_cycles plusarg)
            if (cycle_count > max_cycles) begin
                $display("[RISCOF-TB] TIMEOUT after %0d cycles - test may be stuck", cycle_count);
                dump_signature();
                $finish;
            end

            // Detect write to tohost (byte address match)
            if ((uut.i_dsram.sram_en && uut.i_dsram.sram_we) && tohost_addr != 0 && (dmem_byte_addr == tohost_addr)) begin
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
            
            // Safety check: addresses must be valid range
            if (begin_sig < 32'h80001000 || end_sig < 32'h80001000 || begin_sig > end_sig || (end_sig - begin_sig) > 65536) begin
                $display("[RISCOF-TB] Warning: Invalid/out-of-bounds signature range: begin_sig=%08x, end_sig=%08x. Skipping dump loop to prevent hang.", begin_sig, end_sig);
            end else begin
                // Dump the words between begin_sig and end_sig from i_dsram
                for (i = begin_sig; i < end_sig; i = i + 4) begin
                    $fwrite(fd, "%08x\n", uut.i_dsram.mem_array[(i - 32'h80001000) >> 2]);
                end
            end
            
            $fclose(fd);
            $fclose(debug_fd);
            $display("Signature dumped to %s", sig_file);
        end
    end
    endtask

endmodule
