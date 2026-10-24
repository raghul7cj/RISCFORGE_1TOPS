// =============================================================================
// Module Name : tb_pkg.sv
// Description : RISCFORGE SoC testbench package.
//
//               Owns EVERYTHING the passive monitor layer shares:
//                 1. Authoritative address map + decode functions
//                 2. Blame-layer / command constants
//                 3. Bus, region, size, interrupt-source enumerations
//                 4. Every transaction type used by monitors, scoreboards,
//                    coverage and the failure reporter
//                 5. The generic cyclic ring buffer (post-mortem history)
//
//               Implements INFRA_TRACKING.md S1.1 - S1.11. This file was 0 bytes,
//               which is why every monitor in ../monitors/ failed to compile.
//
// Target      : Vivado XSim 2022.2 (SV-2017, no UVM) - also clean on VCS/Xcelium.
// Conventions : snake_case signals, 4-space indent, snake_case packed txns.
// =============================================================================

`ifndef RF_TB_PKG_SV
`define RF_TB_PKG_SV

`timescale 1ns/1ps

package tb_pkg;

  // ===========================================================================
  // 0. GLOBAL TIMEBASE
  // ===========================================================================
  // One 64-bit free-running counter per simulation, owned by rf_timebase_if and
  // fanned out to every monitor interface. Every transaction carries
  //   timestamp    = absolute cycle at the sampling edge (pre-NBA value)
  //   rel_cycle    = cycles since sys_rst_n released
  // so cross-monitor joins are exact rather than "close enough".
  timeunit      1ns;
  timeprecision 1ps;

  parameter int unsigned CYCLE_W          = 64;
  parameter int unsigned DEFAULT_RING     = 256;   // S1.11: 64-256 entries
  parameter int unsigned DEFAULT_LIVE_Q   = 200000; // live stream trim depth
  parameter int unsigned GPIO_COUNT       = 32;
  parameter int unsigned NUM_APB_SLOTS    = 6;

  parameter int unsigned CLK_PERIOD_NS    = 10;     // 100 MHz

  // ===========================================================================
  // 1. AUTHORITATIVE ADDRESS MAP
  //    Must match riscforge_soc_subsystem.sv :: xbar_addr_map / apb_addr_map
  // ===========================================================================
  parameter logic [31:0] BOOTROM_BASE = 32'h0000_0000;
  parameter logic [31:0] BOOTROM_SIZE = 32'h0000_0040;   // 16 x 32-bit
  parameter logic [31:0] ISRAM_BASE   = 32'h0001_0000;
  parameter logic [31:0] ISRAM_SIZE   = 32'h0000_8000;   // 32 KB
  parameter logic [31:0] DSRAM_BASE   = 32'h0002_0000;
  parameter logic [31:0] DSRAM_SIZE   = 32'h0000_8000;   // 32 KB
  parameter logic [31:0] APB_BR_BASE  = 32'h4000_0000;
  parameter logic [31:0] APB_BR_LIMIT = 32'h4FFF_FFFF;
  parameter logic [31:0] MMIO_LIMIT   = APB_BR_LIMIT;

  // --- APB slot identity -----------------------------------------------------
  typedef enum int unsigned {
    RF_APB_I2C    = 0,   // 0x4000_0000
    RF_APB_TIMER0 = 1,   // 0x4000_1000
    RF_APB_UART   = 2,   // 0x4000_2000
    RF_APB_GPIO   = 3,   // 0x4000_3000  (2 KB window, 11-bit decode)
    RF_APB_SPI    = 4,   // 0x4000_4000
    RF_APB_TIMER1 = 5,   // 0x4000_5000
    RF_APB_NONE   = 6    // unmapped
  } rf_apb_slot_e;

  function automatic logic [31:0] apb_slot_base(int unsigned slot);
    case (slot)
      RF_APB_I2C:    return 32'h4000_0000;
      RF_APB_TIMER0: return 32'h4000_1000;
      RF_APB_UART:   return 32'h4000_2000;
      RF_APB_GPIO:   return 32'h4000_3000;
      RF_APB_SPI:    return 32'h4000_4000;
      RF_APB_TIMER1: return 32'h4000_5000;
      default:       return 32'hFFFF_FFFF;
    endcase
  endfunction

  function automatic int unsigned apb_slot_size_log2(int unsigned slot);
    // GPIO is deliberately 2 KB, not 4 KB - a 4 KB window would alias onto SPI.
    return (slot == RF_APB_GPIO) ? 11 : 12;
  endfunction

  function automatic logic [31:0] apb_slot_size(int unsigned slot);
    return 32'h1 << apb_slot_size_log2(slot);
  endfunction

  function automatic string apb_slot_name(int unsigned slot);
    case (slot)
      RF_APB_I2C:    return "I2C";
      RF_APB_TIMER0: return "TIMER0";
      RF_APB_UART:   return "UART";
      RF_APB_GPIO:   return "GPIO";
      RF_APB_SPI:    return "SPI";
      RF_APB_TIMER1: return "TIMER1";
      default:       return "UNMAPPED";
    endcase
  endfunction

  // S1.1 / PATH-05: single decoder used by the monitor, the scoreboard and the
  // mmio_path_scoreboard check. Returns RF_APB_NONE for anything undecoded.
  function automatic int unsigned get_expected_apb_slot(logic [31:0] addr);
    for (int unsigned s = 0; s < NUM_APB_SLOTS; s++) begin
      if ((addr >= apb_slot_base(s)) && (addr < (apb_slot_base(s) + apb_slot_size(s))))
        return s;
    end
    return int'(RF_APB_NONE);
  endfunction

  // --- Top level regions -----------------------------------------------------
  typedef enum int unsigned {
    RF_REGION_BOOTROM  = 0,
    RF_REGION_ISRAM    = 1,
    RF_REGION_DSRAM    = 2,
    RF_REGION_MMIO     = 3,
    RF_REGION_UNMAPPED = 4
  } rf_region_e;

  function automatic rf_region_e decode_region(logic [31:0] addr);
    if (addr < (BOOTROM_BASE + BOOTROM_SIZE))                         return RF_REGION_BOOTROM;
    if ((addr >= ISRAM_BASE) && (addr < (ISRAM_BASE + ISRAM_SIZE)))   return RF_REGION_ISRAM;
    if ((addr >= DSRAM_BASE) && (addr < (DSRAM_BASE + DSRAM_SIZE)))   return RF_REGION_DSRAM;
    if ((addr >= APB_BR_BASE) && (addr <= APB_BR_LIMIT))              return RF_REGION_MMIO;
    return RF_REGION_UNMAPPED;
  endfunction

  function automatic string region_name(rf_region_e r);
    case (r)
      RF_REGION_BOOTROM:  return "BOOTROM";
      RF_REGION_ISRAM:    return "ISRAM";
      RF_REGION_DSRAM:    return "DSRAM";
      RF_REGION_MMIO:     return "MMIO";
      default:            return "UNMAPPED";
    endcase
  endfunction

  function automatic bit is_mmio_addr(logic [31:0] addr);
    return (addr >= APB_BR_BASE) && (addr <= APB_BR_LIMIT);
  endfunction

  // ===========================================================================
  // 2. BLAME LAYERS, COMMANDS, CHECK IDS
  // ===========================================================================
  parameter int LAYER_PROTOCOL = 1;
  parameter int LAYER_PATH     = 2;
  parameter int LAYER_REG      = 3;
  parameter int LAYER_REGISTER = 3;
  parameter int LAYER_PIN      = 4;
  parameter int LAYER_IRQ      = 5;
  parameter int LAYER_FIRMWARE = 6;

  function automatic string layer_name(int layer);
    case (layer)
      LAYER_PROTOCOL: return "Protocol";
      LAYER_PATH:     return "Path";
      LAYER_REG:      return "Reg";
      LAYER_PIN:      return "Pin";
      LAYER_IRQ:      return "IRQ";
      LAYER_FIRMWARE: return "Firmware";
      default:        return "Unknown";
    endcase
  endfunction

  // Firmware -> TB mailbox words (dsram[0..6] in soc_tb_top).
  parameter logic [31:0] CMD_PASS = 32'hC0DE_C0DE;
  parameter logic [31:0] CMD_FAIL = 32'hBAAD_F00D;
  parameter logic [31:0] CMD_HALT = 32'hDEAD_BEEF;

  // ===========================================================================
  // 3. BUS ENCODINGS
  // ===========================================================================
  // axi_pkg::resp_t
  typedef enum logic [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
  } rf_axi_resp_e;

  function automatic string axi_resp_name(logic [1:0] r);
    case (r)
      2'b00: return "OKAY";
      2'b01: return "EXOKAY";
      2'b10: return "SLVERR";
      default: return "DECERR";
    endcase
  endfunction

  // S1.2: AW, W, B, AR and R are logged as FIVE INDEPENDENT events so that
  // channel ordering and skew are visible in the log, then correlated into a
  // single axi_txn_t by the monitor's per-channel capture latches.
  typedef enum int unsigned {
    RF_AXI_CH_AW = 0,
    RF_AXI_CH_W  = 1,
    RF_AXI_CH_B  = 2,
    RF_AXI_CH_AR = 3,
    RF_AXI_CH_R  = 4,
    RF_AXI_CH_NONE = 5
  } rf_axi_chan_e;

  function automatic rf_axi_chan_e rf_axi_chan_from_string(string s);
    if (s == "AW") return RF_AXI_CH_AW;
    if (s == "W")  return RF_AXI_CH_W;
    if (s == "B")  return RF_AXI_CH_B;
    if (s == "AR") return RF_AXI_CH_AR;
    if (s == "R")  return RF_AXI_CH_R;
    return RF_AXI_CH_NONE;
  endfunction

  function automatic string rf_axi_chan_name(rf_axi_chan_e c);
    case (c)
      RF_AXI_CH_AW: return "AW";
      RF_AXI_CH_W:  return "W";
      RF_AXI_CH_B:  return "B";
      RF_AXI_CH_AR: return "AR";
      RF_AXI_CH_R:  return "R";
      default:      return "--";
    endcase
  endfunction

  // RISC-V LSU unit encoding (memory_cycle.v : lsunitM[4:3])
  typedef enum int unsigned {
    RF_LSU_NOP    = 0,
    RF_LSU_B      = 1,
    RF_LSU_H      = 2,
    RF_LSU_W      = 3,
    RF_LSU_U      = 4,
    RF_LSU_D      = 5
  } rf_lsu_op_e;

  function automatic int unsigned lsu_bytes(rf_lsu_op_e op);
    case (op)
      RF_LSU_B: return 1;
      RF_LSU_H: return 2;
      RF_LSU_U,
      RF_LSU_W: return 4;
      RF_LSU_D: return 8;
      default:  return 0;
    endcase
  endfunction

  function automatic string lsu_op_name(rf_lsu_op_e op);
    case (op)
      RF_LSU_B: return "LB ";
      RF_LSU_H: return "LH ";
      RF_LSU_U: return "LHU";
      RF_LSU_W: return "LW ";
      RF_LSU_D: return "LD ";
      default:  return "-- ";
    endcase
  endfunction

  typedef enum int unsigned { RF_DIR_NONE = 0, RF_DIR_R = 1, RF_DIR_W = 2 } rf_dir_e;

  function automatic rf_dir_e dir_of(bit is_store);
    return is_store ? RF_DIR_W : RF_DIR_R;
  endfunction

  // ===========================================================================
  // 4. INTERRUPT SOURCE MAP
  //    fast_irq_i[15:0] -> mip[31:16]; timer_irq_i -> mip[7] (MTIP).
  //    See riscforge_soc_subsystem.sv:1236-1251.
  // ===========================================================================
  typedef enum int unsigned {
    RF_IRQ_NONE         = 0,
    RF_IRQ_GPIO_GLOBAL  = 1,   // FLI[0]  mip[16] mcause 16
    RF_IRQ_I2C          = 2,   // FLI[1]  mip[17] mcause 17
    RF_IRQ_SPI_EVT0     = 3,   // FLI[2]  mip[18] mcause 18
    RF_IRQ_UART         = 4,   // FLI[3]  mip[19] mcause 19
    RF_IRQ_T0_C0_OVF    = 5,   // FLI[4]  mip[20] mcause 20
    RF_IRQ_T0_C1_OVF    = 6,   // FLI[5]  mip[21] mcause 21
    RF_IRQ_T0_C1_CMP    = 7,   // FLI[6]  mip[22] mcause 22
    RF_IRQ_T1_C0_OVF    = 8,   // FLI[7]  mip[23] mcause 23
    RF_IRQ_T1_C0_CMP    = 9,   // FLI[8]  mip[24] mcause 24
    RF_IRQ_T1_C1_OVF    = 10,  // FLI[9]  mip[25] mcause 25
    RF_IRQ_T1_C1_CMP    = 11,  // FLI[10] mip[26] mcause 26
    RF_IRQ_SPI_EVT1     = 12,  // FLI[11] mip[27] mcause 27
    RF_IRQ_MTIP         = 13   // timer0_irq_o[1] -> mip[7] mcause 7
  } rf_irq_src_e;

  function automatic int unsigned irq_fli_bit(rf_irq_src_e s);  // -1 => not on FLI
    case (s)
      RF_IRQ_GPIO_GLOBAL: return 0;
      RF_IRQ_I2C:         return 1;
      RF_IRQ_SPI_EVT0:    return 2;
      RF_IRQ_UART:        return 3;
      RF_IRQ_T0_C0_OVF:   return 4;
      RF_IRQ_T0_C1_OVF:   return 5;
      RF_IRQ_T0_C1_CMP:   return 6;
      RF_IRQ_T1_C0_OVF:   return 7;
      RF_IRQ_T1_C0_CMP:   return 8;
      RF_IRQ_T1_C1_OVF:   return 9;
      RF_IRQ_T1_C1_CMP:   return 10;
      RF_IRQ_SPI_EVT1:    return 11;
      default:            return 32'hFFFF_FFFF;
    endcase
  endfunction

  function automatic int unsigned irq_mip_bit(rf_irq_src_e s);
    case (s)
      RF_IRQ_GPIO_GLOBAL: return 16;
      RF_IRQ_I2C:         return 17;
      RF_IRQ_SPI_EVT0:    return 18;
      RF_IRQ_UART:        return 19;
      RF_IRQ_T0_C0_OVF:   return 20;
      RF_IRQ_T0_C1_OVF:   return 21;
      RF_IRQ_T0_C1_CMP:   return 22;
      RF_IRQ_T1_C0_OVF:   return 23;
      RF_IRQ_T1_C0_CMP:   return 24;
      RF_IRQ_T1_C1_OVF:   return 25;
      RF_IRQ_T1_C1_CMP:   return 26;
      RF_IRQ_SPI_EVT1:    return 27;
      RF_IRQ_MTIP:        return 7;
      default:            return 32'hFFFF_FFFF;
    endcase
  endfunction

  function automatic logic [31:0] irq_mcause(rf_irq_src_e s);
    int unsigned b = irq_mip_bit(s);
    return (b == 32'hFFFF_FFFF) ? '0 : (32'h8000_0000 | (32'(b) << 0));
  endfunction

  function automatic string irq_src_name(rf_irq_src_e s);
    case (s)
      RF_IRQ_GPIO_GLOBAL: return "GPIO_GLOBAL";
      RF_IRQ_I2C:         return "I2C";
      RF_IRQ_SPI_EVT0:    return "SPI_EVT0";
      RF_IRQ_UART:        return "UART";
      RF_IRQ_T0_C0_OVF:   return "TIMER0_C0_OVF";
      RF_IRQ_T0_C1_OVF:   return "TIMER0_C1_OVF";
      RF_IRQ_T0_C1_CMP:   return "TIMER0_C1_CMP";
      RF_IRQ_T1_C0_OVF:   return "TIMER1_C0_OVF";
      RF_IRQ_T1_C0_CMP:   return "TIMER1_C0_CMP";
      RF_IRQ_T1_C1_OVF:   return "TIMER1_C1_OVF";
      RF_IRQ_T1_C1_CMP:   return "TIMER1_C1_CMP";
      RF_IRQ_SPI_EVT1:    return "SPI_EVT1";
      RF_IRQ_MTIP:        return "MTIP";
      default:            return "NONE";
    endcase
  endfunction

  // irq_arbiter.v priority classes: 2 = Real-Time, 1 = Stream, 0 = Background
  function automatic logic [1:0] irq_class(rf_irq_src_e s);
    case (s)
      RF_IRQ_T0_C0_OVF, RF_IRQ_T0_C1_OVF, RF_IRQ_T0_C1_CMP,
      RF_IRQ_T1_C0_OVF, RF_IRQ_T1_C0_CMP, RF_IRQ_T1_C1_OVF,
      RF_IRQ_T1_C1_CMP, RF_IRQ_MTIP:                return 2'd2;
      RF_IRQ_UART, RF_IRQ_SPI_EVT0, RF_IRQ_SPI_EVT1: return 2'd1;
      RF_IRQ_I2C, RF_IRQ_GPIO_GLOBAL:               return 2'd0;
      default:                                     return 2'd0;
    endcase
  endfunction

  function automatic string irq_class_name(logic [1:0] c);
    case (c)
      2'd2: return "REALTIME";
      2'd1: return "STREAM";
      default: return "BACKGROUND";
    endcase
  endfunction

  // irq_gateway.v edge_mode = 6'b110101 indexed {WD,T0,UART,SPI,I2C,GPIO}
  function automatic bit irq_is_edge(rf_irq_src_e s);
    case (s)
      RF_IRQ_GPIO_GLOBAL: return 1'b1;
      RF_IRQ_I2C:         return 1'b0;
      RF_IRQ_SPI_EVT0,
      RF_IRQ_SPI_EVT1:    return 1'b1;
      RF_IRQ_UART:        return 1'b0;
      RF_IRQ_T0_C0_OVF,
      RF_IRQ_T0_C1_OVF,
      RF_IRQ_T0_C1_CMP:   return 1'b1;
      RF_IRQ_MTIP:        return 1'b1;   // Timer0 slot
      default:            return 1'b1;
    endcase
  endfunction

  function automatic rf_irq_src_e irq_src_of_mcause31(logic [31:0] mc);
    for (int unsigned i = 0; i <= int'(RF_IRQ_MTIP); i++)
      if (mc == irq_mcause(rf_irq_src_e'(i))) return rf_irq_src_e'(i);
    return RF_IRQ_NONE;
  endfunction

  function automatic rf_irq_src_e irq_src_of_cause_enc(logic [4:0] cause);
    case (cause)
      5'd16: return RF_IRQ_GPIO_GLOBAL;
      5'd17: return RF_IRQ_I2C;
      5'd18: return RF_IRQ_SPI_EVT0;
      5'd19: return RF_IRQ_UART;
      5'd20: return RF_IRQ_T0_C0_OVF;
      5'd21: return RF_IRQ_T0_C1_OVF;
      5'd22: return RF_IRQ_T0_C1_CMP;
      5'd23: return RF_IRQ_T1_C0_OVF;
      5'd24: return RF_IRQ_T1_C0_CMP;
      5'd25: return RF_IRQ_T1_C1_OVF;
      5'd26: return RF_IRQ_T1_C1_CMP;
      5'd27: return RF_IRQ_SPI_EVT1;
      5'd7:  return RF_IRQ_MTIP;
      default: return RF_IRQ_NONE;
    endcase
  endfunction

  // ===========================================================================
  // SHADOW PC-TO-INSTRUCTION TABLE (for Retire Disassembly)
  // ===========================================================================
  logic [31:0] shadow_pc_imem [logic [31:0]];

  function automatic void shadow_record_fetch(logic [31:0] pc, logic [31:0] instr);
    shadow_pc_imem[pc] = instr;
  endfunction

  function automatic logic [31:0] shadow_lookup_instr(logic [31:0] pc);
    if (shadow_pc_imem.exists(pc))
      return shadow_pc_imem[pc];
    return 32'h0000_0000;
  endfunction

  function automatic logic [31:0] shadow_lookup_retire(logic [31:0] pc);
    return shadow_lookup_instr(pc);
  endfunction

  // ===========================================================================
  // 5. TRANSACTION TYPES
  //    All are `struct packed` so an array of them is legal in every simulator,
  //    including XSim 2022.2 (which rejects unpacked arrays inside interfaces
  //    and inside class members). Field names below are the ones the pre-existing
  //    ../monitors/*.sv modules already reference.
  // ===========================================================================

  // ---- 5.1 Fetch ------------------------------------------------------------
  typedef struct packed {
    longint unsigned timestamp;    // absolute shared cycle counter
    longint unsigned rel_cycle;    // cycles since sys_rst_n release
    int     unsigned seq;          // per-monitor monotonic event id
    logic [31:0] pc;                // Fetch.PCF
    logic [31:0] instr;             // Fetch.InstrF
    logic        valid;
    logic        stall;             // Fetch.imem_stall | top.StallF
    logic        branch_taken;      // pc != pc + 4
    logic [31:0] pc_next;           // Fetch.PC_next
    logic        exc_valid;         // Fetch.exc_valid_F
    logic [5:0]  exc_cause;
    logic [31:0] exc_tval;
    rf_region_e  region;
  } fetch_txn_t;

  // ---- 5.2 Retire (architectural commit) ------------------------------------
  typedef struct packed {
    longint unsigned timestamp;
    longint unsigned rel_cycle;
    int     unsigned seq;
    logic [31:0] pc;                // top.PC_W
    logic [31:0] instr;             // reconstructed / instruction shadow
    logic [4:0]  rd_addr;           // top.RDW
    logic [31:0] rd_wdata;          // top.ResultW
    logic        reg_we;            // top.RegWriteW_gated
    logic        trap;              // top.trap_commit_valid
    logic        irq_ack;           // top.trap_commit_is_interrupt
    logic        is_mret;           // top.is_mret_W | top.mret_commit
    logic        csr_we;            // top.csr_write_en_W
    logic [11:0] csr_addr;          // top.csr_addr_W
    logic [31:0] csr_wdata;         // top.new_csr_W
    logic [5:0]  exc_cause;         // top.exc_cause_W
    logic [31:0] exc_tval;          // top.exc_tval_W
    logic [31:0] exc_pc;            // top.exc_pc_W
    logic [30:0] cause;             // top.trap_commit_cause
    rf_irq_src_e irq_src;           // irq_src_of_mcause31({1'b1,cause})
    logic [1:0]  irq_class;         // decoded from irq_src
  } retire_txn_t;

  // ---- 5.3 LSU --------------------------------------------------------------
  typedef struct packed {
    longint unsigned timestamp;
    longint unsigned rel_cycle;
    int     unsigned seq;
    logic [31:0] pc;                // top.PC_M
    logic [4:0]  lsunit;            // top.lsunitM
    rf_lsu_op_e  op;
    logic        is_load;
    logic        is_store;
    logic [31:0] addr;              // lsu_mem_addr
    logic [31:0] wdata;             // lsu_mem_wdata
    logic [31:0] rdata;             // lsu_mem_rdata
    logic [3:0]  be;                // lsu_mem_be
    logic        we;                // lsu_mem_we
    logic        is_mmio;           // decode_region(addr) == RF_REGION_MMIO
    logic        err;               // lsu_mem_err
    int     unsigned wait_cycles;   // cycles req asserted before completion
    rf_region_e  region;
    int     unsigned apb_slot;      // get_expected_apb_slot(addr) or RF_APB_NONE
  } lsu_txn_t;

  // ---- 5.4a AXI-Lite per-channel event (S1.2 - five independent events) ------
  typedef struct packed {
    longint unsigned timestamp;
    int     unsigned seq;
    rf_axi_chan_e chan;
    logic [31:0] addr;
    logic [2:0]  prot;
    logic [31:0] data;
    logic [3:0]  strb;
    logic [1:0]  resp;
    logic        valid;             // sampled VALID
    logic        ready;             // sampled READY
    int     unsigned wait_cycles;   // VALID asserted but not yet accepted
    int     unsigned outstanding;   // beats issued but not yet completed
  } axi_evt_t;

  // ---- 5.4b AXI-Lite correlated transaction (S1.4 / PATH-01..04) -------------
  typedef struct packed {
    longint unsigned timestamp;     // completion edge (B or R handshake)
    longint unsigned rel_cycle;
    int     unsigned seq;
    logic [31:0] addr;
    logic [31:0] data;
    logic [3:0]  strb;
    logic [1:0]  resp;
    logic        is_write;
    logic [2:0]  prot;
    logic        aw_hs;
    logic        w_hs;
    logic        b_hs;
    int     unsigned aw_wait;       // AWVALID asserted -> AWREADY
    int     unsigned w_wait;        // WVALID asserted  -> WREADY
    int     unsigned b_wait;        // BVALID asserted  -> BREADY
    int     unsigned aw_to_w;       // cycle gap AW -> W (channel skew)
    int     unsigned aw_to_b;       // full write latency
    int     unsigned ar_to_r;       // full read latency
    logic        is_mmio;
    int     unsigned apb_slot;
    bit        decoded;
  } axi_txn_t;

  // ---- 5.5 APB transfer (S1.3 - one line per COMPLETED transfer) -----------
  typedef struct packed {
    longint unsigned timestamp;
    longint unsigned rel_cycle;
    int     unsigned seq;
    int     unsigned slot;
    logic [31:0] paddr;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic [3:0]  pstrb;
    logic        pwrite;
    logic        pready;
    logic        pslverr;
    int     unsigned wait_states;   // cycles PENABLE asserted before PREADY
    longint unsigned setup_cycle;   // first PSEL edge for this slot
    longint unsigned access_cycle;  // first PENABLE edge for this slot
    logic [31:0] addr_match;        // addr rounded down to the 1 KB (or 2 KB) window
  } apb_txn_t;

  // ---- 5.6 Interrupt lifecycle ---------------------------------------------
  typedef struct packed {
    longint unsigned timestamp;
    longint unsigned rel_cycle;
    int     unsigned seq;
    logic [4:0]  irq_id;           // irq_cause_enc
    rf_irq_src_e src;
    logic        asserted;         // source line was high this cycle
    logic        granted;          // irq_pending && !irq_valid-latched-free
    logic        acked;            // trap_commit_is_interrupt
    logic        is_interrupt;     // trap_commit_is_interrupt
    logic [30:0] cause;            // trap_commit_cause
    logic [31:0] mip;              // csr_mip_sb
    logic [31:0] mie;              // csr_mie_sb
    logic        mie_bit;          // csr_mie_sb[irq_cause_enc]
    logic        mstatus_mie;
    logic [1:0]  irq_class;
    logic [31:0] latency_cycles;   // granted -> acked
    logic [1:0]  nest_depth;       // CSR shadow stack depth (0..2)
    logic [5:0]  gateway_pend_q;   // sticky latch in irq_gateway
    logic [1:0]  rr_ptrs;          // {rr_ptr_c1, rr_ptr_c0}
    logic        is_mret;          // 1 if MRET context pop
  } irq_txn_t;

  // ---- 5.7 External pins ----------------------------------------------------
  typedef struct packed {
    longint unsigned timestamp;
    longint unsigned rel_cycle;
    int     unsigned seq;
    logic [31:0] gpio_in;          // gpio_in_i (raw pad)
    logic [31:0] gpio_out;         // gpio_out_o
    logic [31:0] gpio_oe;          // gpio_tx_en_o
    logic [31:0] gpio_in_sync;     // gpio_in_sync_o
    logic [31:0] moved;            // bitwise (gpio_in ^ gpio_in_sync_d)
    logic        global_irq;       // gpio_global_interrupt_o
    logic [31:0] pin_irq;          // gpio_pin_level_interrupts_o
  } gpio_txn_t;

  typedef struct packed {
    longint unsigned timestamp;
    longint unsigned rel_cycle;
    int     unsigned seq;
    logic [7:0]  data_byte;       // SOUT / SIN sampled at end of frame
    logic        tx;               // 1 = DUT drove uart_sout_o
    logic        start_bit;
    logic        stop_bit;
    logic        framing_err;
    logic        parity_err;
    int     unsigned bit_cycles;   // measured bit period (in clk cycles)
  } uart_txn_t;

  typedef struct packed {
    longint unsigned timestamp;
    longint unsigned rel_cycle;
    int     unsigned seq;
    logic        scl;              // resolved line (pull-up accounted for)
    logic        sda;
    logic        scl_oen;
    logic        sda_oen;
    logic        start;            // SDA falls while SCL high
    logic        stop;             // SDA rises  while SCL high
    logic        scl_fall;
    logic        scl_rise;
    logic        sda_fall;
    logic        sda_rise;
    logic [7:0]  data_byte;       // 8 bits sampled on SCL rising edges
    logic        bit_done;
  } i2c_txn_t;

  typedef struct packed {
    longint unsigned timestamp;
    longint unsigned rel_cycle;
    int     unsigned seq;
    logic        sclk_rise;
    logic        sclk_fall;
    logic [1:0]  cs;               // {csn1, csn0}, active low
    logic        mosi;             // spi_sdo0_o
    logic        miso;             // spi_sdi1_i
    logic [7:0]  data_byte;       // MOSI bits assembled on SCLK rising edges
    logic [4:0]  bit_idx;
    logic        tx_word_done;     // CS deasserted (end of transfer)
    logic [1:0]  spi_events;
  } spi_txn_t;

  // ---- 5.8 Convenience accessors -------------------------------------------
  function automatic string txn_tag(rf_dir_e d);
    return (d == RF_DIR_W) ? "WR" : "RD";
  endfunction

  function automatic logic is_mmio_of(axi_txn_t t);
    return t.is_mmio;
  endfunction

  // ===========================================================================
  // 6. CYCLIC RING BUFFER  (post-mortem history, S1.11)
  // ===========================================================================
  // Fixed capacity, O(1) push, no allocation in steady state. Oldest entries are
  // silently overwritten. `frozen` (driven by failure_reporter.freeze_monitors)
  // stops all writes so the ring around the first fatal is preserved verbatim.
  virtual class rf_ring_base #(type T = int, int DEPTH = int'(DEFAULT_RING));

    localparam int DEPTH_C = (DEPTH < 2) ? 2 : DEPTH;

    protected T               m_mem[$];
    protected longint unsigned m_total;      // lifetime push count (overflow-safe)
    protected longint unsigned m_frozen_at;  // cycle at which we stopped

    // ---- lifecycle ----
    function new();
      m_mem      = {};
      m_total    = 0;
      m_frozen_at = 0;
    endfunction

    function void clear();
      m_mem.delete();
      m_total     = 0;
      m_frozen_at = 0;
    endfunction

    // ---- write side ----
    function void push(T t, bit frozen = 0);
      if (frozen) begin
        if (m_frozen_at == 0) m_frozen_at = t.timestamp;
        return;
      end
      if (m_mem.size() == DEPTH_C) void'(m_mem.pop_front());
      m_mem.push_back(t);
      m_total++;
    endfunction

    // ---- read side (index 0 = OLDEST retained, size()-1 = NEWEST) ----
    function int size();        return m_mem.size();                endfunction
    function bit full();        return (m_mem.size() == DEPTH_C);    endfunction
    function bit empty();       return (m_mem.size() == 0);          endfunction
    function longint unsigned total();    return m_total;            endfunction
    function longint unsigned frozen_at();return m_frozen_at;         endfunction
    function bit is_frozen();   return (m_frozen_at != 0);          endfunction

    function T at(int k);
      if (m_mem.size() == 0) begin
        T z;
        z = '0;
        return z;
      end
      if (k < 0)            k = 0;
      if (k >= m_mem.size())k = m_mem.size() - 1;
      return m_mem[k];
    endfunction

    function T oldest(); return at(0);           endfunction
    function T newest(); return at(m_mem.size()-1); endfunction

    // Newest-first traversal helper: k == 0 is the newest entry.
    function T from_newest(int k);
      int idx;
      if (m_mem.size() == 0) return at(0);
      idx = m_mem.size() - 1 - k;
      if (idx < 0) idx = 0;
      return m_mem[idx];
    endfunction

    // Find the newest entry whose timestamp <= t. Returns -1 if none.
    function int search_leq(longint unsigned t);
      for (int i = m_mem.size()-1; i >= 0; i--)
        if (m_mem[i].timestamp <= t) return i;
      return -1;
    endfunction

    function int search_next_ge(longint unsigned t);
      for (int i = 0; i < m_mem.size(); i++)
        if (m_mem[i].timestamp >= t) return i;
      return -1;
    endfunction

    // ---- text ----
    pure virtual function string ring_name();
    pure virtual function string fmt(int idx_oldest_first, T t);

    function string line(int idx);
      return fmt(idx, at(idx));
    endfunction

    // Newest N entries, printed newest first.
    function string dump(int n = 16, string hdr = "");
      int lim = (n < m_mem.size()) ? n : m_mem.size();
      string s;
      s = $sformatf("---- %-12s %0d/%0d retained%s ----\n",
                    ring_name(), m_mem.size(), DEPTH_C,
                    is_frozen() ? $sformatf("  FROZEN@cyc%0d", m_frozen_at) : "");
      if (hdr != "") s = {s, hdr, "\n"};
      for (int k = lim; k > 0; k--)
        s = {s, line(lim - k), "\n"};
      return s;
    endfunction
  endclass

  // ---- typed rings ---------------------------------------------------------
  class rf_fetch_ring  extends rf_ring_base #(fetch_txn_t, DEFAULT_RING);
    function string ring_name(); return "FETCH"; endfunction
    function string fmt(int idx_oldest_first, fetch_txn_t t);
      return $sformatf("  cyc %8d  rel %8d  PC=0x%08h  I=0x%08h  %s %s",
                       t.timestamp, t.rel_cycle, t.pc, t.instr,
                       t.branch_taken ? "BR" : "  ",
                       region_name(t.region));
    endfunction
  endclass

  class rf_retire_ring extends rf_ring_base #(retire_txn_t, DEFAULT_RING);
    function string ring_name(); return "RETIRE"; endfunction
    function string fmt(int idx_oldest_first, retire_txn_t t);
      return $sformatf("  cyc %8d  rel %8d  PC=0x%08h  x%08h  %s x%0d=0x%08h  %s%s%s",
                       t.timestamp, t.rel_cycle, t.pc, t.instr,
                       t.reg_we ? "rd" : "--",
                       t.rd_addr, t.rd_wdata,
                       t.trap        ? "[TRAP] " : "",
                       t.irq_ack     ? $sformatf("[IRQ %0s] ", irq_src_name(t.irq_src)) : "",
                       t.is_mret     ? "[MRET]" : "");
    endfunction
  endclass

  class rf_lsu_ring    extends rf_ring_base #(lsu_txn_t, DEFAULT_RING);
    function string ring_name(); return "LSU"; endfunction
    function string fmt(int idx_oldest_first, lsu_txn_t t);
      return $sformatf("  cyc %8d  PC=0x%08h  %s %s slot=%0d  addr=0x%08h  %s  be=%b  wait=%0d  %s%s",
                       t.timestamp, t.pc, lsu_op_name(t.op), txn_tag(dir_of(t.is_store)),
                       t.apb_slot, t.addr,
                       t.is_store ? $sformatf("w=0x%08h", t.wdata)
                                  : $sformatf("r=0x%08h", t.rdata),
                       t.be, t.wait_cycles, region_name(t.region),
                       t.err ? "  ERR" : "");
    endfunction
  endclass

  class rf_axil_ring   extends rf_ring_base #(axi_txn_t, DEFAULT_RING);
    function string ring_name(); return "AXILITE"; endfunction
    function string fmt(int idx_oldest_first, axi_txn_t t);
      return $sformatf("  cyc %8d  %s addr=0x%08h  %s  be=%b  resp=%s  aw_wait=%0d w_wait=%0d b_wait=%0d  %s",
                       t.timestamp, t.is_write ? "WR" : "RD", t.addr,
                       t.is_write ? $sformatf("w=0x%08h", t.data)
                                  : $sformatf("r=0x%08h", t.data),
                       t.strb, axi_resp_name(t.resp),
                       t.aw_wait, t.w_wait, t.b_wait,
                       t.is_mmio ? region_name(RF_REGION_MMIO) : "MEM");
    endfunction
  endclass

  class rf_apb_ring    extends rf_ring_base #(apb_txn_t, DEFAULT_RING);
    function string ring_name(); return "APB"; endfunction
    function string fmt(int idx_oldest_first, apb_txn_t t);
      return $sformatf("  cyc %8d  [%0d]%-6s %s  paddr=0x%08h  pw=0x%08h pr=0x%08h pstrb=%b  ws=%0d%s",
                       t.timestamp, t.slot, apb_slot_name(t.slot),
                       t.pwrite ? "WR" : "RD", t.paddr, t.pwdata, t.prdata,
                       t.pstrb, t.wait_states, t.pslverr ? "  SLVERR" : "");
    endfunction
  endclass

  class rf_irq_ring     extends rf_ring_base #(irq_txn_t, DEFAULT_RING);
    function string ring_name(); return "IRQ"; endfunction
    function string fmt(int idx_oldest_first, irq_txn_t t);
      return $sformatf("  cyc %8d  id=%0d %-14s assert=%b grant=%b ack=%b  cause=0x%08h  mip=%b mie=%b  lat=%0d depth=%0d%s",
                       t.timestamp, t.irq_id, irq_src_name(t.src),
                       t.asserted, t.granted, t.acked, t.cause,
                       t.mip, t.mie, t.latency_cycles, t.nest_depth,
                       t.is_mret ? " [MRET]" : "");
    endfunction
  endclass

// =============================================================================
// 1. rf_trace_db
// =============================================================================
class rf_trace_db;

  // ---- live stream (bounded, trimmed from the front) ----
  fetch_txn_t  q_fetch  [$];
  retire_txn_t q_retire [$];
  lsu_txn_t    q_lsu    [$];
  axi_evt_t    q_axi_evt[$];
  axi_txn_t    q_axi    [$];
  apb_txn_t    q_apb    [$];
  irq_txn_t    q_irq    [$];
  gpio_txn_t   q_gpio   [$];
  uart_txn_t   q_uart   [$];
  i2c_txn_t    q_i2c    [$];
  spi_txn_t    q_spi    [$];

  // ---- post-mortem cyclic rings (S1.11) ----
  rf_fetch_ring  r_fetch;
  rf_retire_ring r_retire;
  rf_lsu_ring    r_lsu;
  rf_axil_ring   r_axil;
  rf_apb_ring    r_apb;
  rf_irq_ring    r_irq;

  int unsigned live_depth = DEFAULT_LIVE_Q;

  // ---- global bookkeeping ----
  longint unsigned n_fatal;
  longint unsigned fatal_cycle;
  int               fatal_layer;
  string            fatal_check_id;
  string            fatal_msg;
  logic [31:0]      fatal_pc;

  bit frozen;
  longint unsigned freeze_cycle;

  function new();
    r_fetch  = new();
    r_retire = new();
    r_lsu    = new();
    r_axil   = new();
    r_apb    = new();
    r_irq    = new();

    frozen       = 0;
    freeze_cycle = 0;
    n_fatal      = 0;
    fatal_cycle  = 0;
    fatal_layer  = 0;
    fatal_check_id = "";
    fatal_msg    = "";
    fatal_pc     = 32'h0;
  endfunction

  // ---- producers ----------------------------------------------------------
  // The live stream is trimmed from the front rather than allowed to grow
  // without bound. XSim 2022.2 does not accept a `ref dynamic` generic trim
  // helper, so the one-line trim is inlined per record method.
  function void record_fetch(fetch_txn_t t, bit fz);
    q_fetch.push_back(t);
    while (q_fetch.size() > live_depth) void'(q_fetch.pop_front());
    r_fetch.push(t, fz);
  endfunction

  function void record_retire(retire_txn_t t, bit fz);
    q_retire.push_back(t);
    while (q_retire.size() > live_depth) void'(q_retire.pop_front());
    r_retire.push(t, fz);
  endfunction

  function void record_lsu(lsu_txn_t t, bit fz);
    q_lsu.push_back(t);
    while (q_lsu.size() > live_depth) void'(q_lsu.pop_front());
    r_lsu.push(t, fz);
  endfunction

  function void record_axi_evt(axi_evt_t t, bit fz);
    q_axi_evt.push_back(t);
    while (q_axi_evt.size() > live_depth) void'(q_axi_evt.pop_front());
  endfunction

  function void record_axi(axi_txn_t t, bit fz);
    q_axi.push_back(t);
    while (q_axi.size() > live_depth) void'(q_axi.pop_front());
    r_axil.push(t, fz);
  endfunction

  function void record_apb(apb_txn_t t, bit fz);
    q_apb.push_back(t);
    while (q_apb.size() > live_depth) void'(q_apb.pop_front());
    r_apb.push(t, fz);
  endfunction

  function void record_irq(irq_txn_t t, bit fz);
    q_irq.push_back(t);
    while (q_irq.size() > live_depth) void'(q_irq.pop_front());
    r_irq.push(t, fz);
  endfunction

  function void record_gpio(gpio_txn_t t, bit fz);
    q_gpio.push_back(t);
    while (q_gpio.size() > live_depth) void'(q_gpio.pop_front());
  endfunction

  function void record_uart(uart_txn_t t, bit fz);
    q_uart.push_back(t);
    while (q_uart.size() > live_depth) void'(q_uart.pop_front());
  endfunction

  function void record_i2c(i2c_txn_t t, bit fz);
    q_i2c.push_back(t);
    while (q_i2c.size() > live_depth) void'(q_i2c.pop_front());
  endfunction

  function void record_spi(spi_txn_t t, bit fz);
    q_spi.push_back(t);
    while (q_spi.size() > live_depth) void'(q_spi.pop_front());
  endfunction

  // ---- first-fatal latch (feeds failure_reporter.freeze_monitors) ----------
  function void note_fatal(int layer, string check_id, string msg,
                           longint unsigned cyc, logic [31:0] pc);
    if (n_fatal == 0) begin
      n_fatal        = 1;
      fatal_layer    = layer;
      fatal_check_id = check_id;
      fatal_msg      = msg;
      fatal_cycle    = cyc;
      fatal_pc       = pc;
      frozen         = 1;
      freeze_cycle   = cyc;
    end
  endfunction

  // ---- cross-monitor joins used by PATH-01..06 ----------------------------
  // One core MMIO access -> exactly one AXI transaction -> exactly one APB
  // transfer on the decoded slot. These helpers are the query surface the
  // mmio_path_scoreboard uses; keeping them here means the scoreboard never
  // needs direct access to the monitors.

  // Find the newest LSU access at address `addr` at or before cycle `cyc`.
  function lsu_txn_t lsu_at(logic [31:0] addr, longint unsigned cyc);
    lsu_txn_t z;
    z = '0;
    for (int i = q_lsu.size()-1; i >= 0; i--) begin
      if ((q_lsu[i].timestamp <= cyc) && (q_lsu[i].addr == addr)) return q_lsu[i];
    end
    return z;
  endfunction

  // Find the newest AXI-Lite transaction at `addr` at or before `cyc`.
  function axi_txn_t axil_at(logic [31:0] addr, longint unsigned cyc);
    axi_txn_t z;
    z = '0;
    for (int i = q_axi.size()-1; i >= 0; i--) begin
      if ((q_axi[i].timestamp <= cyc) && (q_axi[i].addr == addr)) return q_axi[i];
    end
    return z;
  endfunction

  // Find the newest APB transfer on `slot` at or before `cyc`.
  function apb_txn_t apb_on_slot(int unsigned slot, longint unsigned cyc);
    apb_txn_t z;
    z = '0;
    for (int i = q_apb.size()-1; i >= 0; i--) begin
      if ((q_apb[i].timestamp <= cyc) && (q_apb[i].slot == slot)) return q_apb[i];
    end
    return z;
  endfunction

  // Every APB transfer that landed on the wrong slot for `addr`.
  function int count_wrong_slot(logic [31:0] addr);
    int unsigned want;
    int n;
    n    = 0;
    want = get_expected_apb_slot(addr);
    for (int i = q_apb.size()-1; i >= 0; i--)
      if ((q_apb[i].paddr[31:12] == addr[31:12]) && (q_apb[i].slot != want)) n++;
    return n;
  endfunction

  function longint unsigned count_by_region(rf_region_e r);
    longint unsigned n;
    n = 0;
    for (int i = 0; i < q_lsu.size(); i++)
      if (q_lsu[i].region == r) n++;
    return n;
  endfunction
endclass : rf_trace_db

endpackage : tb_pkg

`endif // RF_TB_PKG_SV