`timescale 1ns / 1ps

module csr_regfile #(
  parameter integer XLEN = 32
) (
  // ============================================================================
  // Clock & Reset (SoC integration)
  // ============================================================================
  input  wire        clk_i,
  input  wire        rst_n_i,
  output wire        csr_valid_o,

  // ============================================================================
  // PORT A: Combinational Read (for Execute stage CSR reads)
  // ============================================================================
  input  wire [11:0] csr_raddr_i,
  output reg  [31:0] csr_rdata_o,

  // ============================================================================
  // PORT B: Synchronous Write (from Writeback - CSR instruction commits)
  // ============================================================================
  input  wire [11:0] csr_waddr_normal_i,
  input  wire [31:0] csr_wdata_normal_i,
  input  wire        csr_write_en_normal_i,

  // ============================================================================
  // PORT C: Sync Write (from Exception Controller - trap/exception path)
  // ============================================================================
  input  wire [11:0] csr_waddr_mret_i,
  input  wire [31:0] csr_wdata_mret_i,
  input  wire        csr_write_en_mret_i,
  input  wire        mret_commit_i,

  // ============================================================================
  // Trap Inputs (from pipeline & trap controller for trap handling)
  // ============================================================================
  input  wire        trap_valid_i,           // Trap detected this cycle
  input  wire [30:0] trap_cause_i,           // Trap cause (0-11 for exc, IRQ ID for intr)
  input  wire [31:0] trap_pc_i,              // PC of faulting instruction (for mepc)
  input  wire [31:0] trap_addr_i,            // Fault address (for mtval on misalign/access-fault)
  input  wire        trap_addr_valid_i,      // Indicates if trap_addr_i is valid (e.g., for load/store faults)
  input  wire        trap_is_interrupt_i,    // 1=interrupt, 0=exception

  input  wire        instr_retired_i,        // Instruction retired (for minstret)

  input  wire        timer_intr_i,           // Timer interrupt pending (for mip)
  input  wire        ext_intr_i,             // External interrupt pending (for mip)
  input  wire        msft_intr_i,            // Software interrupt pending (for mip, set by writes to mip MSIP bit)
  input  wire [15:0] fast_intr_i,            // Fast local interrupts pending for mip[31:16]

  // ============================================================================
  // Sideband Outputs & Preemption Context
  // ============================================================================
  output wire [31:0] mtvec_out_o,            // Trap vector base address
  output wire [31:0] mie_out_o,              // Interrupt enable mask
  output wire [31:0] mip_out_o,              // Interrupt pending bits
  output wire        mstatus_mie_out_o,      // Global interrupt enable bit (mstatus.MIE)
  output wire [31:0] mepc_out_o,             // Exception PC
  output wire [31:0] mcause_out_o,           // Exception cause
  output wire [31:0] mstatus_out_o,          // Full mstatus register
  output wire [1:0]  mintprio_out_o          // Class threshold mintprio[1:0] (to arbiter)
);

  // ============================================================================
  // CSR Storage Registers
  // ============================================================================
  reg [31:0] mstatus_r;    // [3]=MIE, [7]=MPIE, [12:11]=MPP, rest read-as-zero
  reg [31:0] mie_r;        // [3]=MSIE, [7]=MTIE, [11]=MEIE, [31:16]=FLIE
  reg [31:0] mtvec_r;      // [31:2]=BASE, [1:0]=MODE
  reg [31:0] mepc_r;       // Machine exception PC
  reg [31:0] mcause_r;     // Machine cause [31]=interrupt, [30:0]=code
  reg [31:0] mtval_r;      // Machine trap value
  reg [31:0] mscratch_r;   // Machine scratch register

  // Performance Counters (64-bit)
  reg [63:0] mcycle_r;
  reg [63:0] minstret_r;

  // Class threshold for the interrupt arbiter. Software-managed: trap entry and
  // MRET never change it. 0 = all classes eligible, 3 = none. [31:2] read as 0.
  // Ordering corner case (not yet verified): an IRQ may be accepted in Execute
  // using an old threshold while an older mintprio write is still in flight.
  // The write can commit before the IRQ, making that IRQ ineligible. Prevent
  // acceptance across unresolved older gating-CSR writes, or consider this
  // backup: recheck at commit, cancel an ineligible IRQ and replay the replaced
  // instruction from the PC carried by its packet. Cancellation must leave the
  // IRQ pending, suppress its trap/ack/RR update, and flush younger work; the
  // replaced instruction must have made no architectural side effects. This
  // comment records a design option, not behavior implemented by this CSR.
  reg [1:0]  mintprio_r;   // 0x7C0

  // Forward declaration
  wire [31:0] mip_w;

  // ============================================================================
  // CSR Address Decode Constants
  // ============================================================================
  localparam [11:0] MSTATUS_ADDR   = 12'h300;
  localparam [11:0] MIE_ADDR       = 12'h304;
  localparam [11:0] MTVEC_ADDR     = 12'h305;
  localparam [11:0] MSCRATCH_ADDR  = 12'h340;
  localparam [11:0] MEPC_ADDR      = 12'h341;
  localparam [11:0] MCAUSE_ADDR    = 12'h342;
  localparam [11:0] MTVAL_ADDR     = 12'h343;
  localparam [11:0] MIP_ADDR       = 12'h344;
  localparam [11:0] MINTPRIO_ADDR  = 12'h7C0;

  localparam [11:0] MCYCLE_ADDR    = 12'hB00;
  localparam [11:0] MINSTRET_ADDR  = 12'hB02;
  localparam [11:0] MCYCLEH_ADDR   = 12'hB80;
  localparam [11:0] MINSTRETH_ADDR = 12'hB82;

  // ============================================================================
  // PORT A: Combinational Read Mux
  // ============================================================================
  always @(*) begin : read_mux
    case (csr_raddr_i)
      MSTATUS_ADDR:   csr_rdata_o = mstatus_r;
      MIE_ADDR:       csr_rdata_o = mie_r;
      MTVEC_ADDR:     csr_rdata_o = mtvec_r;
      MSCRATCH_ADDR:  csr_rdata_o = mscratch_r;
      MEPC_ADDR:      csr_rdata_o = mepc_r;
      MCAUSE_ADDR:    csr_rdata_o = mcause_r;
      MTVAL_ADDR:     csr_rdata_o = mtval_r;
      MIP_ADDR:       csr_rdata_o = mip_w;
      MINTPRIO_ADDR:  csr_rdata_o = {30'b0, mintprio_r};
      MCYCLE_ADDR:    csr_rdata_o = mcycle_r[31:0];
      MCYCLEH_ADDR:   csr_rdata_o = mcycle_r[63:32];
      MINSTRET_ADDR:  csr_rdata_o = minstret_r[31:0];
      MINSTRETH_ADDR: csr_rdata_o = minstret_r[63:32];
      default:        csr_rdata_o = 32'h0;
    endcase
  end

  // ============================================================================
  // Synchronous Writes
  // ============================================================================
  always @(posedge clk_i or negedge rst_n_i) begin : write_ports
    if (!rst_n_i) begin
      mstatus_r       <= 32'h0;
      mie_r           <= 32'h0;
      mtvec_r         <= 32'h0;
      mepc_r          <= 32'h0;
      mcause_r        <= 32'h0;
      mtval_r         <= 32'h0;
      mscratch_r      <= 32'h0;
      mcycle_r        <= 64'h0;
      minstret_r      <= 64'h0;
      mintprio_r      <= 2'b00;
    end
    else begin
      // Counter increments
      mcycle_r <= mcycle_r + 1'b1;
      if (instr_retired_i) minstret_r <= minstret_r + 1'b1;

      // ----------------------------------------------------------------------
      // Priority 1: Trap Entry (live mepc/mcause/mtval; mintprio untouched)
      // ----------------------------------------------------------------------
      if (trap_valid_i) begin
        mepc_r   <= trap_pc_i;
        mcause_r <= {trap_is_interrupt_i, trap_cause_i};
        mtval_r  <= (trap_addr_valid_i) ? trap_addr_i : 32'h0;

        mstatus_r[3]      <= 1'b0;          // Clear MIE
        mstatus_r[7]      <= mstatus_r[3];  // Save MIE -> MPIE
        mstatus_r[12:11]  <= 2'b11;         // MPP = M-mode
      end

      // ----------------------------------------------------------------------
      // Priority 2: MRET commit (MIE <- this file's own MPIE; mintprio untouched)
      // ----------------------------------------------------------------------
      else if (csr_write_en_mret_i || mret_commit_i) begin
        mstatus_r[3]      <= mstatus_r[7];  // MIE <- MPIE
        mstatus_r[7]      <= 1'b1;          // MPIE = 1
        mstatus_r[12:11]  <= 2'b11;         // MPP = 2'b11
        if (csr_write_en_mret_i && (csr_waddr_mret_i == MSTATUS_ADDR)) begin
          mstatus_r[1] <= csr_wdata_mret_i[1];
        end
      end

      // ----------------------------------------------------------------------
      // Priority 3: Port B writes (instruction commits)
      // ----------------------------------------------------------------------
      else if (csr_write_en_normal_i) begin
        case (csr_waddr_normal_i)
          MSTATUS_ADDR:  mstatus_r  <= (csr_wdata_normal_i & 32'h0000188A) | (mstatus_r & ~32'h0000188A);
          MIE_ADDR:      mie_r      <= (csr_wdata_normal_i & 32'hFFFF0880) | (mie_r & ~32'hFFFF0880);
          MTVEC_ADDR:    mtvec_r    <= {csr_wdata_normal_i[31:2], 1'b0, (csr_wdata_normal_i[1:0] == 2'b01)};
          MSCRATCH_ADDR: mscratch_r <= csr_wdata_normal_i;
          MEPC_ADDR:     mepc_r     <= {csr_wdata_normal_i[31:2], 2'b00};
          MCAUSE_ADDR:   mcause_r   <= csr_wdata_normal_i;
          MTVAL_ADDR:    mtval_r    <= csr_wdata_normal_i;
          MINTPRIO_ADDR: mintprio_r <= csr_wdata_normal_i[1:0]; // [31:2] ignored
          MCYCLE_ADDR:   mcycle_r[31:0]   <= csr_wdata_normal_i;
          MCYCLEH_ADDR:  mcycle_r[63:32]  <= csr_wdata_normal_i;
          MINSTRET_ADDR: minstret_r[31:0]  <= csr_wdata_normal_i;
          MINSTRETH_ADDR:minstret_r[63:32] <= csr_wdata_normal_i;
          default: ;
        endcase
      end
    end
  end

  // ============================================================================
  // Software Interrupt (MSIP) Handling
  // ============================================================================
  // In this single-hart standalone profile without CLINT, MSI is omitted.
  // Per RISC-V Privileged ISA Specification (v1.13):
  // MSIP in mip and MSIE in mie are hardwired to read-only zero.
  // Direct CSR writes to mip cannot set MSIP.
  assign mip_w = {fast_intr_i, 4'b0, ext_intr_i, 3'b0, timer_intr_i, 3'b0, msft_intr_i, 3'b0};

  // ============================================================================
  // Sideband Outputs
  // ============================================================================
  assign mtvec_out_o       = mtvec_r;
  assign mie_out_o         = mie_r;
  assign mip_out_o         = mip_w;
  assign mstatus_mie_out_o = mstatus_r[3];
  assign mepc_out_o        = mepc_r;
  assign mcause_out_o      = mcause_r;
  assign mstatus_out_o     = mstatus_r;
  assign mintprio_out_o    = mintprio_r;

  assign csr_valid_o = (csr_raddr_i == MSTATUS_ADDR)   ||
                       (csr_raddr_i == MIE_ADDR)       ||
                       (csr_raddr_i == MTVEC_ADDR)     ||
                       (csr_raddr_i == MSCRATCH_ADDR)  ||
                       (csr_raddr_i == MEPC_ADDR)      ||
                       (csr_raddr_i == MCAUSE_ADDR)    ||
                       (csr_raddr_i == MTVAL_ADDR)     ||
                       (csr_raddr_i == MIP_ADDR)       ||
                       (csr_raddr_i == MINTPRIO_ADDR)  ||
                       (csr_raddr_i == MCYCLE_ADDR)    ||
                       (csr_raddr_i == MINSTRET_ADDR)  ||
                       (csr_raddr_i == MCYCLEH_ADDR)   ||
                       (csr_raddr_i == MINSTRETH_ADDR);

endmodule
