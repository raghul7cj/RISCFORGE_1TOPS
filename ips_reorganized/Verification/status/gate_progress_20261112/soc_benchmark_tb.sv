`timescale 1ns/1ps
`include "benchmark_config.svh"

module soc_benchmark_tb;
  timeunit 1ns;
  timeprecision 1ps;

  localparam logic [31:0] RESULT_MAGIC = 32'h4245_4e43;
  localparam logic [31:0] RESULT_VERSION = 32'd1;
  localparam int unsigned RESULT_WORDS = 64;
  localparam int unsigned WORD_MAGIC = 0;
  localparam int unsigned WORD_VERSION = 1;
  localparam int unsigned WORD_STATUS = 2;
  localparam int unsigned WORD_BENCHMARK_ID = 3;
  localparam int unsigned WORD_ITERATIONS = 4;
  localparam int unsigned WORD_VALIDATION_ERRORS = 5;
  localparam int unsigned WORD_CYCLE_START_LO = 6;
  localparam int unsigned WORD_CYCLE_START_HI = 7;
  localparam int unsigned WORD_CYCLE_END_LO = 8;
  localparam int unsigned WORD_CYCLE_END_HI = 9;
  localparam int unsigned WORD_INSTRET_START_LO = 10;
  localparam int unsigned WORD_INSTRET_START_HI = 11;
  localparam int unsigned WORD_INSTRET_END_LO = 12;
  localparam int unsigned WORD_INSTRET_END_HI = 13;
  localparam int unsigned WORD_CONSOLE = 23;
  localparam int unsigned WORD_TIMING_PHASE = 26;
  localparam int unsigned DSRAM_WORDS = 8192;
  localparam int unsigned ISRAM_WORDS = 8192;

  logic clk_i = 1'b0;
  logic hard_rst_ni = 1'b0;
  logic soft_rst_ni = 1'b0;
  logic test_mode_i = 1'b0;
  logic fetch_enable_i = 1'b1;
  logic [31:0] boot_addr_i = 32'h0000_0000;
  logic boot_done_o;

  logic i2c_scl_i = 1'b1;
  logic i2c_scl_o;
  logic i2c_scl_oen_o;
  logic i2c_sda_i = 1'b1;
  logic i2c_sda_o;
  logic i2c_sda_oen_o;
  logic i2c_interrupt_o;
  logic [3:0] timer0_irq_o;
  logic [3:0] timer1_irq_o;
  logic uart_sin_i = 1'b1;
  logic uart_sout_o;
  logic uart_int_o;
  logic [31:0] gpio_in_i = '0;
  logic [31:0] gpio_out_o;
  logic [31:0] gpio_tx_en_o;
  logic [31:0] gpio_in_sync_o;
  logic gpio_global_interrupt_o;
  logic [31:0] gpio_pin_level_interrupts_o;
  logic spi_clk_o;
  logic spi_csn0_o;
  logic spi_csn1_o;
  logic spi_sdo0_o;
  logic spi_sdi1_i = 1'b0;
  logic [1:0] spi_events_o;
  logic [5:0] apb_timeout_sticky_o;
  logic axi_wr_timeout_sticky_o;
  logic axi_rd_timeout_sticky_o;

  logic [31:0] imem_words [0:ISRAM_WORDS-1];
  logic [31:0] dmem_words [0:DSRAM_WORDS-1];
  string imem_hex;
  string dmem_hex;
  string result_json;
  string fail_reason;
  string boot_reason;
  integer timeout_cycles;
  integer requested_benchmark_id;
  integer fd;
  integer i;
  integer boot_cycle;
  integer run_cycle;
  integer observed_clock_cycles = 0;
  integer held_wb_cycles = 0;
  integer raw_wb_valid_cycles = 0;
  integer timing_phase_first_cycle = 0;
  integer timing_phase_last_cycle = 0;
  integer timing_phase_seen = 0;
  logic monitor_enable = 1'b0;
  logic trap_seen = 1'b0;
  logic trap_was_interrupt = 1'b0;
  logic [31:0] trap_cause_seen = 32'h0;
  logic [31:0] trap_pc_seen = 32'h0;
  logic [31:0] trap_tval_seen = 32'h0;
  logic [31:0] console_previous = 32'h0;
  logic result_written = 1'b0;
  logic running_seen = 1'b0;
  logic [31:0] current_status;
  logic [31:0] current_magic;
  logic [31:0] current_version;
  logic [31:0] current_id;
  logic [31:0] current_validation_errors;
  logic [31:0] current_timing_phase;
  logic [63:0] cycle_delta;

  function automatic integer hex_digit(input byte character);
    if (character >= "0" && character <= "9") return character - "0";
    if (character >= "a" && character <= "f") return character - "a" + 10;
    if (character >= "A" && character <= "F") return character - "A" + 10;
    return -1;
  endfunction

  // Windows paths may contain spaces, while simulator plusargs are tokenized
  // on whitespace. The host encodes '%' and spaces as %25 and %20.
  function automatic string decode_path(input string encoded);
    string decoded;
    integer position;
    integer upper_nibble;
    integer lower_nibble;
    byte character;
    begin
      decoded = "";
      position = 0;
      while (position < encoded.len()) begin
        character = encoded[position];
        if (character == 8'h25 && position + 2 < encoded.len()) begin
          upper_nibble = hex_digit(encoded[position + 1]);
          lower_nibble = hex_digit(encoded[position + 2]);
          if (upper_nibble >= 0 && lower_nibble >= 0) begin
            decoded = {decoded, byte'((upper_nibble << 4) | lower_nibble)};
            position = position + 3;
          end else begin
            decoded = {decoded, character};
            position = position + 1;
          end
        end else begin
          decoded = {decoded, character};
          position = position + 1;
        end
      end
      return decoded;
    end
  endfunction

  always #5 clk_i = ~clk_i;

  riscforge_soc_subsystem dut (
    .clk_i                       (clk_i),
    .hard_rst_ni                 (hard_rst_ni),
    .soft_rst_ni                 (soft_rst_ni),
    .test_mode_i                 (test_mode_i),
    .fetch_enable_i              (fetch_enable_i),
    .boot_addr_i                 (boot_addr_i),
    .boot_done_o                 (boot_done_o),
    .i2c_scl_i                   (i2c_scl_i),
    .i2c_scl_o                   (i2c_scl_o),
    .i2c_scl_oen_o               (i2c_scl_oen_o),
    .i2c_sda_i                   (i2c_sda_i),
    .i2c_sda_o                   (i2c_sda_o),
    .i2c_sda_oen_o               (i2c_sda_oen_o),
    .i2c_interrupt_o             (i2c_interrupt_o),
    .timer0_irq_o                (timer0_irq_o),
    .timer1_irq_o                (timer1_irq_o),
    .uart_sin_i                  (uart_sin_i),
    .uart_sout_o                 (uart_sout_o),
    .uart_int_o                  (uart_int_o),
    .gpio_in_i                   (gpio_in_i),
    .gpio_out_o                  (gpio_out_o),
    .gpio_tx_en_o                (gpio_tx_en_o),
    .gpio_in_sync_o              (gpio_in_sync_o),
    .gpio_global_interrupt_o      (gpio_global_interrupt_o),
    .gpio_pin_level_interrupts_o (gpio_pin_level_interrupts_o),
    .spi_clk_o                   (spi_clk_o),
    .spi_csn0_o                  (spi_csn0_o),
    .spi_csn1_o                  (spi_csn1_o),
    .spi_sdo0_o                  (spi_sdo0_o),
    .spi_sdi1_i                  (spi_sdi1_i),
    .spi_events_o                (spi_events_o),
    .apb_timeout_sticky_o        (apb_timeout_sticky_o),
    .axi_wr_timeout_sticky_o     (axi_wr_timeout_sticky_o),
    .axi_rd_timeout_sticky_o     (axi_rd_timeout_sticky_o)
  );

  // Point the unmodified SoC's ROM at the checked-in image. The generated
  // config header contains a string literal with an absolute host path.
  // Diagnostic portability overlay: identical ROM staged at its default path.

  always @(posedge clk_i) begin
    if (monitor_enable) begin
      observed_clock_cycles <= observed_clock_cycles + 1;
      if (dut.i_riscv_core.valid_W === 1'b1 && dut.i_riscv_core.exc_valid_W !== 1'b1)
        raw_wb_valid_cycles <= raw_wb_valid_cycles + 1;
      if (dut.i_riscv_core.valid_W === 1'b1 &&
          dut.i_riscv_core.exc_valid_W !== 1'b1 &&
          dut.i_riscv_core.mem_stall_out === 1'b1)
        held_wb_cycles <= held_wb_cycles + 1;
      if (dut.i_riscv_core.trap_commit_valid === 1'b1) begin
        trap_seen <= 1'b1;
        trap_was_interrupt <= dut.i_riscv_core.trap_commit_is_interrupt;
        trap_cause_seen <= dut.i_riscv_core.trap_commit_cause;
        trap_pc_seen <= dut.i_riscv_core.trap_commit_pc;
        trap_tval_seen <= dut.i_riscv_core.trap_commit_addr_valid ?
                          dut.i_riscv_core.trap_commit_addr : 32'h0;
      end
      current_timing_phase = dut.i_dsram.mem[WORD_TIMING_PHASE];
      if (current_timing_phase == 32'd1) begin
        if (timing_phase_seen == 0) begin
          timing_phase_first_cycle <= observed_clock_cycles;
          timing_phase_seen <= 1;
        end
        timing_phase_last_cycle <= observed_clock_cycles;
      end
    end
  end


  // Passive observers: never force signals, drive memory, or change verdicts.
  bit probe_started=0;
  logic [31:0] probe_min_sp=32'h28000, probe_max_sp=0;
  logic [31:0] probe_data_min=32'hffffffff, probe_data_max=0;
  integer probe_sp_outside=0, probe_data_outside=0, probe_samples=0;
  integer probe_lane;
  logic [31:0] probe_byte_address;
  always @(negedge clk_i) if(dut.core_rst_n) begin
    if(dut.i_riscv_core.Decode.rf.Register[2] == 32'h28000) probe_started=1;
    if(probe_started) begin
      if(dut.i_riscv_core.Decode.rf.Register[2] < probe_min_sp)
        probe_min_sp=dut.i_riscv_core.Decode.rf.Register[2];
      if(dut.i_riscv_core.Decode.rf.Register[2] > probe_max_sp)
        probe_max_sp=dut.i_riscv_core.Decode.rf.Register[2];
      if(dut.i_riscv_core.Decode.rf.Register[2] < 32'h21100 ||
         dut.i_riscv_core.Decode.rf.Register[2] > 32'h28000) probe_sp_outside++;
    end
  end
  always @(posedge clk_i) if(dut.core_rst_n &&
      dut.i_riscv_core.lsu_mem_req && !dut.i_riscv_core.lsu_mem_stall) begin
    probe_samples++;
    for(probe_lane=0;probe_lane<4;probe_lane++)
      if(dut.i_riscv_core.lsu_mem_be[probe_lane]) begin
        probe_byte_address=(dut.i_riscv_core.lsu_mem_addr & 32'hfffffffc)+probe_lane;
        if(probe_byte_address<probe_data_min) probe_data_min=probe_byte_address;
        if(probe_byte_address>probe_data_max) probe_data_max=probe_byte_address;
        if(probe_byte_address<32'h20000 || probe_byte_address>=32'h28000) probe_data_outside++;
      end
  end
  task automatic write_sram_probe;
    integer probe_fd;
    begin
      probe_fd=$fopen("sram_probe.json","w");
      $fdisplay(probe_fd,"{");
      $fdisplay(probe_fd,"  \"sp_tracking_started\": %0d,",probe_started);
      $fdisplay(probe_fd,"  \"min_sp\": \"0x%08x\",",probe_min_sp);
      $fdisplay(probe_fd,"  \"max_sp\": \"0x%08x\",",probe_max_sp);
      $fdisplay(probe_fd,"  \"sp_outside_static_free_range_samples\": %0d,",probe_sp_outside);
      $fdisplay(probe_fd,"  \"observed_req_not_stalled_samples\": %0d,",probe_samples);
      $fdisplay(probe_fd,"  \"data_byte_min\": \"0x%08x\",",probe_data_min);
      $fdisplay(probe_fd,"  \"data_byte_max\": \"0x%08x\",",probe_data_max);
      $fdisplay(probe_fd,"  \"data_byte_outside_dsram_samples\": %0d",probe_data_outside);
      $fdisplay(probe_fd,"}");
      $fclose(probe_fd);
    end
  endtask

  task automatic write_result_json(input string reason, input string marker);
    integer result_index;
    begin
      if (!result_written) begin
        write_sram_probe();
        result_written = 1'b1;
        fd = $fopen(result_json, "w");
        if (fd != 0) begin
          $fdisplay(fd, "{");
          $fdisplay(fd, "  \"schema_version\": 1,");
          $fdisplay(fd, "  \"reason\": \"%0s\",", reason);
          $fdisplay(fd, "  \"testbench_marker\": \"%0s\",", marker);
          $fdisplay(fd, "  \"observed_clock_cycles\": %0d,", observed_clock_cycles);
          $fdisplay(fd, "  \"held_wb_cycles\": %0d,", held_wb_cycles);
          $fdisplay(fd, "  \"raw_wb_valid_cycles\": %0d,", raw_wb_valid_cycles);
          $fdisplay(fd, "  \"running_seen\": %0d,", running_seen);
          $fdisplay(fd, "  \"timing_phase_first_cycle\": %0d,", timing_phase_first_cycle);
          $fdisplay(fd, "  \"timing_phase_last_cycle\": %0d,", timing_phase_last_cycle);
          $fdisplay(fd, "  \"trap_seen\": %0d,", trap_seen);
          $fdisplay(fd, "  \"trap_is_interrupt\": %0d,", trap_was_interrupt);
          $fdisplay(fd, "  \"trap_cause\": \"0x%08x\",", trap_cause_seen);
          $fdisplay(fd, "  \"trap_pc\": \"0x%08x\",", trap_pc_seen);
          $fdisplay(fd, "  \"trap_tval\": \"0x%08x\",", trap_tval_seen);
          $fdisplay(fd, "  \"words\": [");
          for (result_index = 0; result_index < RESULT_WORDS; result_index++) begin
            if (result_index == RESULT_WORDS-1)
              $fdisplay(fd, "    \"0x%08x\"", dut.i_dsram.mem[result_index]);
            else
              $fdisplay(fd, "    \"0x%08x\",", dut.i_dsram.mem[result_index]);
          end
          $fdisplay(fd, "  ]");
          $fdisplay(fd, "}");
          $fclose(fd);
        end else begin
          $display("BENCH_RESULT_JSON_OPEN_FAIL path=%0s", result_json);
        end
      end
    end
  endtask

  task automatic finish_fail(input string reason);
    begin
      fail_reason = reason;
      write_result_json(fail_reason, "BENCH_TB_FAIL");
      $display("BENCH_TB_FAIL reason=%0s cycles=%0d", fail_reason, observed_clock_cycles);
      $fatal(1, "RISCFORGE benchmark harness failure: %0s", fail_reason);
    end
  endtask

  task automatic finish_pass;
    begin
      write_result_json("none", "BENCH_TB_PASS");
      $display("BENCH_TB_PASS id=%0d cycles=%0d held_wb_cycles=%0d raw_wb_valid_cycles=%0d",
               requested_benchmark_id, observed_clock_cycles, held_wb_cycles, raw_wb_valid_cycles);
      $finish;
    end
  endtask

  initial begin : run_benchmark
    imem_hex = "";
    dmem_hex = "";
    result_json = "result.json";
    timeout_cycles = 1000000;
    requested_benchmark_id = 0;
    if (!$value$plusargs("IMEM_HEX=%s", imem_hex)) finish_fail("missing_imem_hex_plusarg");
    if (!$value$plusargs("DMEM_HEX=%s", dmem_hex)) finish_fail("missing_dmem_hex_plusarg");
    imem_hex = decode_path(imem_hex);
    dmem_hex = decode_path(dmem_hex);
    if (!$value$plusargs("RESULT_JSON=%s", result_json)) result_json = "result.json";
    if (!$value$plusargs("TIMEOUT_CYCLES=%d", timeout_cycles)) timeout_cycles = 1000000;
    if (!$value$plusargs("BENCHMARK_ID=%d", requested_benchmark_id))
      finish_fail("missing_benchmark_id_plusarg");
    if (timeout_cycles <= 0) finish_fail("invalid_timeout_cycles");
    if (requested_benchmark_id < 1 || requested_benchmark_id > 4)
      finish_fail("unsupported_benchmark_id");

    // Start with both resets low. Releasing hard reset while soft reset stays
    // asserted selects the bootloader's warm path and leaves both SRAMs intact.
    hard_rst_ni = 1'b0;
    soft_rst_ni = 1'b0;
    repeat (4) @(negedge clk_i);
    hard_rst_ni = 1'b1;

    for (boot_cycle = 0; boot_cycle < timeout_cycles; boot_cycle = boot_cycle + 1) begin
      @(negedge clk_i);
      if (dut.hard_rst_sync_n === 1'b1) break;
    end
    if (dut.hard_rst_sync_n !== 1'b1) finish_fail("hard_reset_sync_timeout");

    for (boot_cycle = 0; boot_cycle < timeout_cycles; boot_cycle = boot_cycle + 1) begin
      @(negedge clk_i);
      if (dut.i_bootloader.warm_boot_q === 1'b1) break;
    end
    if (dut.i_bootloader.warm_boot_q !== 1'b1) finish_fail("warm_boot_select_timeout");

    for (i = 0; i < ISRAM_WORDS; i = i + 1)
      dut.i_isram.u_imem.mem_array[i] = 32'h0000_0000;
    for (i = 0; i < DSRAM_WORDS; i = i + 1)
      dut.i_dsram.mem[i] = 32'h0000_0000;
    $readmemh(imem_hex, dut.i_isram.u_imem.mem_array);
    $readmemh(dmem_hex, dut.i_dsram.mem);
    for (i = 0; i < RESULT_WORDS; i = i + 1) begin
      if (dut.i_dsram.mem[i] !== 32'h0000_0000)
        finish_fail("result_block_not_empty_at_preload");
    end
    $display("BENCH_PRELOAD imem=%0s dmem=%0s", imem_hex, dmem_hex);

    soft_rst_ni = 1'b1;
    boot_reason = "warm_boot_release_timeout";
    for (boot_cycle = 0; boot_cycle < timeout_cycles; boot_cycle = boot_cycle + 1) begin
      @(negedge clk_i);
      if (dut.core_rst_n === 1'b1 && boot_done_o === 1'b1) begin
        boot_reason = "none";
        break;
      end
    end
    if (boot_reason != "none") finish_fail(boot_reason);

    monitor_enable = 1'b1;
    console_previous = dut.i_dsram.mem[WORD_CONSOLE];
    $display("BENCH_BOOT_READY timeout_cycles=%0d", timeout_cycles);

    for (run_cycle = 0; run_cycle < timeout_cycles; run_cycle = run_cycle + 1) begin
      @(negedge clk_i);

      if (dut.i_dsram.mem[WORD_CONSOLE] !== console_previous) begin
        console_previous = dut.i_dsram.mem[WORD_CONSOLE];
        $write("%c", console_previous[7:0]);
      end

      if (trap_seen) begin
        if (trap_was_interrupt) finish_fail("unexpected_interrupt_trap");
        else finish_fail("unexpected_synchronous_trap");
      end
      if (|apb_timeout_sticky_o) finish_fail("apb_timeout_sticky");
      if (axi_wr_timeout_sticky_o === 1'b1) finish_fail("axi_write_timeout_sticky");
      if (axi_rd_timeout_sticky_o === 1'b1) finish_fail("axi_read_timeout_sticky");

      current_magic = dut.i_dsram.mem[WORD_MAGIC];
      current_version = dut.i_dsram.mem[WORD_VERSION];
      current_status = dut.i_dsram.mem[WORD_STATUS];
      current_id = dut.i_dsram.mem[WORD_BENCHMARK_ID];
      current_validation_errors = dut.i_dsram.mem[WORD_VALIDATION_ERRORS];

      if (current_magic !== 32'h0 && current_magic !== RESULT_MAGIC)
        finish_fail("unknown_result_magic");
      if (current_magic === RESULT_MAGIC &&
          (current_status === 32'd1 || current_status === 32'd2 || current_status === 32'd3)) begin
        if (current_version !== RESULT_VERSION) finish_fail("unknown_result_version");
        if (current_id !== requested_benchmark_id) finish_fail("benchmark_id_mismatch");
        if (current_status === 32'd1) running_seen = 1'b1;
        // Let firmware finish publishing failure details before collecting the
        // terminal result. PASS still requires exactly zero validation errors.
        if (current_status === 32'd2) begin
          if (!running_seen) finish_fail("terminal_status_without_running");
          if (current_validation_errors !== 32'd0) finish_fail("firmware_validation_errors");
          cycle_delta = {dut.i_dsram.mem[WORD_CYCLE_END_HI], dut.i_dsram.mem[WORD_CYCLE_END_LO]} -
                        {dut.i_dsram.mem[WORD_CYCLE_START_HI], dut.i_dsram.mem[WORD_CYCLE_START_LO]};
          if (cycle_delta == 64'd0) finish_fail("zero_firmware_cycle_delta");
          finish_pass();
        end else if (current_status === 32'd3) begin
          if (!running_seen) finish_fail("terminal_status_without_running");
          finish_fail("firmware_status_fail");
        end
      end
      if (current_magic === RESULT_MAGIC &&
          current_status !== 32'd0 && current_status !== 32'd1 &&
          current_status !== 32'd2 && current_status !== 32'd3)
        finish_fail("unknown_result_status");
    end
    finish_fail("cycle_watchdog_timeout");
  end

  initial begin : optional_wave_dump
    string wave_enable;
    wave_enable = "";
    if ($value$plusargs("WAVES=%s", wave_enable) || $test$plusargs("WAVES")) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, soc_benchmark_tb);
    end
  end
endmodule
