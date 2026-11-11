module tb_csr_corner_unit;
  timeunit 1ns;
  timeprecision 1ps;

  import csr_trap_coverage_pkg::*;

  logic clk = 1'b0;
  csr_corner_if csr_if(clk);
  typedef struct packed {
    logic [11:0] address;
    logic [31:0] observed_data;
    logic valid;
  } csr_observation_t;

  always #5ns clk = ~clk;

  csr_regfile #(.XLEN(32)) dut (
    .clk_i(clk),
    .rst_n_i(csr_if.rst_n),
    .csr_valid_o(csr_if.csr_valid),
    .csr_raddr_i(csr_if.read_address),
    .csr_rdata_o(csr_if.read_data),
    .csr_waddr_normal_i(csr_if.write_address),
    .csr_wdata_normal_i(csr_if.write_data),
    .csr_write_en_normal_i(csr_if.write_enable),
    .csr_waddr_mret_i(csr_if.mret_address),
    .csr_wdata_mret_i(csr_if.mret_data),
    .csr_write_en_mret_i(csr_if.mret_write_enable),
    .mret_commit_i(csr_if.mret_commit),
    .trap_valid_i(csr_if.trap_valid),
    .trap_cause_i(csr_if.trap_cause),
    .trap_pc_i(csr_if.trap_pc),
    .trap_addr_i(csr_if.trap_address),
    .trap_addr_valid_i(csr_if.trap_address_valid),
    .trap_is_interrupt_i(csr_if.trap_is_interrupt),
    .instr_retired_i(csr_if.instruction_retired),
    .timer_intr_i(csr_if.timer_interrupt),
    .ext_intr_i(csr_if.external_interrupt),
    .msft_intr_i(csr_if.software_interrupt),
    .fast_intr_i(csr_if.fast_interrupt),
    .mtvec_out_o(csr_if.mtvec),
    .mie_out_o(csr_if.mie),
    .mip_out_o(csr_if.mip),
    .mstatus_mie_out_o(csr_if.mstatus_mie),
    .mepc_out_o(csr_if.mepc),
    .mcause_out_o(csr_if.mcause),
    .mstatus_out_o(csr_if.mstatus),
    .mintprio_out_o(csr_if.mintprio)
  );

  observed_corner_coverage coverage_collector;
  int checks = 0;
  int failures = 0;
  int pending_cases = 0;
  int scenario_index = 0;
  int causes [0:20] = '{0, 2, 3, 4, 5, 6, 7, 11,
                       7, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27};
  logic [11:0] targets [0:12] = '{12'h300, 12'h304, 12'h305, 12'h340,
      12'h341, 12'h342, 12'h343, 12'h7c0, 12'h344,
      12'hb00, 12'hb80, 12'hb02, 12'hb82};

  task automatic clear_controls();
    csr_if.read_address = '0;
    csr_if.write_address = '0;
    csr_if.write_data = '0;
    csr_if.write_enable = 1'b0;
    csr_if.mret_address = '0;
    csr_if.mret_data = '0;
    csr_if.mret_write_enable = 1'b0;
    csr_if.mret_commit = 1'b0;
    csr_if.trap_valid = 1'b0;
    csr_if.trap_cause = '0;
    csr_if.trap_pc = '0;
    csr_if.trap_address = '0;
    csr_if.trap_address_valid = 1'b0;
    csr_if.trap_is_interrupt = 1'b0;
    csr_if.instruction_retired = 1'b0;
    csr_if.timer_interrupt = 1'b0;
    csr_if.external_interrupt = 1'b0;
    csr_if.software_interrupt = 1'b0;
    csr_if.fast_interrupt = '0;
  endtask

  task automatic reset_case();
    @(negedge clk);
    clear_controls();
    csr_if.rst_n = 0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    csr_if.rst_n = 1;
  endtask

  task automatic write_csr(input logic [11:0] address,
                           input logic [31:0] value);
    @(negedge clk);
    csr_if.write_address = address;
    csr_if.write_data = value;
    csr_if.write_enable = 1;
    @(posedge clk);
    #1ns;
    @(negedge clk);
    csr_if.write_enable = 0;
  endtask

  task automatic check_word(input string name,
                            input logic [31:0] actual,
                            input logic [31:0] expected);
    checks++;
    if (actual !== expected) begin
      failures++;
      $display("UNIT_CHECK_FAIL|%s|actual=%08x|expected=%08x", name, actual, expected);
    end
  endtask

  task automatic status_cases();
    int index;
    int before_failures;
    for (int event_kind = 0; event_kind < 2; event_kind++) begin
      for (int old_mie = 0; old_mie < 2; old_mie++) begin
        for (int old_mpie = 0; old_mpie < 2; old_mpie++) begin
          index = event_kind*4 + old_mie*2 + old_mpie;
          reset_case();
          write_csr(12'h340, 32'h12345678);
          write_csr(12'h300, (old_mie << 3) | (old_mpie << 7));
          before_failures = failures;
          @(negedge clk);
          csr_if.trap_valid = event_kind == 0;
          csr_if.mret_commit = event_kind == 1;
          @(posedge clk);
          #1ns;
          coverage_collector.sample_bin(0, index);
          check_word("status.MIE", {31'b0, csr_if.mstatus[3]}, event_kind == 0 ? 0 : old_mpie);
          check_word("status.MPIE", {31'b0, csr_if.mstatus[7]}, event_kind == 0 ? old_mie : 1);
          csr_if.read_address = 12'h340;
          #1ns;
          check_word("preserved_mscratch", csr_if.read_data, 32'h12345678);
          $display("UNIT_RESULT|0|%0d|CHECKED|%0d", index, failures-before_failures);
        end
      end
    end
  endtask

  task automatic metadata_cases();
    int index = 0;
    int before_failures;
    logic [31:0] expected_pc;
    logic [31:0] expected_value;
    for (int cause_index = 0; cause_index < 21; cause_index++) begin
      for (int pc_pattern = 0; pc_pattern < 2; pc_pattern++) begin
        for (int valid_address = 0; valid_address < 2; valid_address++) begin
          for (int value_pattern = 0; value_pattern < 2; value_pattern++) begin
            reset_case();
            expected_pc = pc_pattern ? 32'h80000124 : 0;
            expected_value = value_pattern ? 32'h87654321 : 0;
            before_failures = failures;
            csr_if.trap_cause = causes[cause_index];
            csr_if.trap_is_interrupt = cause_index >= 8;
            csr_if.trap_pc = expected_pc;
            csr_if.trap_address = expected_value;
            csr_if.trap_address_valid = valid_address;
            csr_if.trap_valid = 1;
            @(posedge clk);
            #1ns;
            coverage_collector.sample_bin(1, index);
            check_word("trap.mepc", csr_if.mepc, expected_pc);
            check_word("trap.mcause", csr_if.mcause,
                       (cause_index >= 8 ? 32'h80000000 : 0) | causes[cause_index]);
            csr_if.read_address = 12'h343;
            #1ns;
            check_word("trap.mtval", csr_if.read_data, valid_address ? expected_value : 0);
            $display("UNIT_RESULT|1|%0d|CHECKED|%0d", index, failures-before_failures);
            index++;
          end
        end
      end
    end
  endtask

  task automatic collision_cases();
    int index = 0;
    for (int event_kind = 0; event_kind < 3; event_kind++) begin
      for (int target = 0; target < 13; target++) begin
        reset_case();
        write_csr(targets[target], 32'h12345678);
        @(negedge clk);
        csr_if.write_address = targets[target];
        csr_if.write_data = 32'h89abcdef;
        csr_if.write_enable = 1;
        csr_if.trap_valid = event_kind != 1;
        csr_if.mret_commit = event_kind != 0;
        csr_if.trap_pc = 32'h80000120;
        csr_if.trap_cause = 11;
        @(posedge clk);
        #1ns;
        coverage_collector.sample_bin(2, index);
        csr_if.read_address = targets[target];
        #1ns;
        $display("UNIT_RESULT|2|%0d|SPEC_PENDING|0|observed=%08x", index, csr_if.read_data);
        pending_cases++;
        index++;
      end
    end
    reset_case();
    csr_if.trap_valid = 1;
    csr_if.mret_commit = 1;
    @(posedge clk);
    #1ns;
    coverage_collector.sample_bin(2, index);
    pending_cases++;
    $display("UNIT_RESULT|2|%0d|SPEC_PENDING|0", index);
  endtask

  task automatic counter_cases();
    logic [11:0] low_address;
    logic [11:0] high_address;
    logic [63:0] before_value;
    logic [63:0] after_value;
    int index = 0;
    for (int counter = 0; counter < 2; counter++) begin
      low_address = counter == 0 ? 12'hb00 : 12'hb02;
      high_address = counter == 0 ? 12'hb80 : 12'hb82;
      for (int boundary = 0; boundary < 2; boundary++) begin
        reset_case();
        write_csr(high_address, boundary ? 32'hffffffff : 0);
        write_csr(low_address, 32'hffffffff);
        csr_if.instruction_retired = 1;
        before_value = counter == 0 ? dut.mcycle_r : dut.minstret_r;
        @(posedge clk);
        #1ns;
        after_value = counter == 0 ? dut.mcycle_r : dut.minstret_r;
        if (after_value[31:0] < before_value[31:0])
          coverage_collector.sample_bin(3, index);
        $display("UNIT_RESULT|3|%0d|SPEC_PENDING|0|before=%016x|after=%016x", index, before_value, after_value);
        pending_cases++;
        index++;
      end
    end
    for (int counter = 0; counter < 2; counter++) begin
      for (int half = 0; half < 2; half++) begin
        for (int event_kind = 0; event_kind < 3; event_kind++) begin
          reset_case();
          csr_if.instruction_retired = 1;
          csr_if.write_address = counter == 0 ? (half ? 12'hb80 : 12'hb00) : (half ? 12'hb82 : 12'hb02);
          csr_if.write_data = 32'h13579bdf;
          csr_if.write_enable = 1;
          csr_if.trap_valid = event_kind == 1;
          csr_if.mret_commit = event_kind == 2;
          @(posedge clk);
          #1ns;
          coverage_collector.sample_bin(3, index);
          $display("UNIT_RESULT|3|%0d|SPEC_PENDING|0", index);
          pending_cases++;
          index++;
        end
      end
    end
  endtask

  task automatic reset_cases();
    int before_failures;
    for (int event_kind = 0; event_kind < 4; event_kind++) begin
      reset_case();
      write_csr(12'h340, 32'h12345678);
      before_failures = failures;
      @(negedge clk);
      csr_if.write_enable = event_kind == 0 || event_kind == 3;
      csr_if.trap_valid = event_kind == 1 || event_kind == 3;
      csr_if.mret_commit = event_kind == 2;
      csr_if.rst_n = 0;
      @(posedge clk);
      #1ns;
      coverage_collector.sample_bin(4, event_kind);
      check_word("reset.mstatus", csr_if.mstatus, 0);
      check_word("reset.mie", csr_if.mie, 0);
      check_word("reset.mepc", csr_if.mepc, 0);
      check_word("reset.mcause", csr_if.mcause, 0);
      check_word("reset.mcycle", dut.mcycle_r[31:0], 0);
      check_word("reset.minstret", dut.minstret_r[31:0], 0);
      $display("UNIT_RESULT|4|%0d|CHECKED|%0d", event_kind, failures-before_failures);
    end
  endtask

  initial begin
    coverage_collector = new(1);
    csr_if.rst_n = 0;
    clear_controls();
    status_cases();
    metadata_cases();
    collision_cases();
    counter_cases();
    reset_cases();
    coverage_collector.report();
    $display("UNIT_DONE|checks=%0d|failures=%0d|spec_pending=%0d", checks, failures, pending_cases);
    // TODO(USER_REF_MODEL): Full independently signed-off reference model remains deferred.
    $finish;
  end
endmodule
