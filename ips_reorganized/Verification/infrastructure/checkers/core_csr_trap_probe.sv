module core_csr_trap_probe (
  input logic valid_w,
  input logic [31:0] pc_w,
  input logic exception_valid_w,
  input logic [31:0] exception_pc_w,
  input logic [5:0] exception_cause_w,
  input logic [31:0] exception_value_w,
  input logic trap_commit,
  input logic mret_commit,
  input logic retired_classified,
  input logic memory_write_observed,
  input logic [4:0] rd_w,
  input logic [31:0] result_w,
  input logic regwrite_gated,
  input logic csrwrite_gated,
  output logic observed_valid_w,
  output logic [31:0] observed_pc_w,
  output logic observed_exception_valid_w,
  output logic [31:0] observed_exception_pc_w,
  output logic [31:0] observed_exception_cause_w,
  output logic [31:0] observed_exception_value_w,
  output logic observed_trap_commit,
  output logic observed_mret_commit,
  output logic observed_retired_classified,
  output logic observed_memory_write,
  output logic [5:0] observed_exception_cause,
  output logic [4:0] observed_rd_w,
  output logic [31:0] observed_result_w,
  output logic observed_regwrite_gated,
  output logic observed_csrwrite_gated
);
  always_comb begin
    observed_valid_w = valid_w;
    observed_pc_w = pc_w;
    observed_exception_valid_w = exception_valid_w;
    observed_exception_pc_w = exception_pc_w;
    observed_exception_cause_w = {26'b0, exception_cause_w};
    observed_exception_value_w = exception_value_w;
    observed_trap_commit = trap_commit;
    observed_mret_commit = mret_commit;
    observed_retired_classified = retired_classified;
    observed_memory_write = memory_write_observed;
    observed_exception_cause = exception_cause_w;
    observed_rd_w = rd_w;
    observed_result_w = result_w;
    observed_regwrite_gated = regwrite_gated;
    observed_csrwrite_gated = csrwrite_gated;
  end
endmodule
