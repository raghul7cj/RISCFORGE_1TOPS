module tb_core_csr_trap;
  timeunit 1ns;
  timeprecision 1ps;

  import csr_trap_types_pkg::*;
  import csr_trap_env_pkg::*;

  localparam logic [31:0] RESET_PC = 32'h80000000;

  logic clk = 1'b0;
  core_corner_if core_if(clk);
  corner_env environment;
  scenario_cfg initial_cfg;
  scenario_cfg_t cfg_value;

  always #5ns clk = ~clk;

  top #(.RESET_PC(RESET_PC)) core (
    .clk(clk),
    .rst(core_if.rst_n),
    .PCSrcE1(core_if.redirect),
    .imem_sram_en(core_if.imem_enable),
    .imem_sram_we(core_if.imem_write),
    .imem_sram_wmask(core_if.imem_mask),
    .imem_sram_addr(core_if.imem_address),
    .imem_sram_wdata(core_if.imem_wdata),
    .imem_sram_rdata(core_if.imem_rdata),
    .lsu_mem_req(core_if.dmem_request),
    .lsu_mem_we(core_if.dmem_write),
    .lsu_mem_addr(core_if.dmem_address),
    .lsu_mem_wdata(core_if.dmem_wdata),
    .lsu_mem_be(core_if.dmem_byte_enable),
    .lsu_mem_rdata(core_if.dmem_rdata),
    .lsu_mem_stall(core_if.dmem_stall),
    .lsu_mem_err(core_if.dmem_error),
    .fast_irq_i(core_if.fast_irq),
    .timer_irq_i(core_if.timer_irq),
    .ext_irq_i(core_if.external_irq),
    .sw_irq_i(core_if.software_irq)
  );

  core_corner_imem instruction_memory (
    .clk(clk),
    .reset_n(core_if.rst_n),
    .enable(core_if.imem_enable),
    .write_enable(core_if.imem_write),
    .byte_mask(core_if.imem_mask),
    .address(core_if.imem_address),
    .write_data(core_if.imem_wdata),
    .read_data(core_if.imem_rdata)
  );

  core_corner_dmem data_memory (
    .clk(clk),
    .reset_n(core_if.rst_n),
    .request(core_if.dmem_request),
    .write(core_if.dmem_write),
    .address(core_if.dmem_address),
    .write_data(core_if.dmem_wdata),
    .byte_enable(core_if.dmem_byte_enable),
    .read_data(core_if.dmem_rdata),
    .stall(core_if.dmem_stall),
    .error(core_if.dmem_error)
  );

  core_csr_trap_probe passive_probe (
    .valid_w(core.valid_W),
    .pc_w(core.PC_W),
    .exception_valid_w(core.exc_valid_W),
    .exception_pc_w(core.exc_pc_W),
    .exception_cause_w(core.exc_cause_W),
    .exception_value_w(core.exc_tval_W),
    .trap_commit(core.trap_commit_valid),
    .mret_commit(core.mret_commit),
    .retired_classified(core.valid_W & ~core.exc_valid_W),
    .memory_write_observed(core_if.dmem_write),
    .rd_w(core.RDW),
    .result_w(core.ResultW),
    .regwrite_gated(core.RegWriteW_gated),
    .csrwrite_gated(core.csr_write_en_W_gated),
    .observed_valid_w(core_if.observe_valid_w),
    .observed_pc_w(core_if.observe_pc_w),
    .observed_exception_valid_w(core_if.observe_exception_valid_w),
    .observed_exception_pc_w(core_if.observe_exception_pc_w),
    .observed_exception_cause_w(core_if.observe_exception_cause_w),
    .observed_exception_value_w(core_if.observe_exception_value_w),
    .observed_trap_commit(core_if.observe_trap_commit),
    .observed_mret_commit(core_if.observe_mret_commit),
    .observed_retired_classified(core_if.observe_retired_classified),
    .observed_memory_write(core_if.observe_memory_write),
    .observed_exception_cause(core_if.observe_exception_cause),
    .observed_rd_w(core_if.observe_rd_w),
    .observed_result_w(core_if.observe_result_w),
    .observed_regwrite_gated(core_if.observe_regwrite_gated),
    .observed_csrwrite_gated(core_if.observe_csrwrite_gated)
  );

  core_csr_trap_assertions passive_assertions (
    .clk(clk),
    .reset_n(core_if.rst_n)
  );

  assign core_if.csr_state_mtvec = core.csr_mtvec_sb;
  assign core_if.csr_state_mepc = core.csr_mepc_sb;
  assign core_if.csr_state_mip = core.csr_mip_sb;
  assign core_if.csr_state_mstatus = core.csr_mstatus_sb;

  initial begin
    core_if.rst_n = 1'b0;
    core_if.fast_irq = '0;
    core_if.timer_irq = 1'b0;
    core_if.external_irq = 1'b0;
    core_if.software_irq = 1'b0;
    cfg_value.test_id = "UNSELECTED";
    cfg_value.seed = 0;
    cfg_value.expectation_version = "UNSET";
    initial_cfg = new(cfg_value);
    environment = new(core_if);
    environment.run(initial_cfg);
    repeat (3) @(negedge clk);
    environment.stop();
    $finish;
  end

  always @(core_if.observe_cb) begin : passive_event_capture
    core_event_t event_data;

    if (core_if.observe_cb.rst_n &&
        (core_if.observe_cb.observe_valid_w || core_if.observe_cb.observe_trap_commit ||
         core_if.observe_cb.observe_mret_commit || core_if.observe_cb.dmem_request)) begin
      event_data = '0;
      event_data.phase = PIPELINE_SAMPLE;
      event_data.observed_at = $time;
      event_data.pc_w = core_if.observe_cb.observe_pc_w;
      event_data.exception_pc = core_if.observe_cb.observe_exception_pc_w;
      event_data.exception_cause = core_if.observe_cb.observe_exception_cause;
      event_data.exception_tval = core_if.observe_cb.observe_exception_value_w;
      event_data.memory_address = core_if.observe_cb.dmem_address;
      event_data.memory_wdata = core_if.observe_cb.dmem_wdata;
      event_data.memory_byte_enable = core_if.observe_cb.dmem_byte_enable;
      event_data.valid_w = core_if.observe_cb.observe_valid_w;
      event_data.retired_classified = core_if.observe_cb.observe_retired_classified;
      event_data.exception_valid = core_if.observe_cb.observe_exception_valid_w;
      event_data.trap_commit = core_if.observe_cb.observe_trap_commit;
      event_data.mret_commit = core_if.observe_cb.observe_mret_commit;
      event_data.memory_request = core_if.observe_cb.dmem_request;
      event_data.memory_write = core_if.observe_cb.observe_memory_write;
      event_data.rd_w = core_if.observe_cb.observe_rd_w;
      event_data.result_w = core_if.observe_cb.observe_result_w;
      event_data.regwrite_gated = core_if.observe_cb.observe_regwrite_gated;
      event_data.csrwrite_gated = core_if.observe_cb.observe_csrwrite_gated;
      environment.publish(event_data);
    end
  end

  always @(core_if.state_cb) begin : passive_state_capture
    core_event_t state_data;

    if (core_if.state_cb.rst_n) begin
      state_data = '0;
      state_data.phase = CSR_STATE_SAMPLE;
      state_data.observed_at = $time;
      state_data.csr_mtvec = core_if.state_cb.csr_state_mtvec;
      state_data.csr_mepc = core_if.state_cb.csr_state_mepc;
      state_data.csr_mip = core_if.state_cb.csr_state_mip;
      state_data.csr_mstatus = core_if.state_cb.csr_state_mstatus;
      environment.publish(state_data);
    end
  end
endmodule
