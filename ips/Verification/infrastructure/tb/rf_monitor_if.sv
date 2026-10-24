// =============================================================================
// Module Name : rf_monitor_if.sv
// Description : RISCFORGE SoC passive-monitor interfaces.
//
//               Seven sampling interfaces + one pin-observation interface, plus
//               rf_timebase_if (the SINGLE shared cycle counter every monitor
//               stamps its transactions with).
//
// XSim 2022.2 constraints honoured here:
//   * every `clocking` block is declared BEFORE its `modport`
//   * NO unpacked or 2-D packed arrays anywhere in an interface body
//     -> the 6 APB PRDATA values are carried in one flat packed bus
//        `prdata_flat`, slot i occupying prdata_flat[i*32 +: 32]
//   * no `virtual interface`; monitors receive a plain interface handle
// =============================================================================

`ifndef RF_MONITOR_IF_SV
`define RF_MONITOR_IF_SV

`timescale 1ns/1ps

// =============================================================================
// 0. rf_timebase_if  -  THE shared cycle counter
// =============================================================================
// One instance lives in soc_tb_top. Every monitor interface re-exports `cycle`
// and `rel_cycle` as plain inputs so that all monitors sample the SAME value at
// the SAME preponed edge. That is what makes cross-monitor joins (LSU -> AXI ->
// APB -> RETIRE) exact instead of approximate.
interface rf_timebase_if #(
  parameter int unsigned CYCLE_W = 64
) (
  input logic clk,
  input logic rst_n
);
  timeunit      1ns;
  timeprecision 1ps;

  logic [CYCLE_W-1:0] cycle;        // absolute, free running, never cleared
  longint unsigned    rel_cycle;    // cycles since rst_n released

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle     <= '0;
      rel_cycle <= 0;
    end else begin
      cycle     <= cycle + 1'b1;
      rel_cycle <= rel_cycle + 1;
    end
  end

  // Purely for waveform visibility.
  initial begin
    cycle     = '0;
    rel_cycle = 0;
  end

  clocking mon_cb @(posedge clk);
    default input #1step;
    input cycle;
    input rel_cycle;
  endclocking

  modport MON (clocking mon_cb, input clk, input rst_n);
endinterface

// =============================================================================
// 1. rf_fetch_if  -  Core Fetch Monitor probe
// =============================================================================
// RTL source (rtl/ips/riscv_core/rtl/):
//   dut.i_riscv_core.Fetch.PCF          - current PC
//   dut.i_riscv_core.Fetch.PCPlus4F     - PC + 4
//   dut.i_riscv_core.Fetch.PC_next      - next PC (branch/jump resolved)
//   dut.i_riscv_core.Fetch.InstrF       - fetched instruction word
//   dut.i_riscv_core.Fetch.imem_stall   - imem backpressure
//   dut.i_riscv_core.Fetch.exc_valid_F  - fetch-stage exception
// NOTE: this core has NO if_valid / imem_ready. imem_sram_en is the fetch
//       request (1-cycle SRAM latency), and top.StallF is the IF-side stall.
interface rf_fetch_if (
  input logic clk,
  input logic rst_n
);
  timeunit 1ns; timeprecision 1ps;

  localparam string MON_NAME = "FETCH";

  // ---- DUT probes ----
  logic [31:0] pc;
  logic [31:0] pc_plus4;
  logic [31:0] pc_next;
  logic [31:0] instr;
  logic        fetch_en;      // imem_sram_en
  logic        stall_f;       // Fetch.imem_stall | top.StallF
  logic        exc_valid;
  logic [5:0]  exc_cause;
  logic [31:0] exc_tval;

  // ---- shared timebase / control ----
  logic [63:0] tb_cycle;
  logic [63:0] tb_rel_cycle;
  logic        freeze;

  // ---- monitor-maintained state ----
  logic [31:0] instr_at_pc;   // instruction shadow, for the retire monitor
  logic        instr_at_pc_v;

  clocking mon_cb @(posedge clk);
    default input #1step;
    input pc, pc_plus4, pc_next, instr;
    input fetch_en, stall_f;
    input exc_valid, exc_cause, exc_tval;
    input tb_cycle, tb_rel_cycle;
    input freeze;
    input instr_at_pc, instr_at_pc_v;
  endclocking

  modport MON (
    clocking mon_cb,
    input clk, input rst_n
  );
endinterface

// =============================================================================
// 2. rf_retire_if  -  Core Retire (architectural commit) probe
// =============================================================================
// RTL source:
//   dut.i_riscv_core.PC_W              - retiring PC
//   dut.i_riscv_core.RDW               - retiring rd
//   dut.i_riscv_core.ResultW           - retiring write data
//   dut.i_riscv_core.RegWriteW_gated   - architectural write enable
//   dut.i_riscv_core.valid_W           - stage valid
//   dut.i_riscv_core.wb_commit         - commit controller strobe
//   dut.i_riscv_core.trap_commit_valid - trap taken
//   dut.i_riscv_core.trap_commit_cause - 31-bit cause
//   dut.i_riscv_core.trap_commit_is_interrupt  <-- there is NO irq_ack net
//   dut.i_riscv_core.mret_commit       - mret retired
//   dut.i_riscv_core.csr_write_en_W / csr_addr_W / new_csr_W
//   dut.i_riscv_core.exc_cause_W / exc_tval_W / exc_pc_W
// The retired instruction word is NOT available in RTL; it is carried over from
// rf_fetch_if via the {instr, instr_at_pc_v} inputs (fetch PC -> retire PC join).
interface rf_retire_if (
  input logic clk,
  input logic rst_n
);
  timeunit 1ns; timeprecision 1ps;

  localparam string MON_NAME = "RETIRE";

  logic        valid_w;
  logic        wb_commit;
  logic [31:0] pc_w;
  logic [31:0] instr;
  logic [4:0]  rd_addr;
  logic [31:0] rd_wdata;
  logic        reg_we;

  logic        trap;
  logic        trap_is_interrupt;    // the irq_ack equivalent
  logic [30:0] trap_cause;
  logic [31:0] trap_pc;
  logic        is_mret;

  logic        csr_we;
  logic [11:0] csr_addr;
  logic [31:0] csr_wdata;

  logic        exc_valid;
  logic [5:0]  exc_cause;
  logic [31:0] exc_tval;
  logic [31:0] exc_pc;

  logic [63:0] tb_cycle;
  logic [63:0] tb_rel_cycle;
  logic        freeze;

  clocking mon_cb @(posedge clk);
    default input #1step;
    input valid_w, wb_commit, pc_w, instr, rd_addr, rd_wdata, reg_we;
    input trap, trap_is_interrupt, trap_cause, trap_pc, is_mret;
    input csr_we, csr_addr, csr_wdata;
    input exc_valid, exc_cause, exc_tval, exc_pc;
    input tb_cycle, tb_rel_cycle;
    input freeze;
  endclocking

  modport MON (
    clocking mon_cb,
    input clk, input rst_n
  );
endinterface

// =============================================================================
// 3. rf_lsu_if  -  LSU / core memory port probe
// =============================================================================
// RTL source (memory_cycle.v + top.v):
//   lsu_mem_req, lsu_mem_we, lsu_mem_addr[31:0], lsu_mem_wdata[31:0],
//   lsu_mem_be[3:0], lsu_mem_rdata[31:0], lsu_mem_stall, lsu_mem_err
//   PC_M, lsunitM[4:0], valid_M
interface rf_lsu_if (
  input logic clk,
  input logic rst_n
);
  timeunit 1ns; timeprecision 1ps;

  localparam string MON_NAME = "LSU";

  logic        valid_m;
  logic [31:0] pc_m;
  logic [4:0]  lsunit;

  logic        req;
  logic        we;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0]  be;
  logic [31:0] rdata;
  logic        stall;
  logic        err;

  logic [63:0] tb_cycle;
  logic [63:0] tb_rel_cycle;
  logic        freeze;

  clocking mon_cb @(posedge clk);
    default input #1step;
    input valid_m, pc_m, lsunit;
    input req, we, addr, wdata, be, rdata, stall, err;
    input tb_cycle, tb_rel_cycle;
    input freeze;
  endclocking

  modport MON (
    clocking mon_cb,
    input clk, input rst_n
  );
endinterface

// =============================================================================
// 4. rf_axil_if  -  AXI4-Lite protocol probe (5 independent handshakes)
// =============================================================================
// RTL source: the SoC does NOT use flat awaddr/awvalid nets. The AXI-Lite
// signals live inside packed structs on the xbar and bridge instances:
//   dut.core_axi_req / dut.core_axi_resp        (core <-> timeout monitor)
//   dut.xbar_slv_req[0] / dut.xbar_slv_resp[0]  (timeout monitor <-> xbar)
//   dut.xbar_mst_req[N] / dut.xbar_mst_resp[N]  (xbar <-> SRAM/APB bridge)
// soc_tb_top flattens one of those structs onto this interface with continuous
// assignments (see the "g_axil_flatten" generate block in soc_tb_top.sv).
// No IDs, no bursts, no LEN/SIZE/BURST: AXI-Lite only, AxiIdWidth == 0.
interface rf_axil_if #(
  parameter int unsigned ADDR_W = 32,
  parameter int unsigned DATA_W = 32,
  parameter int unsigned STRB_W = 4,
  parameter int unsigned PROT_W = 3,
  parameter int unsigned RESP_W = 2
) (
  input logic clk,
  input logic rst_n
);
  timeunit 1ns; timeprecision 1ps;

  localparam string MON_NAME = "AXILITE";

  // ---- Write address ----
  logic [ADDR_W-1:0] awaddr;
  logic [PROT_W-1:0] awprot;
  logic              awvalid;
  logic              awready;
  // ---- Write data ----
  logic [DATA_W-1:0] wdata;
  logic [STRB_W-1:0] wstrb;
  logic              wvalid;
  logic              wready;
  // ---- Write response ----
  logic [RESP_W-1:0] bresp;
  logic              bvalid;
  logic              bready;
  // ---- Read address ----
  logic [ADDR_W-1:0] araddr;
  logic [PROT_W-1:0] arprot;
  logic              arvalid;
  logic              arready;
  // ---- Read data ----
  logic [DATA_W-1:0] rdata;
  logic [RESP_W-1:0] rresp;
  logic              rvalid;
  logic              rready;

  // ---- shared ----
  logic [63:0] tb_cycle;
  logic [63:0] tb_rel_cycle;
  logic        freeze;

  clocking mon_cb @(posedge clk);
    default input #1step;
    input awaddr, awprot, awvalid, awready;
    input wdata, wstrb, wvalid, wready;
    input bresp, bvalid, bready;
    input araddr, arprot, arvalid, arready;
    input rdata, rresp, rvalid, rready;
    input tb_cycle, tb_rel_cycle;
    input freeze;
  endclocking

  modport MON (
    clocking mon_cb,
    input clk, input rst_n
  );
endinterface

// =============================================================================
// 5. rf_apb_if  -  APB per-peripheral probe for all 6 slots
// =============================================================================
// RTL source: apb_req_t {paddr,pprot,psel,penable,pwrite,pwdata,pstrb}
//             apb_resp_t{pready,prdata,pslverr}
// Probe points (bridge side, post timeout-monitor):
//   dut.apb_req[g] / dut.apb_resp[g]
// Probe points (slave side, pre timeout-monitor):
//   dut.apb_resp_slv[g]
// XSim-safe: PRDATA for all 6 slots rides in ONE flat packed bus.
//   slot i  ->  prdata_flat[i*32 +: 32]      (use prdata_of(i))
interface rf_apb_if #(
  parameter int unsigned NUM_SLOTS = 6,
  parameter int unsigned ADDR_W    = 32,
  parameter int unsigned DATA_W    = 32,
  parameter int unsigned STRB_W    = 4,
  parameter int unsigned PROT_W    = 3
) (
  input logic clk,
  input logic rst_n
);
  timeunit 1ns; timeprecision 1ps;

  localparam string MON_NAME = "APB";

  // The bridge only defines request fields for the selected slot. Keep one
  // copy per slot so the monitor never samples inactive/undefined fields.
  logic [NUM_SLOTS*ADDR_W-1:0]  paddr_flat;
  logic [NUM_SLOTS*PROT_W-1:0]  pprot_flat;
  logic [NUM_SLOTS-1:0]         psel;
  logic [NUM_SLOTS-1:0]         penable;
  logic [NUM_SLOTS-1:0]         pwrite;
  logic [NUM_SLOTS*DATA_W-1:0]  pwdata_flat;
  logic [NUM_SLOTS*STRB_W-1:0]  pstrb_flat;
  // Selected-slot scalar view for class monitors. XSim 2022.2 can mis-sample
  // variable slices of packed vectors through virtual interfaces.
  logic [ADDR_W-1:0]            active_paddr;
  logic [DATA_W-1:0]            active_pwdata;
  logic [DATA_W-1:0]            active_prdata;
  logic [STRB_W-1:0]            active_pstrb;
  logic                         active_pwrite;
  logic [NUM_SLOTS-1:0]         pready;
  logic [NUM_SLOTS*DATA_W-1:0]  prdata_flat;
  logic [NUM_SLOTS-1:0]         pslverr;

  logic [63:0] tb_cycle;
  logic [63:0] tb_rel_cycle;
  logic        freeze;

  // Slot i is selected on PSEL && PENABLE && PREADY - the APB "access" phase.
  function automatic bit access(int unsigned i);
    return psel[i] && penable[i] && pready[i];
  endfunction

  function automatic bit setup(int unsigned i);
    return psel[i] && !penable[i];
  endfunction

  function automatic logic [DATA_W-1:0] prdata_of(int unsigned i);
    return prdata_flat[i*DATA_W +: DATA_W];
  endfunction

  function automatic string slot_name(int unsigned i);
    case (i)
      0:    return "I2C";
      1:    return "TIMER0";
      2:    return "UART";
      3:    return "GPIO";
      4:    return "SPI";
      5:    return "TIMER1";
      default: return "UNMAPPED";
    endcase
  endfunction

  // Payload buses remain direct interface reads to avoid XSim's known clocking
  // block sampling issue for packed arrays. APB holds them stable through access.
  clocking mon_cb @(posedge clk);
    default input #1step;
    input psel, penable, pwrite;
    input pready, pslverr;
    input tb_cycle, tb_rel_cycle;
    input freeze;
  endclocking

  modport MON (
    clocking mon_cb,
    input clk, input rst_n
  );
endinterface

// =============================================================================
// 6. rf_irq_if  -  Interrupt lifecycle probe
// =============================================================================
// RTL source:
//   raw sources   : gpio_global_interrupt_o, i2c_interrupt_o, spi_events_o[1:0],
//                   uart_int_o, timer0_irq_o[3:0], timer1_irq_o[3:0]
//   core inbound  : fast_irq_i[15:0], timer_irq_i (MTIP)
//   gateway       : dut.i_riscv_core.u_irq_gateway.pend_o[5:0]
//   arbiter       : irq_pending, irq_cause_enc[4:0], irq_id[30:0], irq_class[1:0]
//   CSRs          : csr_mip_sb, csr_mie_sb, csr_mstatus_mie_sb, csr_mintprio_sb
//   acknowledgement: trap_commit_is_interrupt (there is no irq_ack net)
interface rf_irq_if (
  input logic clk,
  input logic rst_n
);
  timeunit 1ns; timeprecision 1ps;

  localparam string MON_NAME = "IRQ";

  // ---- raw peripheral sources ----
  logic        gpio_irq;      // gpio_global_interrupt_o
  logic [31:0] gpio_pin_irq;  // gpio_pin_level_interrupts_o
  logic        i2c_irq;       // i2c_interrupt_o
  logic [1:0]  spi_irq;       // spi_events_o
  logic        uart_irq;      // uart_int_o
  logic [3:0]  timer0_irq;    // timer0_irq_o  [2N]=ovf [2N+1]=cmp
  logic [3:0]  timer1_irq;    // timer1_irq_o

  // ---- gateway ----
  logic [5:0]  gateway_pend;    // u_irq_gateway.pend_o
  logic [5:0]  gateway_pend_q;  // u_irq_gateway.pend_q (sticky latch)

  // ---- core inbound / CSR view ----
  logic [15:0] fast_irq;      // core fast_irq_i
  logic        timer_irq;     // MTIP
  logic [31:0] mip;           // csr_mip_sb
  logic [31:0] mie;           // csr_mie_sb
  logic [31:0] mintprio;      // csr_mintprio_sb
  logic        mstatus_mie;

  // ---- arbiter outputs ----
  logic        irq_valid;
  logic        irq_pending;
  logic [4:0]  irq_cause_enc;
  logic [30:0] irq_id;
  logic [1:0]  irq_class;
  logic        rr_ptr_c1;     // arbiter Class 1 RR pointer
  logic        rr_ptr_c0;     // arbiter Class 0 RR pointer

  // ---- shadow stack observables ----
  logic [1:0]  nest_depth;
  logic [1:0]  cur_class;
  logic [63:0] mepc_stack_flat;   // {mepc_stack[1], mepc_stack[0]}
  logic [63:0] mcause_stack_flat; // {mcause_stack[1], mcause_stack[0]}

  // ---- acknowledgement / commit ----
  logic        trap_is_interrupt;   // <-- the "irq_ack" the user asked for
  logic [30:0] trap_cause;
  logic [31:0] trap_pc;
  logic        mret_commit;

  logic [63:0] tb_cycle;
  logic [63:0] tb_rel_cycle;
  logic        freeze;

  clocking mon_cb @(posedge clk);
    default input #1step;
    input gpio_irq, gpio_pin_irq, i2c_irq, spi_irq, uart_irq;
    input timer0_irq, timer1_irq, gateway_pend, gateway_pend_q;
    input fast_irq, timer_irq, mip, mie, mintprio, mstatus_mie;
    input irq_valid, irq_pending, irq_cause_enc, irq_id, irq_class;
    input rr_ptr_c1, rr_ptr_c0;
    input nest_depth, cur_class, mepc_stack_flat, mcause_stack_flat;
    input trap_is_interrupt, trap_cause, trap_pc, mret_commit;
    input tb_cycle, tb_rel_cycle;
    input freeze;
  endclocking

  modport MON (
    clocking mon_cb,
    input clk, input rst_n
  );
endinterface

// =============================================================================
// 7. rf_pin_if  -  External pin observation (UART / I2C / SPI / GPIO)
// =============================================================================
// RTL source (SoC top ports):
//   uart : uart_sin_i, uart_sout_o, uart_int_o
//   i2c  : i2c_scl_i/o/oen_o, i2c_sda_i/o/oen_o, i2c_interrupt_o
//          open drain -> drive 0 when (oen && !out), else release to pull-up.
//          The TB owns the tri-state wires; `scl`/`sda` here are the RESOLVED
//          lines and `scl_o`/`scl_oen` are the raw pad drivers.
//   spi  : spi_clk_o, spi_csn0_o, spi_csn1_o (ACTIVE LOW), spi_sdo0_o (MOSI),
//          spi_sdi1_i (MISO), spi_events_o[1:0]
//   gpio : gpio_in_i[31:0], gpio_out_o[31:0], gpio_tx_en_o[31:0] (1 = driven),
//          gpio_in_sync_o[31:0], gpio_global_interrupt_o,
//          gpio_pin_level_interrupts_o[31:0]
interface rf_pin_if #(
  parameter int unsigned NGPIO = 32
) (
  input logic clk,
  input logic rst_n
);
  timeunit 1ns; timeprecision 1ps;

  localparam string MON_NAME = "PIN";

  // ---- UART ----
  logic uart_rx;      // uart_sin_i
  logic uart_tx;      // uart_sout_o
  logic uart_irq;     // uart_int_o

  // ---- I2C (resolved lines + raw open-drain drivers) ----
  logic scl;          // resolved SCL (pull-up accounted for)
  logic sda;          // resolved SDA
  logic scl_i;        // i2c_scl_i
  logic sda_i;        // i2c_sda_i
  logic scl_o;        // i2c_scl_o
  logic scl_oen;      // i2c_scl_oen_o
  logic sda_o;        // i2c_sda_o
  logic sda_oen;      // i2c_sda_oen_o
  logic i2c_irq;      // i2c_interrupt_o

  // ---- SPI ----
  logic sclk;         // spi_clk_o
  logic csn0;         // spi_csn0_o  (active low)
  logic csn1;         // spi_csn1_o  (active low)
  logic mosi;         // spi_sdo0_o
  logic miso;         // spi_sdi1_i
  logic [1:0] spi_events;

  // ---- GPIO ----
  logic [NGPIO-1:0] gpio_in;
  logic [NGPIO-1:0] gpio_out;
  logic [NGPIO-1:0] gpio_oe;       // 1 = output driven
  logic [NGPIO-1:0] gpio_in_sync;
  logic [NGPIO-1:0] gpio_pin_irq;
  logic             gpio_global_irq;

  logic [63:0] tb_cycle;
  logic [63:0] tb_rel_cycle;
  logic        freeze;

  // ---- monitor-maintained edge state (updated by the class monitors) ----
  logic scl_d, sda_d, sclk_d, mosi_d, miso_d;
  logic uart_tx_d, uart_rx_d;
  logic [NGPIO-1:0] gpio_in_d;

  clocking mon_cb @(posedge clk);
    default input #1step;
    input uart_rx, uart_tx, uart_irq;
    input scl, sda, scl_i, sda_i, scl_o, scl_oen, sda_o, sda_oen, i2c_irq;
    input sclk, csn0, csn1, mosi, miso, spi_events;
    input gpio_in, gpio_out, gpio_oe, gpio_in_sync, gpio_pin_irq, gpio_global_irq;
    input tb_cycle, tb_rel_cycle;
    input freeze;
    input scl_d, sda_d, sclk_d, mosi_d, miso_d;
    input uart_tx_d, uart_rx_d;
  endclocking

  modport MON (
    clocking mon_cb,
    input clk, input rst_n
  );
endinterface

// =============================================================================
// 8. rf_if_ports  -  interface bundle for passing handles into classes
// =============================================================================
// XSim 2022.2 CANNOT name an interface type in a class formal argument list
// (verified: `function new(i3_if v)` -> "'i3_if' is not declared"). An
// interface type IS legal as a class MEMBER and inside class task bodies, so
// the bundle-class pattern is the portable way to hand interfaces to the
// monitor constructors. On VCS / Xcelium the constructors could take the
// interfaces directly.
class rf_if_ports;
  virtual rf_timebase_if tb;
  virtual rf_fetch_if    fetch;
  virtual rf_retire_if   retire;
  virtual rf_lsu_if      lsu;
  virtual rf_axil_if     axil;
  virtual rf_apb_if      apb;
  virtual rf_irq_if      irq;
  virtual rf_pin_if      pin;

  function new();
    tb     = null;
    fetch  = null;
    retire = null;
    lsu    = null;
    axil   = null;
    apb    = null;
    irq    = null;
    pin    = null;
  endfunction
endclass : rf_if_ports

`endif // RF_MONITOR_IF_SV
