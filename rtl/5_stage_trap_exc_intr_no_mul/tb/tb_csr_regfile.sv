`timescale 1ns/1ps

module tb_csr_regfile;
  localparam int CLK_HALF = 5;

  logic clk;
  logic rst_n;

  // Port A
  logic [11:0] csr_raddr;
  wire  [31:0] csr_rdata;

  // Port B (normal)
  logic [11:0] csr_waddr_n;
  logic [31:0] csr_wdata_n;
  logic        csr_wen_n;

  // Port C (mret/priv)
  logic [11:0] csr_waddr_m;
  logic [31:0] csr_wdata_m;
  logic        csr_wen_m;

  // Trap bundle
  logic        trap_valid;
  logic [30:0] trap_cause;
  logic [31:0] trap_pc;
  logic [31:0] trap_addr;
  logic        trap_addr_valid;
  logic        trap_is_interrupt;

  // Counters / IRQ inputs
  logic instr_retired;
  logic timer_intr;
  logic ext_intr;
  logic msft_intr;

  wire [31:0] mtvec_out;
  wire [31:0] mie_out;
  wire [31:0] mip_out;
  wire        mstatus_mie_out;
  wire [31:0] mepc_out;
  wire [31:0] mcause_out;
  wire [31:0] mstatus_out;

  // CSR addresses
  localparam [11:0] MSTATUS_ADDR  = 12'h300;
  localparam [11:0] MIE_ADDR      = 12'h304;
  localparam [11:0] MTVEC_ADDR    = 12'h305;
  localparam [11:0] MSCRATCH_ADDR = 12'h340;
  localparam [11:0] MEPC_ADDR     = 12'h341;
  localparam [11:0] MCAUSE_ADDR   = 12'h342;
  localparam [11:0] MTVAL_ADDR    = 12'h343;
  localparam [11:0] MIP_ADDR      = 12'h344;

  // Clock
  initial clk = 1'b0;
  always #(CLK_HALF) clk = ~clk;

  // DUT
  csr_regfile dut (
    .clk_i(clk),
    .rst_n_i(rst_n),

    .csr_raddr_i(csr_raddr),
    .csr_rdata_o(csr_rdata),

    .csr_waddr_normal_i(csr_waddr_n),
    .csr_wdata_normal_i(csr_wdata_n),
    .csr_write_en_normal_i(csr_wen_n),

    .csr_waddr_mret_i(csr_waddr_m),
    .csr_wdata_mret_i(csr_wdata_m),
    .csr_write_en_mret_i(csr_wen_m),

    .trap_valid_i(trap_valid),
    .trap_cause_i(trap_cause),
    .trap_pc_i(trap_pc),
    .trap_addr_i(trap_addr),
    .trap_addr_valid_i(trap_addr_valid),
    .trap_is_interrupt_i(trap_is_interrupt),

    .instr_retired_i(instr_retired),

    .timer_intr_i(timer_intr),
    .ext_intr_i(ext_intr),
    .msft_intr_i(msft_intr),

    .mtvec_out_o(mtvec_out),
    .mie_out_o(mie_out),
    .mip_out_o(mip_out),
    .mstatus_mie_out_o(mstatus_mie_out),
    .mepc_out_o(mepc_out),
    .mcause_out_o(mcause_out),
    .mstatus_out_o(mstatus_out)
  );

  int pass, fail;

  task automatic check(input bit cond, input string msg);
    if (!cond) begin
      $error("FAIL: %s", msg);
      fail++;
    end else begin
      pass++;
    end
  endtask

  task automatic reset_dut();
    rst_n = 1'b0;
    csr_raddr = '0;
    csr_wen_n = 1'b0;
    csr_wen_m = 1'b0;
    trap_valid = 1'b0;
    trap_cause = '0;
    trap_pc = '0;
    trap_addr = '0;
    trap_addr_valid = 1'b0;
    trap_is_interrupt = 1'b0;
    instr_retired = 1'b0;
    timer_intr = 1'b0;
    ext_intr = 1'b0;
    msft_intr = 1'b0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
  endtask

  task automatic write_normal(input [11:0] addr, input [31:0] data);
    @(posedge clk);
    csr_waddr_n <= addr;
    csr_wdata_n <= data;
    csr_wen_n   <= 1'b1;
    @(posedge clk);
    csr_wen_n   <= 1'b0;
  endtask

  task automatic write_mret(input [11:0] addr, input [31:0] data);
    @(posedge clk);
    csr_waddr_m <= addr;
    csr_wdata_m <= data;
    csr_wen_m   <= 1'b1;
    @(posedge clk);
    csr_wen_m   <= 1'b0;
  endtask

  task automatic read_csr(input [11:0] addr, output [31:0] data);
    csr_raddr = addr;
    #1;
    data = csr_rdata;
  endtask

  task automatic fire_trap(
    input [30:0] cause,
    input [31:0] pc,
    input [31:0] addr,
    input        addr_valid,
    input        is_intr
  );
    @(posedge clk);
    trap_valid        <= 1'b1;
    trap_cause        <= cause;
    trap_pc           <= pc;
    trap_addr         <= addr;
    trap_addr_valid   <= addr_valid;
    trap_is_interrupt <= is_intr;
    @(posedge clk);
    trap_valid        <= 1'b0;
  endtask

  initial begin
    pass = 0;
    fail = 0;

    $display("=== tb_csr_regfile ===");
    reset_dut();

    // CSR-S1: mscratch round-trip
    begin
      logic [31:0] rd;
      write_normal(MSCRATCH_ADDR, 32'hDEADBEEF);
      read_csr(MSCRATCH_ADDR, rd);
      check(rd == 32'hDEADBEEF, "MSCRATCH round-trip");
    end

    // CSR-S2: mstatus mask
    begin
      logic [31:0] rd;
      write_normal(MSTATUS_ADDR, 32'hFFFF_FFFF);
      read_csr(MSTATUS_ADDR, rd);
      check(rd == 32'h0000_1888, "MSTATUS write mask");
    end

    // CSR-S3: mtvec MODE frozen (bits[1:0]==00)
    begin
      logic [31:0] rd;
      write_normal(MTVEC_ADDR, 32'hFFFF_FFFF);
      read_csr(MTVEC_ADDR, rd);
      check(rd[1:0] == 2'b00, "MTVEC.MODE frozen to 00");
    end

    // CSR-S5: trap entry atomic update
    begin
      logic [31:0] rd_mstatus;
      fire_trap(31'd11, 32'h0000_0100, 32'h0, 1'b0, 1'b0);
      read_csr(MEPC_ADDR, rd_mstatus); // reuse var
      check(rd_mstatus == 32'h0000_0100, "Trap writes MEPC");
      read_csr(MCAUSE_ADDR, rd_mstatus);
      check(rd_mstatus == 32'h0000_000B, "Trap writes MCAUSE (exception)");
      read_csr(MTVAL_ADDR, rd_mstatus);
      check(rd_mstatus == 32'h0, "Trap writes MTVAL=0 when addr_invalid");
      read_csr(MSTATUS_ADDR, rd_mstatus);
      check(rd_mstatus[3] == 1'b0, "Trap clears MSTATUS.MIE");
      check(rd_mstatus[12:11] == 2'b11, "Trap sets MSTATUS.MPP=11");
    end

    // CSR-S8: Port C mstatus write applies only key bits
    begin
      logic [31:0] rd;
      write_mret(MSTATUS_ADDR, 32'h0000_1888); // set MIE/MPIE/MPP
      read_csr(MSTATUS_ADDR, rd);
      check(rd == 32'h0000_1888, "Port C writes mstatus key fields");
    end

    // CSR-S13: mip readonly timer/ext reflect inputs
    begin
      logic [31:0] rd;
      timer_intr = 1'b1;
      ext_intr   = 1'b1;
      msft_intr  = 1'b0;
      @(posedge clk);
      read_csr(MIP_ADDR, rd);
      check(rd[7] == 1'b1, "MIP.MTIP tracks timer_intr_i");
      check(rd[11] == 1'b1, "MIP.MEIP tracks ext_intr_i");

      // attempt to write mip[7]/[11] via normal port should not affect
      write_normal(MIP_ADDR, 32'hFFFF_FFFF);
      read_csr(MIP_ADDR, rd);
      check(rd[7] == 1'b1, "MIP.MTIP remains readonly");
      check(rd[11] == 1'b1, "MIP.MEIP remains readonly");
    end

    $display("=== Results: %0d pass, %0d fail ===", pass, fail);
    if (fail != 0) $fatal(1);
    $finish;
  end

endmodule
