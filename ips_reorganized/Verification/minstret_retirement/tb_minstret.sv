`timescale 1ns/1ps
// Execute a fixed assembly path with a variable-latency data memory. The
// architectural reference is an explicit list of executed instruction PCs,
// not the DUT's retirement pulse or a sum of WB-valid cycles.
module tb_minstret;
  reg clk=0, rst=0;
  always #5 clk=~clk;
  wire en, we;
  wire [3:0] wm, be;
  wire [29:0] ia;
  wire [31:0] iw, da, dw;
  wire req, dwe;
  reg [31:0] instructions[0:1023];
  reg [31:0] data[0:1023];
  reg [31:0] expected_pc[0:127];
  integer iq=0, waits=0, cycles=0, wait_limit=0;
  integer expected_count, index=0, holds=0, traps=0, returns=0;
  integer i,b;
  reg [31:0] done_pc;
  reg [63:0] before_count;
  string hexfile, reference;
  wire stall = req && !dwe && waits < wait_limit;
  top #(.RESET_PC(32'h80000000)) dut(
    .clk(clk), .rst(rst), .PCSrcE1(), .imem_sram_en(en),
    .imem_sram_we(we), .imem_sram_wmask(wm), .imem_sram_addr(ia),
    .imem_sram_wdata(iw), .imem_sram_rdata(instructions[iq]),
    .lsu_mem_req(req), .lsu_mem_we(dwe), .lsu_mem_addr(da),
    .lsu_mem_wdata(dw), .lsu_mem_be(be), .lsu_mem_rdata(data[da[11:2]]),
    .lsu_mem_stall(stall), .lsu_mem_err(1'b0),
    .fast_irq_i(16'b0), .timer_irq_i(1'b0), .ext_irq_i(1'b0), .sw_irq_i(1'b0));

  initial begin
    for(i=0;i<1024;i=i+1) begin instructions[i]=32'h00000013; data[i]=0; end
    if(!$value$plusargs("HEX=%s",hexfile)) $fatal(1,"missing HEX");
    if(!$value$plusargs("REFERENCE=%s",reference)) $fatal(1,"missing REFERENCE");
    if(!$value$plusargs("COUNT=%d",expected_count)) $fatal(1,"missing COUNT");
    if(!$value$plusargs("DONE=%h",done_pc)) $fatal(1,"missing DONE");
    if($value$plusargs("WAIT=%d",wait_limit)) begin end
    $readmemh(hexfile,instructions);
    $readmemh(reference,expected_pc,0,expected_count-1);
    repeat(5) @(negedge clk);
    rst=1;
  end

  always @(posedge clk) begin
    if(!rst) begin iq<=0; waits<=0; end
    else begin
      cycles<=cycles+1;
      if(cycles>3000) $fatal(1,"TIMEOUT pc=%h",dut.Fetch.PCF);
      if(en) iq <= (ia >= 30'h20000000 && ia < 30'h20000400) ? ia-30'h20000000 : 0;
      if(req && !dwe) begin
        if(waits < wait_limit) waits<=waits+1;
        else waits<=0;
      end else waits<=0;
      if(req && dwe)
        for(b=0;b<4;b=b+1) if(be[b]) data[da[11:2]][8*b+:8]<=dw[8*b+:8];
    end
  end

  always @(posedge clk) if(rst) begin
    before_count=dut.csr_file.minstret_r;
    if(dut.trap_commit_valid) begin
      traps=traps+1;
      if(dut.trap_commit_cause !== 31'd11) $fatal(1,"unexpected trap");
    end
    if(dut.mret_commit) returns=returns+1;

    if(dut.valid_W && !dut.exc_valid_W &&
       (dut.mret_commit || (!dut.mem_stall_out && !dut.FlushW))) begin
      if(index>=expected_count || dut.PC_W !== expected_pc[index])
        $fatal(1,"unexpected instruction index=%0d pc=%h expected=%h",index,dut.PC_W,expected_pc[index]);
      index=index+1;
    end

    if(dut.valid_W && !dut.exc_valid_W && dut.mem_stall_out && !dut.mret_commit) begin
      holds=holds+1;
      #1;
      if(dut.csr_file.minstret_r !== before_count)
        $fatal(1,"held WB incremented minstret pc=%h before=%0d after=%0d",dut.PC_W,before_count,dut.csr_file.minstret_r);
    end else if(dut.valid_W && dut.PC_W==done_pc) begin
      #1;
      if(index!=expected_count || dut.csr_file.minstret_r !== expected_count)
        $fatal(1,"retirement total expected=%0d actual=%0d path=%0d",expected_count,dut.csr_file.minstret_r,index);
      if(traps!=1 || returns!=1 || (wait_limit>0 && holds==0))
        $fatal(1,"missing coverage traps=%0d returns=%0d holds=%0d",traps,returns,holds);
      $display("PASS expected_retired=%0d actual=%0d held_edges=%0d traps=%0d mret=%0d wait=%0d",
               expected_count,dut.csr_file.minstret_r,holds,traps,returns,wait_limit);
      $finish;
    end
  end
endmodule
