// =============================================================================
`include "step4_cfg.svh"
//  RISCFORGE SoC  --  Verification Infrastructure, Step 4
//  step4_pkg.sv : shared constants, types, check IDs, transaction records
// =============================================================================
//  Predecessor: "SoC Verification Infrastructure: Integration Guide" Step 4,
//  "Checkers and failure reporter".
//
//  SINGLE SOURCE OF TRUTH. Every constant here is copied verbatim from the RTL
//  it checks. Source of each value is given as <file>:<line>. If you change the
//  RTL address map you change it here, and only here.
//
//    riscforge_soc_subsystem.sv:678-680   xbar_addr_map[0..2]
//    riscforge_soc_subsystem.sv:683-690   apb_addr_map[0..5]
//    riscforge_soc_subsystem.sv:463-470   APB_TIMEOUT_CYCLES[0..5]
//    riscforge_soc_subsystem.sv:476-477   AXI_TIMEOUT_SRAM / AXI_TIMEOUT_APB
//    riscforge_soc_subsystem.sv:244       NUM_APB_SLAVES
//    hybrid_mem_interface.sv:61-72        SRAM_BASE / SRAM_LIMIT / MMIO range
//    axi_lite_to_apb.sv:305,333           paddr is 4-byte ALIGNED
//    addr_decode.sv:53-54                 start inclusive, end EXCLUSIVE
//    gpio_apb_wrap.sv                     sub-word (PSTRB != 4'hF) write => PSLVERR
// =============================================================================

package step4_pkg;

  // ---------------------------------------------------------------------------
  // 1. Layer taxonomy  (Integration Guide section 3, "Observe and check in layers")
  //
  //    Lower number = more fundamental. A protocol error explains many
  //    higher-layer symptoms, so blame always walks down this list.
  //
  //    The five levels named in the Step 4 request map to
  //    L_PROTO, L_PATH, L_REG, L_FUNC, L_FW.  L_IRQ (Step 7) and L_CPU
  //    (Step 6, ISS co-simulation) sit between them and are declared here so
  //    the enum is complete and blame ordering stays stable as those steps land.
  // ---------------------------------------------------------------------------
  typedef enum int unsigned {
    L_NONE = 0,
    L_PROTO = 1,   // AXI4-Lite / APB handshakes                (this step)
    L_PATH  = 2,   // LSU -> AXI -> APB bridge -> slot           (this step)
    L_REG   = 3,   // peripheral register reads/writes           (register predictor)
    L_FUNC  = 4,   // peripheral behaviour at the pins           (pin models)
    L_IRQ   = 5,   // raise/pending/grant/accept/ack             (Step 7)
    L_CPU   = 6,   // retired instructions, CSRs, traps          (Step 6, ISS)
    L_FW    = 7    // mailbox status, checksum                   (firmware result)
  } layer_t;

  function automatic string layer_name(layer_t l);
    case (l)
      L_NONE : return "NONE";
      L_PROTO: return "PROTOCOL";
      L_PATH : return "PATH";
      L_REG  : return "REGISTER";
      L_FUNC : return "FUNCTIONAL";
      L_IRQ  : return "INTERRUPT";
      L_CPU  : return "CPU-STATE";
      L_FW   : return "FIRMWARE";
      default: return "??";
    endcase
  endfunction

  // ---------------------------------------------------------------------------
  // 2. Check IDs.
  //    Format <DOMAIN>-<NNNN>.  The ID is the triage key: the Step 8 runner
  //    buckets failures by check ID, so an ID must name one property only and
  //    must never be reused for a different property.
  // ---------------------------------------------------------------------------

  // ---- AXI4-Lite protocol  (layer L_PROTO) ----
  localparam string AXIL_AW_STABLE  = "AXIL-1001"; // AW addr/prot stable while stalled
  localparam string AXIL_W_STABLE   = "AXIL-1002"; // W data/strb stable while stalled
  localparam string AXIL_B_STABLE   = "AXIL-1003"; // B resp stable while stalled
  localparam string AXIL_AR_STABLE  = "AXIL-1004"; // AR addr/prot stable while stalled
  localparam string AXIL_R_STABLE   = "AXIL-1005"; // R data/resp stable while stalled
  localparam string AXIL_VALID_HELD= "AXIL-1006"; // VALID must not be withdrawn
  localparam string AXIL_NO_X       = "AXIL-1007"; // no X/Z on payload when VALID
  localparam string AXIL_RESP_LEGAL = "AXIL-1008"; // resp in {OKAY,SLVERR,DECERR}
  localparam string AXIL_W_AFTER_AW = "AXIL-1009"; // W may precede AW (legal)
  localparam string AXIL_NO_STALL   = "AXIL-1010"; // no AXI deadlock past budget
  localparam string AXIL_ERR_GONE   = "AXIL-1011"; // error response is not lost

  // ---- APB protocol  (layer L_PROTO) ----
  localparam string APB_SETUP_STABLE= "APB-2001"; // PADDR/etc stable through setup->access
  localparam string APB_ENABLE_CON  = "APB-2002"; // PENABLE implies PSEL
  localparam string APB_ENABLE_SEQ  = "APB-2003"; // PSEL rises before PENABLE
  localparam string APB_COMPLETE    = "APB-2004"; // access phase ends with PREADY
  localparam string APB_READ_ONLY   = "APB-2005"; // PRDATA only meaningful when !PWRITE
  localparam string APB_NO_X        = "APB-2006"; // no X/Z on APB payload
  localparam string APB_ALIGNED     = "APB-2007"; // PADDR[1:0] must be 0 (bridge aligns)
  localparam string APB_ONE_SLOT    = "APB-2008"; // exactly one PSEL asserted at a time
  localparam string APB_ERR_RSP     = "APB-2009"; // PSLVERR only in access phase
  localparam string APB_SETTLE      = "APB-2010"; // response available in access phase

  // ---- Path  (layer L_PATH) ----
  localparam string PATH_NO_LOSS    = "PATH-3001"; // every LSU access reaches AXI
  localparam string PATH_NO_EXTRA   = "PATH-3002"; // no AXI txn without an LSU access
  localparam string PATH_NO_EXTRA_APB="PATH-3003";// no APB transfer without an AXI txn
  localparam string PATH_SLOT       = "PATH-3004"; // APB slot matches address map
  localparam string PATH_ADDR       = "PATH-3005"; // PADDR == aligned AXI addr
  localparam string PATH_WDATA      = "PATH-3006"; // PWDATA == AXI WDATA
  localparam string PATH_STRB       = "PATH-3007"; // PSTRB == AXI WSTRB (byte enables)
  localparam string PATH_RDATA      = "PATH-3008"; // PRDATA == AXI RDATA
  localparam string PATH_RESP       = "PATH-3009"; // response code maps PSLVERR <-> RESP
  localparam string PATH_DIR        = "PATH-3010"; // read/write direction preserved
  localparam string PATH_LATENCY    = "PATH-3011"; // latency within declared budget
  localparam string PATH_TIMEOUT    = "PATH-3012"; // timeout path behaves as specified
  localparam string PATH_ORDER      = "PATH-3013"; // accesses complete in order
  localparam string PATH_HOLE       = "PATH-3014"; // unmapped hole returns DECERR
  localparam string PATH_ZERO_STRB  = "PATH-3015"; // strb==0 write -> OKAY, no APB transfer

  // ---- Register  (layer L_REG) ----
  localparam string REG_SUBWORD_ERR = "REG-4001";  // GPIO sub-word write -> PSLVERR
  localparam string REG_WO_MASK     = "REG-4002";  // write-only field reads as 0/const

  // ---------------------------------------------------------------------------
  // 3. Address map.  Copied verbatim from riscforge_soc_subsystem.sv.
  //    addr_decode semantics: start_addr INCLUSIVE, end_addr EXCLUSIVE
  //    (addr_decode.sv:53-54).  Every range below is therefore [lo, hi).
  // ---------------------------------------------------------------------------
  localparam logic [31:0] ISRAM_BASE = 32'h0001_0000; // :678
  localparam logic [31:0] ISRAM_END  = 32'h0001_8000; // :678
  localparam logic [31:0] DSRAM_BASE = 32'h0002_0000; // :679
  localparam logic [31:0] DSRAM_END  = 32'h0002_8000; // :679
  localparam logic [31:0] APB_BASE   = 32'h4000_0000; // :680
  localparam logic [31:0] APB_END    = 32'h5000_0000; // :680

  //  Direct DSRAM path inside hybrid_mem_interface (hybrid_mem_interface.sv:61-62).
  localparam logic [31:0] HMIF_SRAM_BASE  = 32'h0002_0000;
  localparam logic [31:0] HMIF_SRAM_LIMIT = 32'h0002_7FFF; // inclusive there
  localparam logic [31:0] HMIF_MMIO_BASE  = 32'h4000_0000;
  localparam logic [31:0] HMIF_MMIO_LIMIT = 32'h4FFF_FFFF; // inclusive there

  //  APB slots.  idx == array index into apb_req[0..5] == slot number.
  localparam int unsigned NUM_APB_SLAVES = 6;   // :244
  localparam logic [31:0] SLOT_BASE [NUM_APB_SLAVES] = '{
    32'h4000_0000, // [0] I2C
    32'h4000_1000, // [1] Timer 0
    32'h4000_2000, // [2] UART
    32'h4000_3000, // [3] GPIO   -- 2 KB window, see note
    32'h4000_4000, // [4] SPI Master (bootloader passthrough)
    32'h4000_5000  // [5] Timer 1
  };
  localparam logic [31:0] SLOT_END [NUM_APB_SLAVES] = '{
    32'h4000_1000, // [0] I2C
    32'h4000_2000, // [1] Timer 0
    32'h4000_3000, // [2] UART
    32'h4000_3800, // [3] GPIO   2 KB, NOT 0x4000_4000
    32'h4000_5000, // [4] SPI
    32'h4000_6000  // [5] Timer 1
  };

  function automatic string slot_name(int unsigned s);
    case (s)
      0: return "I2C";
      1: return "TIMER0";
      2: return "UART";
      3: return "GPIO";
      4: return "SPI";
      5: return "TIMER1";
      default: return "UNMAPPED";
    endcase
  endfunction

  //  Pure function of the address map: which APB slot owns this address?
  //  Returns 0..5, or 6 for "in APB space but no rule" (must yield DECERR).
  function automatic int unsigned apb_slot_of(logic [31:0] a);
    for (int unsigned i = 0; i < NUM_APB_SLAVES; i++)
      if ((a >= SLOT_BASE[i]) && (a <  SLOT_END[i])) return i;
    return NUM_APB_SLAVES; // sentinel: decoded region, but no rule
  endfunction

  function automatic bit in_apb_region(logic [31:0] a);
    return (a >= APB_BASE) && (a < APB_END);
  endfunction

  // ---------------------------------------------------------------------------
  // 4. Timing budgets, copied from riscforge_soc_subsystem.sv:463-477.
  //    A wait-state injector may never exceed these: the apb_timeout_monitor
  //    fires first and turns the transfer into SLVERR, which would mask the
  //    protocol violation we are trying to observe.
  // ---------------------------------------------------------------------------
  localparam int unsigned APB_TIMEOUT_CYCLES [NUM_APB_SLAVES] = '{
    16,    // [0] I2C
    16,    // [1] Timer 0
    16,    // [2] UART
    16,    // [3] GPIO
    65536, // [4] SPI  -- genuinely slow, flash transactions
    16     // [5] Timer 1
  };

  //  AXI-side budgets (axi_lite_timeout_monitor).
  localparam int unsigned AXI_TIMEOUT_SRAM = 64;     // :476
  localparam int unsigned AXI_TIMEOUT_APB  = 131072; // :477
  //  Invariant asserted at elaboration: the APB monitor must always answer
  //  before the AXI monitor, or the APB error is swallowed upstream.
  //  (comment at riscforge_soc_subsystem.sv:474-475)
  localparam bit APB_BEFORE_AXI = (AXI_TIMEOUT_APB > 65536);

  //  Sentinel data the timeout monitors inject.  A read that returns these is
  //  a timeout, not a peripheral value -- the register layer must never predict
  //  them.
  localparam logic [31:0] APB_TIMEOUT_DATA  = 32'hDEAD_BEEF; // :1000
  localparam logic [31:0] AXI_TIMEOUT_DATA  = 32'hDEAD_DEAD; // :1318

  // ---------------------------------------------------------------------------
  // 5. Response encoding.  axi_pkg::resp_t is logic[1:0] from the common_cells
  //    axi_pkg compiled by soc_subsystem.f:62.  We redeclare the encodings
  //    rather than importing, so this package elaborates standalone.
  // ---------------------------------------------------------------------------
  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_EXOKAY = 2'b01;
  localparam logic [1:0] RESP_SLVERR = 2'b10;
  localparam logic [1:0] RESP_DECERR = 2'b11;

  function automatic string resp_name(logic [1:0] r);
    case (r)
      RESP_OKAY  : return "OKAY";
      RESP_EXOKAY: return "EXOKAY";
      RESP_SLVERR: return "SLVERR";
      RESP_DECERR: return "DECERR";
      default    : return "??";
    endcase
  endfunction

  // ---------------------------------------------------------------------------
  // 6. Configuration (all overridable from the command line, see step4_cfg.sv)
  // ---------------------------------------------------------------------------
  parameter int unsigned RING_DEPTH    = 16;  // transactions kept per ring
  parameter int unsigned RETIRE_DEPTH  = 32;  // retired instructions kept
  parameter int unsigned MAX_FINDINGS  = 64;  // findings retained in the report
  parameter bit          DISASM_FALLBACK = 1; // use built-in decoder when no pc-map

  // ---------------------------------------------------------------------------
  // 7. Observation records.
  //
  //    One record type for every ring.  Three rings (LSU, AXI-Lite, APB) share
  //    this type so the hub can own, freeze and print all of them with one set
  //    of routines, and so a finding at any layer can be read against the same
  //    window of history from every tap.
  //
  //    Deliberately no `string` field: records live in an unpacked array that is
  //    written every cycle by monitors, and a fixed-width type keeps that write
  //    cheap and simulator-portable.  The human-readable tag lives on the
  //    finding, not the record.
  // ---------------------------------------------------------------------------
  typedef enum int unsigned {
    REC_NONE = 0,
    REC_LSU     = 1,  // core_lsu_req / addr / we / be accepted by hybrid_mem_interface
    REC_AXI_REQ = 2,  // AW+W (write) or AR (read) accepted at the xbar slave port
    REC_AXI_RESP= 3,  // B or R response returned to the core
    REC_APB_XFER= 4,  // completed APB transfer on one slot
    REC_APB_TO  = 5   // apb_timeout_monitor aborted a transfer on one slot
  } rec_kind_t;

  function automatic string rec_name(rec_kind_t k);
    case (k)
      REC_NONE    : return "-";
      REC_LSU     : return "LSU";
      REC_AXI_REQ : return "AXI";
      REC_AXI_RESP: return "AXR";
      REC_APB_XFER: return "APB";
      REC_APB_TO  : return "APTO";
      default     : return "??";
    endcase
  endfunction

  typedef struct packed {
    rec_kind_t     kind;      //  3
    logic          is_write;  //  1
    logic [31:0]   addr;      // 32  LSU/AXI byte address, APB aligned PADDR
    logic [31:0]   wdata;     // 32
    logic [31:0]   rdata;     // 32
    logic [3:0]    strb;      //  4  byte enables (APB PSTRB / AXI WSTRB)
    logic [1:0]    resp;      //  2  AXI resp, or APB PSLVERR<<1 when is_apb
    logic [15:0]   cycle_lo;  // 16  low 16 bits of the cycle stamp
    int unsigned   slot;      // 32  APB slot 0..5, or 6 = unmapped
    bit            ok;        //  1  this tap's own verdict
  } step4_rec_t;

  localparam step4_rec_t REC_ZERO = '0;

  // ---------------------------------------------------------------------------
  // 8. Findings.  A finding is a check that fired.  The reporter keeps them all
  //    (bounded by MAX_FINDINGS) but only the first is ever blamed; the rest are
  //    labelled.
  // ---------------------------------------------------------------------------
  typedef enum int unsigned {
    F_PRIMARY = 0,   // the first check to fire -- this is the blame
    F_REASSIGN= 1,   // fired later at a LOWER layer than the blame -> blame moves
    F_DOWNSTREAM=2,  // fired later at the same or higher layer -> consequence
    F_LATE    = 3    // fired later at a higher layer, after a freeze -> consequence
  } finding_state_t;

  typedef struct {
    finding_state_t state;
    layer_t         layer;
    string          id;        // e.g. "PATH-3007"
    longint unsigned cycle;
    logic [63:0]    time_ps;
    string         exp_str;
    string         act_str;
    string          where;     // instance / slot name
  } step4_finding_t;

  // ---------------------------------------------------------------------------
  // 9. Event counters.  Also the vacuity evidence for the pass rule: a checker
  //    that never saw traffic must not be reported as passing.
  // ---------------------------------------------------------------------------
  typedef struct {
    longint unsigned lsu_reqs;
    longint unsigned axi_wrs;
    longint unsigned axi_rds;
    longint unsigned apb_xfers [NUM_APB_SLAVES];
    longint unsigned apb_timeouts;
    longint unsigned resp_slverr;
    longint unsigned resp_decerr;
    longint unsigned retired;
  } step4_stats_t;

  //  step4_stats_t holds an array, so it is unpacked and cannot be cleared with
  //  a single '0.  Clear the members explicitly instead -- see clear_stats().
  function automatic void clear_stats(inout step4_stats_t s);
    s.lsu_reqs      = 0;
    s.axi_wrs       = 0;
    s.axi_rds       = 0;
    s.apb_timeouts  = 0;
    s.resp_slverr   = 0;
    s.resp_decerr   = 0;
    s.retired       = 0;
    for (int unsigned i = 0; i < NUM_APB_SLAVES; i++) s.apb_xfers[i] = 0;
  endfunction

// ---------------------------------------------------------------------------
  // 10. Check-ID indices and the event record.
  //
  //     A checker that fires from inside an SVA action block may NOT call into the
  //     reporter interface directly.  That is not a style preference: xsim
  //     crashes in codegen (EXCEPTION_ACCESS_VIOLATION) when a concurrent
  //     assertion's action block calls a function on an interface that carries
  //     real state.  It elaborates and runs perfectly when the interface is a
  //     couple of variables, and dies when the interface holds ring buffers,
  //     queues and associative arrays.  (Verified by bisection: an unused
  //     interface port elaborates, calling push_lsu() from an initial block
  //     elaborates, calling it from an action block does not.)
  //
  //     So the action block does the least it possibly can -- assign a packed
  //     event and raise a flag -- and a plain always_ff in the same checker
  //     forwards it to the reporter on the following edge.  One consequence is
  //     that the reporter owns every string: checkers send numbers, the reporter
  //     renders the sentence.  That is the right way round anyway, because the
  //     check ID is what the triage bucket is keyed on.
  // ---------------------------------------------------------------------------
  typedef enum int unsigned {
    CID_AXIL_AW_STABLE = 0,
    CID_AXIL_W_STABLE,
    CID_AXIL_B_STABLE,
    CID_AXIL_AR_STABLE,
    CID_AXIL_R_STABLE,
    CID_AXIL_VALID_HELD,
    CID_AXIL_NO_X,
    CID_AXIL_RESP_LEGAL,
    CID_AXIL_B_HAS_REQ,
    CID_AXIL_NO_STALL,
    CID_AXIL_R_ANSWERED,

    CID_APB_ENABLE_CON,
    CID_APB_ENABLE_SEQ,
    CID_APB_SETUP_STABLE,
    CID_APB_COMPLETE,
    CID_APB_RDATA_ONLY_RD,
    CID_APB_ERR_IN_ACCESS,
    CID_APB_ALIGNED,
    CID_APB_ONE_SLOT,
    CID_APB_NO_X_ADDR,
    CID_APB_NO_X_CTRL,

    CID_PATH_NO_LOSS,
    CID_PATH_WDATA,
    CID_PATH_STRB,
    CID_PATH_SLOT,
    CID_PATH_ADDR,
    CID_PATH_DIR,
    CID_PATH_RDATA,
    CID_PATH_RESP,
    CID_PATH_NO_EXTRA_APB,
    CID_PATH_HOLE,
    CID_PATH_ZERO_STRB,
    CID_PATH_ORDER,
    CID_PATH_LATENCY,

    CID_REG_SUBWORD_ERR,

    CID_COUNT
  } cid_t;

  //  Location indices.  A checker registers its human-readable name once, at
  //  construction, so the event only has to carry an integer.
  localparam int LOC_NONE = 0;
  localparam int LOC_AXI_CORE = 1;
  localparam int LOC_AXI_BOOT = 2;
  localparam int LOC_APB      = 4;
  localparam int LOC_SB       = 5;
  localparam int LOC_MAX  = 15;

  //  Four context words.  What each one means is fixed per check ID and is
  //  documented in the render table in step4_hub.sv.
  typedef struct packed {
    bit          vld;    // raised by the action block, cleared by the forwarder
    int unsigned cid;    // cid_t
    layer_t      layer;
    int unsigned loc;    // location index registered with the reporter
    logic [31:0] a;      // context word 0
    logic [31:0] b;      // context word 1
    logic [31:0] c;      // context word 2
    logic [31:0] d;      // context word 3
    finding_state_t state; // set by the reporter, not by the checker
  } step4_evt_t;

  localparam step4_evt_t EVT_ZERO = '0;

  // ---------------------------------------------------------------------------
  //  Finding-mailbox channel assignment (M2 decoupled forwarder).
  //  Each checker owns a DISJOINT region of hub.evt and its own write pointer,
  //  so two forwarders can never target the same slot and no pointer is ever
  //  driven by two processes. Must match step4_hub.sv / step4_reporter.sv.
  // ---------------------------------------------------------------------------
  localparam int unsigned EVT_CH_AXI = 0;  // step4_axi_sva
  localparam int unsigned EVT_CH_APB = 1;  // step4_apb_sva
  localparam int unsigned EVT_CH_SB  = 2;  // step4_path_scoreboard
  localparam int unsigned EVT_NCH    = 3;
  localparam int unsigned EVT_REGION = 4;  // slots per channel; power of two
  localparam int unsigned EVT_SLOTS  = EVT_NCH * EVT_REGION;  // = 12

endpackage : step4_pkg

// =============================================================================
//  Fault injection configuration.
//
//  In step4_pkg rather than in step4_fault_inject.sv so that the package order
//  in step4.f stays simple: step4_pkg.sv must be compiled first anyway.
// =============================================================================
package step4_fault_inject_pkg;

  typedef enum int unsigned {
    FI_NONE = 0,
    FI_STROBE,        // force byte strobes                       -> PATH_STRB
    FI_WAIT,          // report PREADY late                       -> APB_COMPLETE
    FI_SLVERR,        // force PSLVERR on a live transfer         -> PATH_RESP
    FI_TIMEOUT,       // inject the timeout sentinel as PRDATA     -> PATH_RDATA
    FI_STROBE_AXI,    // force WSTRB on the AXI hop                 -> PATH_STRB
    FI_PADDR,         // corrupt APB PADDR                         -> PATH_ADDR
    FI_AXI_ADDR,      // corrupt the AXI address                     -> PATH_NO_LOSS
    FI_AXI_WDATA,     // corrupt the AXI write data                 -> PATH_WDATA
    FI_WDATA,         // corrupt write data end to end            -> PATH_WDATA
    FI_RDATA,         // corrupt read data                        -> PATH_RDATA
    FI_RESP,          // replace the response code                -> PATH_RESP/PATH_HOLE
    FI_GHOST_XFER     // an APB transfer that belongs to nobody   -> PATH_NO_EXTRA_APB
  } fi_kind_t;

  function automatic string fi_name(fi_kind_t k);
    case (k)
      FI_NONE      : return "none";
      FI_STROBE    : return "strobe-corruptor";
      FI_WAIT      : return "wait-state-injector";
      FI_SLVERR    : return "parity-trigger";
      FI_TIMEOUT   : return "timeout-trigger";

      FI_WDATA     : return "wdata-corruptor";
      FI_RDATA     : return "rdata-corruptor";
      FI_RESP      : return "resp-corruptor";
      FI_GHOST_XFER: return "ghost-transfer";
      default      : return "??";
    endcase
  endfunction

  //  One slot of the mask per APB slot.  The injector aims at the lowest set bit.
  typedef struct packed {
    bit             armed;
    fi_kind_t       kind;
    logic [5:0]     slot_mask;
    longint unsigned at_cycle;     // inject from this cycle onwards
    int unsigned    n_times;       // how many transfers to corrupt
    logic [3:0]     strb_value;    // forced strobes
    int unsigned    wait_cycles;   // injected stall length
    logic [1:0]     resp_value;    // forced response code
    logic [31:0]    data_value;    // xor mask for the data corruptors
  } step4_fault_inject_cfg_t;

  localparam step4_fault_inject_cfg_t FI_CFG_OFF = '0;

endpackage : step4_fault_inject_pkg

// =============================================================================
//  The RISCFORGE fabric bus types.
//
//  At package scope, not module scope, even though riscforge_soc_subsystem.sv
//  declares its own copies at lines 335-413.  Two reasons:
//    - xsim refuses to connect an unpacked-array port whose parameter type is a
//      module-local typedef ("cannot assign a packed type to an unpacked type");
//    - the checkers and the DUT must agree on these by construction, not by two
//      copies of a declaration that someone has to keep in step.
//
//  Field names and widths are verbatim from riscforge_soc_subsystem.sv.
// =============================================================================
package step4_bus_pkg;

  typedef logic [31:0] addr_t;
  typedef logic [31:0] data_t;
  typedef logic [3:0]  strb_t;

  typedef struct packed { addr_t addr; logic [2:0] prot; } aw_chan_t;
  typedef struct packed { data_t data; strb_t strb; }      w_chan_t;
  typedef struct packed { logic [1:0] resp; }              b_chan_t;
  typedef struct packed { addr_t addr; logic [2:0] prot; } ar_chan_t;
  typedef struct packed { data_t data; logic [1:0] resp; } r_chan_t;

  typedef struct packed {
    aw_chan_t aw;   logic aw_valid;
    w_chan_t  w;    logic w_valid;
    logic     b_ready;
    ar_chan_t ar;   logic ar_valid;
    logic     r_ready;
  } axi_req_t;

  typedef struct packed {
    logic    aw_ready;
    logic    w_ready;
    b_chan_t b;     logic b_valid;
    logic    ar_ready;
    r_chan_t r;     logic r_valid;
  } axi_resp_t;

  typedef struct packed {
    int unsigned idx;
    addr_t       start_addr;
    addr_t       end_addr;
  } rule_t;

  //  APB4.  Only gpio_apb_wrap takes PSTRB in this design, but the bridge carries
  //  it for every slot, so it is modelled everywhere.
  typedef struct packed {
    addr_t      paddr;
    logic [2:0] pprot;
    logic       psel;
    logic       penable;
    logic       pwrite;
    data_t      pwdata;
    strb_t      pstrb;
  } apb_req_t;

  typedef struct packed {
    logic  pready;
    data_t prdata;
    logic  pslverr;
  } apb_resp_t;

  //  Flattening helpers.  The checkers take packed [slot][field] ports so that
  //  a bind can connect them with one concatenation, but the DUT signals are
  //  unpacked arrays of structs.  These two functions are the single place that
  //  conversion happens.
  function automatic void flatten_apb_req(input  apb_req_t q [step4_pkg::NUM_APB_SLAVES],
                                          output logic [step4_pkg::NUM_APB_SLAVES-1:0]        psel,
                                          output logic [step4_pkg::NUM_APB_SLAVES-1:0]        penable,
                                          output logic [step4_pkg::NUM_APB_SLAVES-1:0]        pwrite,
                                          output logic [step4_pkg::NUM_APB_SLAVES-1:0][31:0]  paddr,
                                          output logic [step4_pkg::NUM_APB_SLAVES-1:0][31:0]  pwdata,
                                          output logic [step4_pkg::NUM_APB_SLAVES-1:0][3:0]   pstrb);
    for (int unsigned i = 0; i < step4_pkg::NUM_APB_SLAVES; i++) begin
      psel[i]    = q[i].psel;
      penable[i] = q[i].penable;
      pwrite[i]  = q[i].pwrite;
      paddr[i]   = q[i].paddr;
      pwdata[i]  = q[i].pwdata;
      pstrb[i]   = q[i].pstrb;
    end
  endfunction

  function automatic void flatten_apb_rsp(input  apb_resp_t q [step4_pkg::NUM_APB_SLAVES],
                                          output logic [step4_pkg::NUM_APB_SLAVES-1:0]        pready,
                                          output logic [step4_pkg::NUM_APB_SLAVES-1:0]        pslverr,
                                          output logic [step4_pkg::NUM_APB_SLAVES-1:0][31:0]  prdata);
    for (int unsigned i = 0; i < step4_pkg::NUM_APB_SLAVES; i++) begin
      pready[i]  = q[i].pready;
      pslverr[i] = q[i].pslverr;
      prdata[i]  = q[i].prdata;
    end
  endfunction

endpackage : step4_bus_pkg
