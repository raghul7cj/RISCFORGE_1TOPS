// Functional coverage of real trap commitments. No scenario/model indices sample bins.
// The complete cause is {interrupt bit, cause}; current bins target F1/F2 synchronous cases.
// MODE bins sample the actual CSR on trap commitment, including Vectored mode.
module trap_functional_cov (
  core_pipeline_if.monitor pipe,
  output int unsigned trap_samples = 0,
  output int unsigned cause_hits[0:31],
  output int unsigned mode_hits[0:1],
  output int unsigned irq_hits[0:31],
  output int unsigned irq_entry_transitions = 0,
  output int unsigned return_transitions = 0
);
  covergroup cg_traps @(posedge pipe.clk);
    option.per_instance = 1;
    option.name = "trap_commits";
    cause: coverpoint {pipe.trap_interrupt, pipe.trap_cause}
      iff (pipe.rst_n && pipe.trap_valid) {
      bins illegal_instruction = {2};
      bins breakpoint = {3};
      bins load_misaligned = {4};
      bins store_misaligned = {6};
      bins machine_ecall = {11};
      bins machine_timer_irq = {32'h80000007};
      bins platform_fast_irq[] = {[32'h80000010:32'h8000001b]};
    }
    vector_mode: coverpoint pipe.csr_mtvec[1:0]
      iff (pipe.rst_n && pipe.trap_valid) {
      bins mode_direct = {0};
      bins mode_vectored = {1};
    }
    cause_by_mode: cross cause, vector_mode;
  endgroup
  cg_traps coverage_traps = new();

  bit previous_trap = 0;
  bit previous_irq = 0;
  bit previous_mret = 0;
  logic [31:0] previous_status = 0;
  covergroup cg_status @(posedge pipe.clk);
    option.per_instance = 1;
    option.name = "trap_status";
    entry_mie: coverpoint {previous_status[3],pipe.csr_mstatus[3]}
      iff (pipe.rst_n && previous_trap) { bins clear_mie = {2'b10}; bins masked_entry = {2'b00}; }
    entry_mpie: coverpoint {previous_status[7],pipe.csr_mstatus[7]}
      iff (pipe.rst_n && previous_trap) { bins changes[] = {[0:3]}; }
    return_mie: coverpoint {previous_status[3],pipe.csr_mstatus[3]}
      iff (pipe.rst_n && previous_mret) { bins restore_enabled = {2'b01}; bins restore_disabled = {2'b00}; }
    return_mpie: coverpoint {previous_status[7],pipe.csr_mstatus[7]}
      iff (pipe.rst_n && previous_mret) { bins set_from_zero = {2'b01}; bins remain_one = {2'b11}; }
  endgroup
  cg_status coverage_status = new();

  initial begin
    foreach (irq_hits[index]) irq_hits[index] = 0;
    foreach (cause_hits[index]) cause_hits[index] = 0;
    foreach (mode_hits[index]) mode_hits[index] = 0;
  end
  always @(posedge pipe.clk) begin
    if (!pipe.rst_n) begin
      previous_trap <= 0;
      previous_irq <= 0;
      previous_mret <= 0;
    end else begin
      if (previous_irq && previous_status[3] && !pipe.csr_mstatus[3]) irq_entry_transitions++;
      if (previous_mret && !previous_status[3] && pipe.csr_mstatus[3]) return_transitions++;
      previous_trap <= pipe.trap_valid;
      previous_irq <= pipe.trap_valid && pipe.trap_interrupt;
      previous_mret <= pipe.mret_commit;
      previous_status <= pipe.csr_mstatus;
    end
    if (pipe.rst_n && pipe.trap_valid) begin
      trap_samples++;
      if (pipe.trap_interrupt && !$isunknown(pipe.trap_cause) && pipe.trap_cause < 32)
        irq_hits[pipe.trap_cause]++;
      if (!pipe.trap_interrupt && !$isunknown(pipe.trap_cause) && pipe.trap_cause < 32)
        cause_hits[pipe.trap_cause]++;
      if (!$isunknown(pipe.csr_mtvec[1:0]) && pipe.csr_mtvec[1:0] < 2)
        mode_hits[pipe.csr_mtvec[1:0]]++;
    end
  end
  final begin
    $display("IRQ_COV timer=%0d external=%0d software=%0d fast0=%0d fast6=%0d mie_entry_clear=%0d mie_return_restore=%0d",
             irq_hits[7],irq_hits[11],irq_hits[3],irq_hits[16],irq_hits[22],irq_entry_transitions,return_transitions);
    $display("TRAP_COV samples=%0d illegal=%0d ebreak=%0d load=%0d store=%0d ecall=%0d direct=%0d vectored=%0d instance_pct=%0.2f",
             trap_samples, cause_hits[2], cause_hits[3], cause_hits[4], cause_hits[6], cause_hits[11],
             mode_hits[0], mode_hits[1], coverage_traps.get_inst_coverage());
  end
endmodule
