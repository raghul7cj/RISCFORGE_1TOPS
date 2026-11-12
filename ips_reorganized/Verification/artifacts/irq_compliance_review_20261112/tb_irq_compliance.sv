`timescale 1ns/1ps
// Review reproducer: real blocks wired with top.v's 13-source contract.
// Not an instruction-pipeline test. Expected results follow privileged ISA 1.13.
module tb_irq_compliance;
  reg clk=0, rst=0;
  always #5 clk=~clk;
  reg [11:0] raddr=0,waddr=0;
  reg [31:0] wdata=0;
  reg wen=0, ext=0, sw=0, timer=0;
  reg [12:0] clear=0;
  wire [12:0] pending;
  wire [31:0] rd,mip,mie,status;
  wire [1:0] threshold;
  wire offered;
  wire [4:0] id;
  integer failures=0;
  irq_gateway gw(.clk_i(clk),.rst_ni(rst),.irq_raw_i({12'b0,timer}),
    .edge_mode_i(13'h0002),.event_mode_i(13'h1fe9),.clear_i(clear),.pend_o(pending));
  csr_regfile csr(.clk_i(clk),.rst_n_i(rst),.csr_raddr_i(raddr),.csr_rdata_o(rd),
    .csr_waddr_normal_i(waddr),.csr_wdata_normal_i(wdata),.csr_write_en_normal_i(wen),
    .csr_waddr_mret_i(12'b0),.csr_wdata_mret_i(32'b0),.csr_write_en_mret_i(1'b0),
    .mret_commit_i(1'b0),.trap_valid_i(1'b0),.trap_cause_i(31'b0),.trap_pc_i(32'b0),
    .trap_addr_i(32'b0),.trap_addr_valid_i(1'b0),.trap_is_interrupt_i(1'b0),
    .instr_retired_i(1'b0),.timer_intr_i(pending[0]),.ext_intr_i(ext),.msft_intr_i(sw),
    .fast_intr_i({4'b0,pending[12:1]}),.mip_out_o(mip),.mie_out_o(mie),
    .mintprio_out_o(threshold),.mstatus_out_o(status));
  irq_arbiter arb(.clk_i(clk),.rst_ni(rst),.pend_i(pending),.mie_i(mie),
    .mstatus_mie_i(status[3]),.mintprio_i(threshold),.wb_commit_i(1'b0),
    .wb_trap_cause_i(5'b0),.irq_pending_o(offered),.irq_id_o(id),.irq_class_o());
  task write_csr(input [11:0] addr,input [31:0] value);
    @(negedge clk);waddr=addr;wdata=value;wen=1;
    @(negedge clk);wen=0;#1;
  endtask
  task check(input condition,input [8*100-1:0] label);
    if(condition) $display("[PASS] %0s",label);
    else begin failures=failures+1;$display("[FAIL] %0s",label);end
  endtask
  initial begin
    #1;rst=0;repeat(2) @(negedge clk);rst=1;
    write_csr(12'h300,32'h1808);
    write_csr(12'h304,32'h888);
    write_csr(12'h344,32'h8);
    $display("[OBSERVE] software write mip: mip=%08x mie=%08x mstatus=%08x irq=%b id=%0d",mip,mie,status,offered,id);
    check(mip[3]===1'b0,"MSIP must be read-only through mip CSR (write 1 must not assert it)");
    check(offered===1'b1 && id===5'd3,"Advertised enabled MSIP must reach arbitration");
    write_csr(12'h344,0);
    sw=1;#1;
    $display("[OBSERVE] software pin: mip=%08x irq=%b id=%0d",mip,offered,id);
    check(mip[3]===1'b1 && offered===1'b1 && id===5'd3,"Enabled software interrupt pin must reach arbitration");
    sw=0;ext=1;#1;
    $display("[OBSERVE] external pin: mip=%08x irq=%b id=%0d",mip,offered,id);
    check(mip[11]===1'b1 && offered===1'b1 && id===5'd11,"Enabled MEIP must reach arbitration");
    ext=0;timer=1;@(negedge clk);timer=0;#1;
    check(mip[7] && offered && id==7,"Baseline timer offer with mintprio=0");
    write_csr(12'h7c0,3);
    $display("[OBSERVE] standard MTI at threshold 3: mip=%08x mie=%08x mstatus=%08x irq=%b",mip,mie,status,offered);
    check(offered===1'b1 && id===5'd7,"Standard MTI remains eligible with MIE and MTIE set");
    write_csr(12'h300,32'h0000000a);
    $display("[OBSERVE] M-only mstatus write: mstatus=%08x MPP=%b SIE=%b",status,status[12:11],status[1]);
    check(status[12:11]===2'b11,"M-only MPP must remain the only supported mode (M)");
    check(status[1]===1'b0,"No S-mode: SIE must be read-only zero");
    $display("[SUMMARY] standards_checks_failed=%0d (intentional negative evidence)",failures);
    if(failures) $fatal(1,"Compliance review found contract mismatches; preserve log");
    $finish;
  end
endmodule
