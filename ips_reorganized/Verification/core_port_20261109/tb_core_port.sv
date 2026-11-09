`timescale 1ns/1ps
module tb_core_port;
  reg clk=0, rst=0;
  always #5 clk=~clk;
  wire en,we; wire [3:0] wm; wire [29:0] ia; wire [31:0] iw;
  wire req,dwe; wire [31:0] da,dw; wire [3:0] be;
  reg [31:0] instructions[0:1023]; reg [31:0] data[0:1023];
  integer iq=0, waits=0, cycles=0, writes=0, reads=0, trap_count=0;
  integer wait_limit=3;
  wire [31:0] dr = data[da[11:2]];
  wire stall = req && !dwe && waits < wait_limit;
  top #(.RESET_PC(32'h80000000)
`ifdef CANDIDATE
    , .FETCH_CHECK_ENABLE(1'b1), .FETCH_BASE0(32'h80000000),
    .FETCH_END0(32'h80001000), .FETCH_BASE1(0), .FETCH_END1(0)
`endif
  ) dut(.clk(clk),.rst(rst),.PCSrcE1(),.imem_sram_en(en),
    .imem_sram_we(we),.imem_sram_wmask(wm),.imem_sram_addr(ia),
    .imem_sram_wdata(iw),.imem_sram_rdata(instructions[iq]),
    .lsu_mem_req(req),.lsu_mem_we(dwe),.lsu_mem_addr(da),.lsu_mem_wdata(dw),
    .lsu_mem_be(be),.lsu_mem_rdata(dr),.lsu_mem_stall(stall),.lsu_mem_err(1'b0),
    .fast_irq_i(16'b0),.timer_irq_i(1'b0),.ext_irq_i(1'b0),.sw_irq_i(1'b0));
  string hexfile;
  integer i,b;
  initial begin
    for(i=0;i<1024;i=i+1) begin instructions[i]=32'h00000013; data[i]=0; end
    if(!$value$plusargs("HEX=%s",hexfile)) $fatal(1,"missing HEX");
    if($value$plusargs("WAIT=%d",wait_limit)) begin end
    $readmemh(hexfile,instructions);
    repeat(5) @(negedge clk);
    rst=1;
  end
  always @(posedge clk) begin
    if(!rst) begin iq<=0; waits<=0; end
    else begin
      cycles<=cycles+1;
      if(cycles>3000) $fatal(1,"TIMEOUT pc=%h traps=%0d",dut.Fetch.PCF,trap_count);
      if(en) iq <= (ia >= 30'h20000000 && ia < 30'h20000400) ? ia-30'h20000000 : 0;
      if(dut.trap_commit_valid) begin
        trap_count<=trap_count+1;
        $display("TRAP cause=%h pc=%h tval=%h",dut.exc_cause_W,dut.exc_pc_W,dut.exc_tval_W);
      end
      if(req && !dwe) begin
        if(waits < wait_limit) waits<=waits+1;
        else begin waits<=0; reads<=reads+1; end
      end else waits<=0;
      if(req && dwe) begin
        writes<=writes+1;
        if(da==32'h80001100) begin
          if(dw!==32'd1) $fatal(1,"FIRMWARE FAIL code=%h cycles=%0d",dw,cycles);
          $display("PASS cycles=%0d reads=%0d writes=%0d traps=%0d",cycles,reads,writes,trap_count);
          $finish;
        end
        for(b=0;b<4;b=b+1) if(be[b]) data[da[11:2]][8*b+:8]<=dw[8*b+:8];
      end
    end
  end
endmodule
