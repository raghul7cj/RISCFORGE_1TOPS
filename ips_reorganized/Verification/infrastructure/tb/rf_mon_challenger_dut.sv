// =============================================================================
// Module Name : rf_mon_challenger_dut.sv
// Description : Advanced high-coverage structural DUT stub for empirical stress
//               testing of the RISCFORGE passive monitor layer.
//
// Generates complex, multi-phase execution scenarios with distinct address spaces:
//   Phase 1 (cyc 10-40)  : Normal sequential instruction fetch & retirement (0x1000..0x100C)
//   Phase 2 (cyc 50-85)  : Branch taken at 0x1020 with speculative wrong-path flushes (0x1024, 0x1028)
//   Phase 3 (cyc 90-155) : 5-iteration loop execution (0x1050, 0x1054)
//   Phase 4 (cyc 160-215): Data hazard stall & LSU memory wait states (0x1070, 0x1074)
//   Phase 5 (cyc 220-265): Exception / Trap commit (ECALL at 0x1080) & MRET (0x2000)
//   Phase 6 (cyc 270-395): Ring buffer wrap-around burst (>100 transactions) (0x3000+)
//   Phase 7 (cyc 400-450): Post-freeze continuous stimulus (0x4000+)
// =============================================================================

`timescale 1ns/1ps

module rf_mon_chall_fetch;
  logic [31:0] PCF, PCPlus4F, PC_next, InstrF, exc_tval_F;
  logic [5:0]  exc_cause_F;
  logic        imem_stall, exc_valid_F;
endmodule

module rf_mon_chall_arbiter;
  logic [1:0] irq_class_o;
  logic       rr_ptr_c1, rr_ptr_c0;
endmodule

module rf_mon_chall_gateway;
  logic [5:0] pend_o, pend_q;
endmodule

module rf_mon_chall_csr;
  logic [1:0]  nest_depth, cur_class_r;
  logic [31:0] mepc_stack [0:1];
  logic [31:0] mcause_stack [0:1];
endmodule

module rf_mon_chall_core;
  rf_mon_chall_fetch    Fetch();
  rf_mon_chall_arbiter  u_irq_arbiter();
  rf_mon_chall_gateway  u_irq_gateway();
  rf_mon_chall_csr      csr_file();

  logic        imem_sram_en = 1'b0, StallF = 1'b0, StallD = 1'b0, FlushD = 1'b0;

  logic        valid_M = 1'b0;
  logic [31:0] PC_M = '0;
  logic [4:0]  lsunitM = '0;
  logic        lsu_mem_req = 1'b0, lsu_mem_we = 1'b0, lsu_mem_stall = 1'b0, lsu_mem_err = 1'b0;
  logic [31:0] lsu_mem_addr = '0, lsu_mem_wdata = '0, lsu_mem_rdata = '0;
  logic [3:0]  lsu_mem_be = '0;

  logic        valid_W = 1'b0, wb_commit = 1'b0, RegWriteW_gated = 1'b0;
  logic [31:0] PC_W = '0, ResultW = '0;
  logic [4:0]  RDW = '0;
  logic        trap_commit_valid = 1'b0, trap_commit_is_interrupt = 1'b0, mret_commit = 1'b0, is_mret_W = 1'b0;
  logic [30:0] trap_commit_cause = '0;
  logic [31:0] trap_commit_pc = '0;
  logic        csr_write_en_W = 1'b0;
  logic [11:0] csr_addr_W = '0;
  logic [31:0] new_csr_W = '0;
  logic        exc_valid_W = 1'b0;
  logic [5:0]  exc_cause_W = '0;
  logic [31:0] exc_tval_W = '0, exc_pc_W = '0;

  logic [15:0] fast_irq_i = '0;
  logic        timer_irq_i = 1'b0;
  logic [31:0] csr_mip_sb = '0, csr_mie_sb = '0, csr_mintprio_sb = '0;
  logic        csr_mstatus_mie_sb = 1'b0;
  logic        irq_valid = 1'b0, irq_pending = 1'b0;
  logic [4:0]  irq_cause_enc = '0;
  logic [30:0] irq_id = '0;
endmodule

module rf_mon_challenger_dut import tb_pkg::*; (input logic clk);

  // AXI-Lite
  typedef struct packed { logic [31:0] addr; logic [2:0] prot; } chal_aw_chan_t;
  typedef struct packed { logic [31:0] data; logic [3:0] strb; } chal_w_chan_t;
  typedef struct packed { logic [1:0]  resp; }                    chal_b_chan_t;
  typedef struct packed { logic [31:0] addr; logic [2:0] prot; } chal_ar_chan_t;
  typedef struct packed { logic [31:0] data; logic [1:0] resp; } chal_r_chan_t;

  typedef struct packed {
    chal_aw_chan_t aw; logic aw_valid;
    chal_w_chan_t  w;  logic w_valid;
                       logic b_ready;
    chal_ar_chan_t ar; logic ar_valid;
                       logic r_ready;
  } chal_axi_req_t;

  typedef struct packed {
    logic aw_ready, w_ready;
    chal_b_chan_t b; logic b_valid;
    logic ar_ready;
    chal_r_chan_t r; logic r_valid;
  } chal_axi_resp_t;

  // APB
  typedef struct packed {
    logic [31:0] paddr;  logic [2:0] pprot;
    logic psel, penable, pwrite;
    logic [31:0] pwdata; logic [3:0] pstrb;
  } chal_apb_req_t;

  typedef struct packed {
    logic pready; logic [31:0] prdata; logic pslverr;
  } chal_apb_resp_t;

  chal_axi_req_t  core_axi_req;
  chal_axi_resp_t core_axi_resp;
  chal_apb_req_t  apb_req  [6];
  chal_apb_resp_t apb_resp [6];

  rf_mon_chall_core i_riscv_core();

  logic        gpio_global_interrupt_o, i2c_interrupt_o, uart_int_o;
  logic [1:0]  spi_events_o;
  logic [3:0]  timer0_irq_o, timer1_irq_o;
  logic [31:0] gpio_in_sync_o, gpio_pin_level_interrupts_o;
  logic        i2c_scl_i, i2c_sda_i, i2c_scl_o, i2c_scl_oen_o;
  logic        i2c_sda_o, i2c_sda_oen_o;
  logic        spi_sdi1_i;

  int unsigned cyc = 0;

  // Instruction Opcode Constants for verification
  localparam logic [31:0] OP_ADDI_X1 = 32'h0010_0093; // addi x1, x0, 1
  localparam logic [31:0] OP_ADDI_X2 = 32'h0020_0113; // addi x2, x0, 2
  localparam logic [31:0] OP_ADD_X3  = 32'h0020_81b3; // add  x3, x1, x2
  localparam logic [31:0] OP_LUI_X4  = 32'h0001_8237; // lui  x4, 0x18
  localparam logic [31:0] OP_BEQ     = 32'h0220_8463; // beq  x1, x2, +32
  localparam logic [31:0] OP_FLUSH1  = 32'h1111_1113; // wrong path 1
  localparam logic [31:0] OP_FLUSH2  = 32'h2222_2213; // wrong path 2
  localparam logic [31:0] OP_TARGET  = 32'h3333_3313; // target at 0x1040
  localparam logic [31:0] OP_LOOP1   = 32'h0014_0413; // addi x8, x8, 1
  localparam logic [31:0] OP_LOOP2   = 32'h0054_1493; // slli x9, x8, 2
  localparam logic [31:0] OP_LW      = 32'h0005_a503; // lw   x10, 0(x11)
  localparam logic [31:0] OP_ECALL   = 32'h0000_0073; // ecall

  always_ff @(posedge clk) begin
    cyc <= cyc + 1;

    // Default pin / bus states
    i2c_scl_i <= 1'b1; i2c_sda_i <= 1'b1;
    i2c_scl_o <= 1'b1; i2c_scl_oen_o <= 1'b0;
    i2c_sda_o <= 1'b1; i2c_sda_oen_o <= 1'b0;
    spi_sdi1_i <= 1'b0; gpio_in_sync_o <= '0;

    // Default core states
    i_riscv_core.exc_valid_W       <= 1'b0;
    i_riscv_core.trap_commit_valid <= 1'b0;
    i_riscv_core.mret_commit       <= 1'b0;
    i_riscv_core.is_mret_W         <= 1'b0;
    i_riscv_core.csr_write_en_W    <= 1'b0;

    // =========================================================================
    // PHASE 1: Normal In-order Execution (cyc 10..40)
    // Only 4 distinct sequential instructions: 0x1000, 0x1004, 0x1008, 0x100C
    // =========================================================================
    if (cyc >= 10 && cyc <= 40) begin
      case (cyc)
        10: begin
          i_riscv_core.imem_sram_en      <= 1'b1;
          i_riscv_core.StallF            <= 1'b0;
          i_riscv_core.Fetch.imem_stall  <= 1'b0;
          i_riscv_core.Fetch.PCF         <= 32'h0000_1000;
          i_riscv_core.Fetch.InstrF      <= OP_ADDI_X1;
          i_riscv_core.Fetch.PC_next     <= 32'h0000_1004;
          i_riscv_core.valid_W           <= 1'b0;
        end
        11: begin
          i_riscv_core.Fetch.PCF         <= 32'h0000_1004;
          i_riscv_core.Fetch.InstrF      <= OP_ADDI_X2;
          i_riscv_core.Fetch.PC_next     <= 32'h0000_1008;
        end
        12: begin
          i_riscv_core.Fetch.PCF         <= 32'h0000_1008;
          i_riscv_core.Fetch.InstrF      <= OP_ADD_X3;
          i_riscv_core.Fetch.PC_next     <= 32'h0000_100C;
        end
        13: begin
          i_riscv_core.Fetch.PCF         <= 32'h0000_100C;
          i_riscv_core.Fetch.InstrF      <= OP_LUI_X4;
          i_riscv_core.Fetch.PC_next     <= 32'h0000_1010;
        end
        14: begin
          // Stop fetching in Phase 1
          i_riscv_core.imem_sram_en      <= 1'b0;
          // 0x1000 commits at WB
          i_riscv_core.valid_W           <= 1'b1;
          i_riscv_core.wb_commit         <= 1'b1;
          i_riscv_core.PC_W              <= 32'h0000_1000;
          i_riscv_core.RDW               <= 5'd1;
          i_riscv_core.ResultW           <= 32'd1;
          i_riscv_core.RegWriteW_gated   <= 1'b1;
        end
        15: begin
          // 0x1004 commits at WB
          i_riscv_core.PC_W              <= 32'h0000_1004;
          i_riscv_core.RDW               <= 5'd2;
          i_riscv_core.ResultW           <= 32'd2;
        end
        16: begin
          // 0x1008 commits at WB
          i_riscv_core.PC_W              <= 32'h0000_1008;
          i_riscv_core.RDW               <= 5'd3;
          i_riscv_core.ResultW           <= 32'd3;
        end
        17: begin
          // 0x100C commits at WB
          i_riscv_core.PC_W              <= 32'h0000_100C;
          i_riscv_core.RDW               <= 5'd4;
          i_riscv_core.ResultW           <= 32'h0001_8000;
        end
        default: begin
          i_riscv_core.imem_sram_en      <= 1'b0;
          i_riscv_core.valid_W           <= 1'b0;
        end
      endcase
    end

    // =========================================================================
    // PHASE 2: Branch Taken & Speculative Flushes (cyc 50..85)
    // Branch at 0x1020, wrong path 0x1024 & 0x1028, target 0x1040
    // =========================================================================
    else if (cyc >= 50 && cyc <= 85) begin
      case (cyc)
        // Cycle 50: Fetch Branch instruction at 0x1020
        50: begin
          i_riscv_core.imem_sram_en      <= 1'b1;
          i_riscv_core.StallF            <= 1'b0;
          i_riscv_core.Fetch.imem_stall  <= 1'b0;
          i_riscv_core.Fetch.PCF         <= 32'h0000_1020;
          i_riscv_core.Fetch.InstrF      <= OP_BEQ;
          i_riscv_core.Fetch.PC_next     <= 32'h0000_1024;
          i_riscv_core.valid_W           <= 1'b0;
        end
        // Cycle 51: Speculative fetch of wrong-path 0x1024 (valid fetch, will be flushed)
        51: begin
          i_riscv_core.Fetch.PCF         <= 32'h0000_1024;
          i_riscv_core.Fetch.InstrF      <= OP_FLUSH1;
          i_riscv_core.Fetch.PC_next     <= 32'h0000_1028;
        end
        // Cycle 52: Speculative fetch of wrong-path 0x1028 (valid fetch, will be flushed)
        52: begin
          i_riscv_core.Fetch.PCF         <= 32'h0000_1028;
          i_riscv_core.Fetch.InstrF      <= OP_FLUSH2;
          i_riscv_core.Fetch.PC_next     <= 32'h0000_1040; // branch resolves TAKEN to 0x1040
        end
        // Cycle 53: Redirect cycle (imem_stall=1, StallF=1 during branch drain)
        53: begin
          i_riscv_core.Fetch.imem_stall  <= 1'b1;
          i_riscv_core.StallF            <= 1'b1;
          i_riscv_core.Fetch.PCF         <= 32'h0000_1040;
        end
        // Cycle 54: Redirect target fetch 0x1040
        54: begin
          i_riscv_core.Fetch.imem_stall  <= 1'b0;
          i_riscv_core.StallF            <= 1'b0;
          i_riscv_core.imem_sram_en      <= 1'b1;
          i_riscv_core.Fetch.PCF         <= 32'h0000_1040;
          i_riscv_core.Fetch.InstrF      <= OP_TARGET;
          i_riscv_core.Fetch.PC_next     <= 32'h0000_1044;
        end
        // Cycle 55: Branch 0x1020 commits at WB, target continues fetching
        55: begin
          i_riscv_core.imem_sram_en      <= 1'b1;
          i_riscv_core.valid_W           <= 1'b1;
          i_riscv_core.wb_commit         <= 1'b1;
          i_riscv_core.PC_W              <= 32'h0000_1020;
          i_riscv_core.RegWriteW_gated   <= 1'b0;
          i_riscv_core.RDW               <= 5'd0;
        end
        // Cycle 56..58: Flush bubble (0x1024 and 0x1028 discarded)
        56, 57, 58: begin
          i_riscv_core.imem_sram_en      <= 1'b0;
          i_riscv_core.valid_W           <= 1'b0;
        end
        // Cycle 59: Branch target 0x1040 commits at WB!
        59: begin
          i_riscv_core.valid_W           <= 1'b1;
          i_riscv_core.PC_W              <= 32'h0000_1040;
          i_riscv_core.RegWriteW_gated   <= 1'b1;
          i_riscv_core.RDW               <= 5'd6;
          i_riscv_core.ResultW           <= 32'h0000_0333;
        end
        default: begin
          i_riscv_core.valid_W           <= 1'b0;
          i_riscv_core.imem_sram_en      <= 1'b0;
        end
      endcase
    end

    // =========================================================================
    // PHASE 3: 5-Iteration Loop (cyc 90..155)
    // Loop instructions: 0x1050 (LOOP1), 0x1054 (LOOP2)
    // =========================================================================
    else if (cyc >= 90 && cyc <= 155) begin
      int iter = (cyc - 90) / 6;
      int step = (cyc - 90) % 6;

      if (iter < 5) begin
        case (step)
          0: begin // Fetch 0x1050
            i_riscv_core.imem_sram_en  <= 1'b1;
            i_riscv_core.StallF        <= 1'b0;
            i_riscv_core.Fetch.PCF     <= 32'h0000_1050;
            i_riscv_core.Fetch.InstrF  <= OP_LOOP1;
            i_riscv_core.Fetch.PC_next <= 32'h0000_1054;
            i_riscv_core.valid_W       <= 1'b0;
          end
          1: begin // Fetch 0x1054
            i_riscv_core.Fetch.PCF     <= 32'h0000_1054;
            i_riscv_core.Fetch.InstrF  <= OP_LOOP2;
            i_riscv_core.Fetch.PC_next <= 32'h0000_1050;
          end
          4: begin // Retire 0x1050
            i_riscv_core.valid_W       <= 1'b1;
            i_riscv_core.PC_W          <= 32'h0000_1050;
            i_riscv_core.RDW           <= 5'd8;
            i_riscv_core.ResultW       <= iter + 1;
            i_riscv_core.RegWriteW_gated <= 1'b1;
          end
          5: begin // Retire 0x1054
            i_riscv_core.valid_W       <= 1'b1;
            i_riscv_core.PC_W          <= 32'h0000_1054;
            i_riscv_core.RDW           <= 5'd9;
            i_riscv_core.ResultW       <= (iter + 1) << 2;
            i_riscv_core.RegWriteW_gated <= 1'b1;
          end
          default: i_riscv_core.valid_W <= 1'b0;
        endcase
      end else begin
        i_riscv_core.valid_W      <= 1'b0;
        i_riscv_core.imem_sram_en <= 1'b0;
      end
    end

    // =========================================================================
    // PHASE 4: Pipeline Hazard & Multi-Cycle Stalls (cyc 160..215)
    // Instructions: 0x1070 (LW), 0x1074 (ADDI)
    // =========================================================================
    else if (cyc >= 160 && cyc <= 215) begin
      case (cyc)
        160: begin
          // Fetch LW instruction at 0x1070
          i_riscv_core.imem_sram_en  <= 1'b1;
          i_riscv_core.Fetch.PCF     <= 32'h0000_1070;
          i_riscv_core.Fetch.InstrF  <= OP_LW;
          i_riscv_core.Fetch.PC_next <= 32'h0000_1074;
          i_riscv_core.StallF        <= 1'b0;
          i_riscv_core.valid_W       <= 1'b0;
        end
        161: begin
          // Stalled fetch at 0x1074
          i_riscv_core.Fetch.PCF     <= 32'h0000_1074;
          i_riscv_core.Fetch.InstrF  <= OP_ADDI_X1;
          i_riscv_core.Fetch.PC_next <= 32'h0000_1078;
        end
        // Cycles 162-165: 4 cycles of data hazard stall!
        162, 163, 164, 165: begin
          i_riscv_core.StallF        <= 1'b1; // Freeze PCF
          i_riscv_core.Fetch.imem_stall <= 1'b1;
          i_riscv_core.lsu_mem_req   <= 1'b1;
          i_riscv_core.lsu_mem_stall <= (cyc < 165);
          i_riscv_core.lsu_mem_addr  <= 32'h0002_0040;
          i_riscv_core.lsu_mem_we    <= 1'b0;
          i_riscv_core.lsu_mem_be    <= 4'hF;
          i_riscv_core.valid_W       <= 1'b0;
        end
        166: begin
          // Stall released
          i_riscv_core.StallF        <= 1'b0;
          i_riscv_core.Fetch.imem_stall <= 1'b0;
          i_riscv_core.lsu_mem_req   <= 1'b0;
          i_riscv_core.lsu_mem_stall <= 1'b0;
          // LW retires
          i_riscv_core.valid_W       <= 1'b1;
          i_riscv_core.PC_W          <= 32'h0000_1070;
          i_riscv_core.RDW           <= 5'd10;
          i_riscv_core.ResultW       <= 32'hDEAD_BEEF;
          i_riscv_core.RegWriteW_gated <= 1'b1;
        end
        167: begin
          // 0x1074 retires
          i_riscv_core.valid_W       <= 1'b1;
          i_riscv_core.PC_W          <= 32'h0000_1074;
          i_riscv_core.RDW           <= 5'd1;
          i_riscv_core.ResultW       <= 32'd1;
        end
        default: begin
          i_riscv_core.valid_W       <= 1'b0;
          i_riscv_core.imem_sram_en  <= 1'b0;
        end
      endcase
    end

    // =========================================================================
    // PHASE 5: Exception / Trap Commit (ECALL) (cyc 220..265)
    // ECALL at 0x1080
    // =========================================================================
    else if (cyc >= 220 && cyc <= 265) begin
      case (cyc)
        225: begin
          // Fetch ECALL at 0x1080
          i_riscv_core.imem_sram_en  <= 1'b1;
          i_riscv_core.Fetch.PCF     <= 32'h0000_1080;
          i_riscv_core.Fetch.InstrF  <= OP_ECALL;
          i_riscv_core.Fetch.PC_next <= 32'h0000_1084;
          i_riscv_core.StallF        <= 1'b0;
          i_riscv_core.valid_W       <= 1'b0;
        end
        230: begin
          // Trap commits at WB!
          i_riscv_core.valid_W           <= 1'b1;
          i_riscv_core.exc_valid_W       <= 1'b1; // exception valid
          i_riscv_core.trap_commit_valid <= 1'b1;
          i_riscv_core.trap_commit_is_interrupt <= 1'b0; // synchronous trap
          i_riscv_core.trap_commit_cause <= 31'd11;      // Machine ECALL
          i_riscv_core.trap_commit_pc    <= 32'h0000_1080;
          i_riscv_core.PC_W              <= 32'h0000_1080;
          i_riscv_core.RegWriteW_gated   <= 1'b0;
        end
        231: begin
          i_riscv_core.trap_commit_valid <= 1'b0;
          i_riscv_core.exc_valid_W       <= 1'b0;
          i_riscv_core.valid_W           <= 1'b0;
        end
        240: begin
          // MRET commits
          i_riscv_core.valid_W     <= 1'b1;
          i_riscv_core.mret_commit <= 1'b1;
          i_riscv_core.is_mret_W   <= 1'b1;
          i_riscv_core.PC_W        <= 32'h0000_2000;
        end
        241: begin
          i_riscv_core.mret_commit <= 1'b0;
          i_riscv_core.is_mret_W   <= 1'b0;
          i_riscv_core.valid_W     <= 1'b0;
        end
        default: begin
          i_riscv_core.valid_W      <= 1'b0;
          i_riscv_core.imem_sram_en <= 1'b0;
        end
      endcase
    end

    // =========================================================================
    // PHASE 6: Ring Buffer Wrap-Around Burst (>100 transactions) (cyc 270..395)
    // Distinct address range: 0x3000..0x3200
    // =========================================================================
    else if (cyc >= 270 && cyc <= 395) begin
      i_riscv_core.imem_sram_en      <= 1'b1;
      i_riscv_core.StallF            <= 1'b0;
      i_riscv_core.Fetch.PCF         <= 32'h0000_3000 + (cyc - 270) * 4;
      i_riscv_core.Fetch.InstrF      <= OP_ADDI_X1;
      i_riscv_core.Fetch.PC_next     <= 32'h0000_3004 + (cyc - 270) * 4;

      i_riscv_core.valid_W           <= 1'b1;
      i_riscv_core.wb_commit         <= 1'b1;
      i_riscv_core.exc_valid_W       <= 1'b0;
      i_riscv_core.PC_W              <= 32'h0000_3000 + (cyc - 270) * 4;
      i_riscv_core.RegWriteW_gated   <= 1'b1;
      i_riscv_core.RDW               <= 5'd1;
      i_riscv_core.ResultW           <= cyc;

      // Active LSU, AXI, and APB traffic on even cycles
      if (cyc % 2 == 0) begin
        i_riscv_core.lsu_mem_req     <= 1'b1;
        i_riscv_core.lsu_mem_we      <= 1'b1;
        i_riscv_core.lsu_mem_addr    <= 32'h4000_2000;
        i_riscv_core.lsu_mem_wdata   <= cyc;
        i_riscv_core.lsu_mem_be      <= 4'hF;
        i_riscv_core.lsu_mem_stall   <= 1'b0;

        core_axi_req.aw.addr         <= 32'h4000_2000;
        core_axi_req.aw_valid        <= 1'b1;
        core_axi_resp.aw_ready       <= 1'b1;
        core_axi_req.w.data          <= cyc;
        core_axi_req.w_valid         <= 1'b1;
        core_axi_resp.w_ready        <= 1'b1;
        core_axi_req.b_ready         <= 1'b1;
        core_axi_req.r_ready         <= 1'b1;
        core_axi_resp.b_valid        <= 1'b1;
        core_axi_resp.b.resp         <= AXI_RESP_OKAY;

        apb_req[2].psel              <= 1'b1;
        apb_req[0].penable           <= 1'b1;
        apb_req[0].pwrite            <= 1'b1;
        apb_req[0].paddr             <= 32'h4000_2000;
        apb_req[0].pwdata            <= cyc;
        apb_req[0].pstrb             <= 4'hF;
        apb_resp[2].pready           <= 1'b1;
        apb_resp[2].pslverr          <= 1'b0;
      end else begin
        i_riscv_core.lsu_mem_req     <= 1'b0;
        core_axi_req.aw_valid        <= 1'b0;
        core_axi_req.w_valid         <= 1'b0;
        core_axi_resp.b_valid        <= 1'b0;
        apb_req[2].psel              <= 1'b0;
        apb_req[0].penable           <= 1'b0;
      end
    end

    // =========================================================================
    // PHASE 7: Post-Freeze Active Stimulus (cyc 400..450)
    // Continuous active transactions while freeze=1 is applied by the testbench
    // =========================================================================
    else if (cyc >= 400 && cyc <= 450) begin
      i_riscv_core.imem_sram_en      <= 1'b1;
      i_riscv_core.StallF            <= 1'b0;
      i_riscv_core.Fetch.PCF         <= 32'h0000_4000 + (cyc - 400) * 4;
      i_riscv_core.Fetch.InstrF      <= OP_ADDI_X2;
      i_riscv_core.Fetch.PC_next     <= 32'h0000_4004 + (cyc - 400) * 4;

      i_riscv_core.valid_W           <= 1'b1;
      i_riscv_core.wb_commit         <= 1'b1;
      i_riscv_core.exc_valid_W       <= 1'b0;
      i_riscv_core.PC_W              <= 32'h0000_4000 + (cyc - 400) * 4;
      i_riscv_core.RegWriteW_gated   <= 1'b1;
      i_riscv_core.RDW               <= 5'd2;
      i_riscv_core.ResultW           <= cyc;

      i_riscv_core.lsu_mem_req       <= 1'b1;
      i_riscv_core.lsu_mem_we        <= 1'b1;
      i_riscv_core.lsu_mem_addr      <= 32'h4000_1000;
      i_riscv_core.lsu_mem_wdata     <= cyc;
      i_riscv_core.lsu_mem_be        <= 4'hF;
      i_riscv_core.lsu_mem_stall     <= 1'b0;

      apb_req[1].psel                <= 1'b1;
      apb_req[0].penable             <= 1'b1;
      apb_req[0].pwrite              <= 1'b1;
      apb_req[0].paddr               <= 32'h4000_1000;
      apb_req[0].pwdata              <= cyc;
      apb_req[0].pstrb               <= 4'hF;
      apb_resp[1].pready             <= 1'b1;
      apb_resp[1].pslverr            <= 1'b0;
    end

    // End
    else begin
      i_riscv_core.imem_sram_en  <= 1'b0;
      i_riscv_core.valid_W       <= 1'b0;
      i_riscv_core.lsu_mem_req   <= 1'b0;
      core_axi_req.aw_valid      <= 1'b0;
      core_axi_req.w_valid       <= 1'b0;
      core_axi_resp.b_valid      <= 1'b0;
      apb_req[1].psel            <= 1'b0;
      apb_req[2].psel            <= 1'b0;
      apb_req[0].penable         <= 1'b0;
    end
  end

endmodule
