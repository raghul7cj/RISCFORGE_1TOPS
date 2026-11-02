// =============================================================================
// RISCFORGE 1TOPS — SoC transaction tracer: type package (testbench only)
// =============================================================================
// Bit-for-bit copies of the packed structs declared inside
// riscforge_soc_subsystem (Sections 1, 2 and 8). soc_tracer receives the SoC's
// own structs on its ports; because both sides are packed, the connection is a
// plain bit copy. soc_tracer checks every width against the SoC's $bits() at
// time 0 and stops with $fatal if the SoC layout has changed.
// =============================================================================
package soc_tracer_pkg;

  // ---- AXI-Lite (axi_req_t / axi_resp_t in riscforge_soc_subsystem) --------
  typedef struct packed {
    logic [31:0] addr;
    logic [2:0]  prot;
  } trc_ax_t;

  typedef struct packed {
    logic [31:0] data;
    logic [3:0]  strb;
  } trc_w_t;

  typedef struct packed {
    logic [1:0] resp;
  } trc_b_t;

  typedef struct packed {
    logic [31:0] data;
    logic [1:0]  resp;
  } trc_r_t;

  typedef struct packed {
    trc_ax_t aw;
    logic    aw_valid;
    trc_w_t  w;
    logic    w_valid;
    logic    b_ready;
    trc_ax_t ar;
    logic    ar_valid;
    logic    r_ready;
  } trc_axi_req_t;

  typedef struct packed {
    logic    aw_ready;
    logic    w_ready;
    trc_b_t  b;
    logic    b_valid;
    logic    ar_ready;
    trc_r_t  r;
    logic    r_valid;
  } trc_axi_resp_t;

  // ---- APB (apb_req_t / apb_resp_t) -----------------------------------------
  typedef struct packed {
    logic [31:0] paddr;
    logic [2:0]  pprot;
    logic        psel;
    logic        penable;
    logic        pwrite;
    logic [31:0] pwdata;
    logic [3:0]  pstrb;
  } trc_apb_req_t;

  typedef struct packed {
    logic        pready;
    logic [31:0] prdata;
    logic        pslverr;
  } trc_apb_resp_t;

  // ---- Address rule (rule_t) ------------------------------------------------
  typedef struct packed {
    int unsigned idx;
    logic [31:0] start_addr;
    logic [31:0] end_addr;
  } trc_rule_t;

  // ---- One cycle of pipeline state, kept in the tracer's ring buffer --------
  typedef struct packed {
    logic [31:0] pc_f, pc_d, pc_e, pc_m, pc_w;
    logic        v_d, v_e, v_m, v_w;
    logic [3:0]  stall;      // {F, D, E, M}
    logic [3:0]  flush;      // {D, E, M, W}
    logic        mem_stall, mul_stall, pcsrc, trap_redirect;
    logic        lsu_req, lsu_we, lsu_stall, lsu_err;
    logic [31:0] lsu_addr;
  } trc_pipe_t;

endpackage : soc_tracer_pkg
