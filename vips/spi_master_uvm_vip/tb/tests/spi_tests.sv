//------------------------------------------------------------------------------
// spi_tests : concrete UVM tests.
//
// Directedness is deliberate, not a default: a test stays fully directed
// only when the *scenario itself* requires a specific, engineered
// condition that randomization can't reliably reach (a race window, a
// threshold like BUFFER_DEPTH, a real standardized command opcode). Where
// the scenario doesn't require specific values, the content (word data,
// clk_div, csreg, word count) is rolled fresh every run via $urandom(),
// so re-running the same test with a different -svseed exercises
// different data each time instead of the same fixed constants forever.
//------------------------------------------------------------------------------

// -----------------------------------------------------------------------
// spi_smoke_read_test : single 32-bit standard-mode read. Kept fully
// directed on purpose -- this is the fast, deterministic go/no-go gate
// you run first; it should never itself be a source of run-to-run
// variance.
// -----------------------------------------------------------------------
class spi_smoke_read_test extends spi_base_test;
    `uvm_component_utils(spi_smoke_read_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        spi_master_read_vseq vseq = spi_master_read_vseq::type_id::create("vseq");
        vseq.clk_div    = 8'd4;
        vseq.csreg      = 4'b0001;
        vseq.quad       = 1'b0;
        vseq.resp_words = '{32'h0000_0013}; // RISCV NOP: addi x0,x0,0
        run_vseq(phase, vseq);
    endtask

endclass : spi_smoke_read_test

// -----------------------------------------------------------------------
// spi_sequential_read_test : four separate single-word reads back to
// back. The *scenario* (four separate transactions, not one burst) is
// fixed; the word content, clk_div and csreg are rolled per-read.
// -----------------------------------------------------------------------
class spi_sequential_read_test extends spi_base_test;
    `uvm_component_utils(spi_sequential_read_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        bit [3:0] csreg_choices[4] = '{4'b0001, 4'b0010, 4'b0100, 4'b1000};
        phase.raise_objection(this);
        for (int i = 0; i < 4; i++) begin
            spi_master_read_vseq vseq = spi_master_read_vseq::type_id::create($sformatf("vseq_%0d", i));
            vseq.clk_div    = $urandom_range(1, 32);
            vseq.csreg      = csreg_choices[$urandom_range(0, 3)];
            vseq.resp_words = '{$urandom()};
            `uvm_info(get_type_name(), $sformatf(
                "[%0d/4] csreg=%b clk_div=%0d word=0x%08h",
                i+1, vseq.csreg, vseq.clk_div, vseq.resp_words[0]), UVM_LOW)
            vseq.start(env.vsqr);
        end
        phase.drop_objection(this);
    endtask

endclass : spi_sequential_read_test

// -----------------------------------------------------------------------
// spi_burst_read_test : words shifted in under a single CS assertion.
// The scenario (one burst) is fixed; word count/content/clk_div/csreg
// are rolled.
// -----------------------------------------------------------------------
class spi_burst_read_test extends spi_base_test;
    `uvm_component_utils(spi_burst_read_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        bit [3:0] csreg_choices[4] = '{4'b0001, 4'b0010, 4'b0100, 4'b1000};
        spi_master_read_vseq vseq = spi_master_read_vseq::type_id::create("vseq");
        int unsigned nwords = $urandom_range(2, 8);
        vseq.clk_div = $urandom_range(1, 32);
        vseq.csreg   = csreg_choices[$urandom_range(0, 3)];
        for (int i = 0; i < nwords; i++)
            vseq.resp_words.push_back($urandom());
        `uvm_info(get_type_name(), $sformatf(
            "csreg=%b clk_div=%0d nwords=%0d", vseq.csreg, vseq.clk_div, nwords), UVM_LOW)
        run_vseq(phase, vseq);
    endtask

endclass : spi_burst_read_test

// -----------------------------------------------------------------------
// spi_quad_read_test : exercises the SPI_QUAD_RX lane packing. quad=1 is
// fixed on purpose -- that's the entire point of this test; everything
// else is rolled.
// -----------------------------------------------------------------------
class spi_quad_read_test extends spi_base_test;
    `uvm_component_utils(spi_quad_read_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        bit [3:0] csreg_choices[4] = '{4'b0001, 4'b0010, 4'b0100, 4'b1000};
        spi_master_read_vseq vseq = spi_master_read_vseq::type_id::create("vseq");
        int unsigned nwords = $urandom_range(1, 8);
        vseq.clk_div = $urandom_range(1, 32);
        vseq.csreg   = csreg_choices[$urandom_range(0, 3)];
        vseq.quad    = 1'b1;
        for (int i = 0; i < nwords; i++)
            vseq.resp_words.push_back($urandom());
        `uvm_info(get_type_name(), $sformatf(
            "csreg=%b clk_div=%0d nwords=%0d", vseq.csreg, vseq.clk_div, nwords), UVM_LOW)
        run_vseq(phase, vseq);
    endtask

endclass : spi_quad_read_test

// -----------------------------------------------------------------------
// spi_write_test : exercises the TX path -- pushes words into TXFIFO and
// checks (via the scoreboard) that they come out correctly on MOSI.
// Word count/content/clk_div/csreg rolled each run.
// -----------------------------------------------------------------------
class spi_write_test extends spi_base_test;
    `uvm_component_utils(spi_write_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        bit [3:0] csreg_choices[4] = '{4'b0001, 4'b0010, 4'b0100, 4'b1000};
        spi_master_write_vseq vseq = spi_master_write_vseq::type_id::create("vseq");
        int unsigned nwords = $urandom_range(2, 8);
        vseq.clk_div = $urandom_range(1, 32);
        vseq.csreg   = csreg_choices[$urandom_range(0, 3)];
        for (int i = 0; i < nwords; i++)
            vseq.tx_words.push_back($urandom());
        `uvm_info(get_type_name(), $sformatf(
            "csreg=%b clk_div=%0d nwords=%0d", vseq.csreg, vseq.clk_div, nwords), UVM_LOW)
        run_vseq(phase, vseq);
    endtask

endclass : spi_write_test

// -----------------------------------------------------------------------
// spi_flash_read_test : mimics a real SPI NOR flash "Read Data" command
// (opcode 0x03): 8-bit opcode + 24-bit address, no dummy cycles, then the
// data phase. Standard (1-bit) mode -- 0x03 is never used with quad I/O
// on real flash parts.
//
// The opcode (0x03) and framing (cmd_bits=8, addr_bits=24, dummy=0) are
// fixed on purpose: those are what make this a real, standardized flash
// command rather than an arbitrary transfer -- randomizing them would
// test nothing that exists in the real world. The address, response
// data, and clk_div are rolled every run.
//
// This is the first test to exercise nonzero cmd_bits/addr_bits at all;
// treat a failure here as equally likely to be the new preamble-timing
// model (see compute_preamble_symbols()) as the DUT itself.
// -----------------------------------------------------------------------
class spi_flash_read_test extends spi_base_test;
    `uvm_component_utils(spi_flash_read_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        spi_master_read_vseq vseq = spi_master_read_vseq::type_id::create("vseq");
        int unsigned nwords = $urandom_range(1, 4);
        vseq.clk_div    = $urandom_range(1, 32);
        vseq.csreg      = 4'b0001;
        vseq.quad       = 1'b0;
        vseq.cmd_val    = 32'h0300_0000;                 // fixed: opcode 0x03 (real flash command)
        vseq.cmd_bits   = 6'd8;                           // fixed: opcode framing
        vseq.addr_val   = $urandom() & 32'hFFFF_FF00;   // random 24-bit address, top-justified
        vseq.addr_bits  = 6'd24;                          // fixed: address framing
        vseq.dummy_rd   = 16'd0;                          // fixed: 0x03 has no dummy phase
        for (int i = 0; i < nwords; i++)
            vseq.resp_words.push_back($urandom());
        `uvm_info(get_type_name(), $sformatf(
            "clk_div=%0d addr=0x%08h nwords=%0d", vseq.clk_div, vseq.addr_val, nwords), UVM_LOW)
        run_vseq(phase, vseq);
    endtask

endclass : spi_flash_read_test

// -----------------------------------------------------------------------
// spi_flash_fast_read_test : mimics SPI NOR flash "Fast Read" (opcode
// 0x0B): 8-bit opcode + 24-bit address + 8 dummy clock cycles, then data.
// Opcode and framing (including the 8 dummy cycles, part of the 0x0B
// spec) are fixed for the same reason as spi_flash_read_test; address,
// data and clk_div are rolled.
// -----------------------------------------------------------------------
class spi_flash_fast_read_test extends spi_base_test;
    `uvm_component_utils(spi_flash_fast_read_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        spi_master_read_vseq vseq = spi_master_read_vseq::type_id::create("vseq");
        int unsigned nwords = $urandom_range(1, 4);
        vseq.clk_div    = $urandom_range(1, 32);
        vseq.csreg      = 4'b0001;
        vseq.quad       = 1'b0;
        vseq.cmd_val    = 32'h0B00_0000;                 // fixed: opcode 0x0B (real flash command)
        vseq.cmd_bits   = 6'd8;                           // fixed: opcode framing
        vseq.addr_val   = $urandom() & 32'hFFFF_FF00;   // random 24-bit address, top-justified
        vseq.addr_bits  = 6'd24;                          // fixed: address framing
        vseq.dummy_rd   = 16'd8;                          // fixed: 8 dummy clocks, part of 0x0B spec
        for (int i = 0; i < nwords; i++)
            vseq.resp_words.push_back($urandom());
        `uvm_info(get_type_name(), $sformatf(
            "clk_div=%0d addr=0x%08h nwords=%0d", vseq.clk_div, vseq.addr_val, nwords), UVM_LOW)
        run_vseq(phase, vseq);
    endtask

endclass : spi_flash_fast_read_test

// -----------------------------------------------------------------------
// spi_random_test : constrained-random regression. Randomizes clk_div,
// csreg, quad mode, cmd/addr/dummy framing, and word count/content for a
// mix of read and write transactions. Iteration count can be overridden
// with +NUM_TRANS=<n>.
// -----------------------------------------------------------------------
class spi_random_test extends spi_base_test;
    `uvm_component_utils(spi_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        int unsigned num_trans = 20;
        void'($value$plusargs("NUM_TRANS=%0d", num_trans));

        phase.raise_objection(this);
        for (int i = 0; i < num_trans; i++) begin
            if ($urandom_range(0, 1)) begin
                spi_master_read_vseq vseq = spi_master_read_vseq::type_id::create($sformatf("rd_%0d", i));
                if (!vseq.randomize())
                    `uvm_fatal(get_type_name(), "read vseq randomize failed")
                `uvm_info(get_type_name(), $sformatf(
                    "[%0d/%0d] READ  quad=%0b csreg=%b clk_div=%0d cmd_bits=%0d addr_bits=%0d dummy=%0d nwords=%0d",
                    i+1, num_trans, vseq.quad, vseq.csreg, vseq.clk_div,
                    vseq.cmd_bits, vseq.addr_bits, vseq.dummy_rd, vseq.resp_words.size()), UVM_LOW)
                vseq.start(env.vsqr);
            end
            else begin
                spi_master_write_vseq vseq = spi_master_write_vseq::type_id::create($sformatf("wr_%0d", i));
                if (!vseq.randomize())
                    `uvm_fatal(get_type_name(), "write vseq randomize failed")
                `uvm_info(get_type_name(), $sformatf(
                    "[%0d/%0d] WRITE quad=%0b csreg=%b clk_div=%0d cmd_bits=%0d addr_bits=%0d nwords=%0d",
                    i+1, num_trans, vseq.quad, vseq.csreg, vseq.clk_div,
                    vseq.cmd_bits, vseq.addr_bits, vseq.tx_words.size()), UVM_LOW)
                vseq.start(env.vsqr);
            end
        end
        phase.drop_objection(this);
    endtask

endclass : spi_random_test

// -----------------------------------------------------------------------
// spi_overflow_test : RX FIFO backpressure/overflow + recovery. n_words
// must exceed BUFFER_DEPTH (10) or the stall this test exists to check
// simply won't occur -- that threshold is fixed on purpose; random draws
// from spi_random_test (word count 1-8) would essentially never trigger
// it. csreg is rolled since it isn't load-bearing to the scenario.
// -----------------------------------------------------------------------
class spi_overflow_test extends spi_base_test;
    `uvm_component_utils(spi_overflow_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        bit [3:0] csreg_choices[4] = '{4'b0001, 4'b0010, 4'b0100, 4'b1000};
        spi_rx_overflow_vseq vseq = spi_rx_overflow_vseq::type_id::create("vseq");
        vseq.n_words = 16; // fixed: must exceed BUFFER_DEPTH(10) to force the stall
        vseq.csreg   = csreg_choices[$urandom_range(0, 3)];
        `uvm_info(get_type_name(), $sformatf("csreg=%b n_words=%0d", vseq.csreg, vseq.n_words), UVM_LOW)
        run_vseq(phase, vseq, 2_000_000);
    endtask

endclass : spi_overflow_test

// -----------------------------------------------------------------------
// spi_empty_fifo_stall_test : PREADY stall on an early RXFIFO read. This
// is a race-window test (APB read arrives before SPI data does) -- the
// condition itself has to be engineered, not rolled, so it stays fully
// directed.
// -----------------------------------------------------------------------
class spi_empty_fifo_stall_test extends spi_base_test;
    `uvm_component_utils(spi_empty_fifo_stall_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        spi_empty_fifo_stall_vseq vseq = spi_empty_fifo_stall_vseq::type_id::create("vseq");
        run_vseq(phase, vseq);
    endtask

endclass : spi_empty_fifo_stall_test

// -----------------------------------------------------------------------
// spi_reset_test : software reset mid-transfer. Also a timing-injection
// test (swrst must land mid-transfer, not before/after) -- stays
// directed for the same reason as the empty-FIFO-stall test.
// -----------------------------------------------------------------------
class spi_reset_test extends spi_base_test;
    `uvm_component_utils(spi_reset_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        spi_swrst_vseq vseq = spi_swrst_vseq::type_id::create("vseq");
        run_vseq(phase, vseq);
    endtask

endclass : spi_reset_test

// -----------------------------------------------------------------------
// spi_regression_test : one-stop constrained-random regression combining
// the directed corner cases (overflow, empty-FIFO stall, reset -- each of
// which requires its own engineered condition, see their own classes
// above) with a large batch of randomized read/write traffic. Intended
// as the default test for nightly/full regression. Iteration count:
// +NUM_TRANS=<n>.
// -----------------------------------------------------------------------
class spi_regression_test extends spi_base_test;
    `uvm_component_utils(spi_regression_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        int unsigned num_trans = 50;
        void'($value$plusargs("NUM_TRANS=%0d", num_trans));

        phase.raise_objection(this);

        // NOTE ON ORDERING: spi_swrst_vseq (v2, below) intentionally
        // asserts spi_swrst mid-transfer. Because spi_swrst does not reset
        // spi_master_controller's state machine (see the RTL's own
        // "FIXME Not used at all" comment on that port), the controller
        // can fail to resynchronize with the interrupted bit stream and
        // leave spi_cs asserted (bus wedged) for the rest of the
        // simulation -- since the controller only accepts a new
        // rd/wr/qrd/qwr trigger while in IDLE, every subsequent
        // transaction then silently never starts and wait_eot() times out
        // for reasons that have nothing to do with that later
        // transaction's own configuration. This was found the hard way:
        // v2 used to run before the random loop and the very next
        // transaction after it would hang. Keep v2 LAST so this DUT
        // behavior (worth confirming with the RTL owner) can't take out
        // any other test in the same simulation.
        begin
            spi_empty_fifo_stall_vseq v0 = spi_empty_fifo_stall_vseq::type_id::create("v0");
            v0.start(env.vsqr);
        end

        begin
            spi_rx_overflow_vseq v1 = spi_rx_overflow_vseq::type_id::create("v1");
            v1.n_words = 16;
            v1.start(env.vsqr);
        end

        for (int i = 0; i < num_trans; i++) begin
            if ($urandom_range(0, 1)) begin
                spi_master_read_vseq vseq = spi_master_read_vseq::type_id::create($sformatf("rd_%0d", i));
                if (!vseq.randomize())
                    `uvm_fatal(get_type_name(), "read vseq randomize failed")
                `uvm_info(get_type_name(), $sformatf(
                    "[%0d/%0d] READ  quad=%0b csreg=%b clk_div=%0d cmd_bits=%0d addr_bits=%0d dummy=%0d nwords=%0d",
                    i+1, num_trans, vseq.quad, vseq.csreg, vseq.clk_div,
                    vseq.cmd_bits, vseq.addr_bits, vseq.dummy_rd, vseq.resp_words.size()), UVM_LOW)
                vseq.start(env.vsqr);
            end
            else begin
                spi_master_write_vseq vseq = spi_master_write_vseq::type_id::create($sformatf("wr_%0d", i));
                if (!vseq.randomize())
                    `uvm_fatal(get_type_name(), "write vseq randomize failed")
                `uvm_info(get_type_name(), $sformatf(
                    "[%0d/%0d] WRITE quad=%0b csreg=%b clk_div=%0d cmd_bits=%0d addr_bits=%0d nwords=%0d",
                    i+1, num_trans, vseq.quad, vseq.csreg, vseq.clk_div,
                    vseq.cmd_bits, vseq.addr_bits, vseq.tx_words.size()), UVM_LOW)
                vseq.start(env.vsqr);
            end
        end

        // Run last, deliberately -- see note above.
        begin
            spi_swrst_vseq v2 = spi_swrst_vseq::type_id::create("v2");
            v2.start(env.vsqr);
        end

        phase.drop_objection(this);
    endtask

endclass : spi_regression_test
