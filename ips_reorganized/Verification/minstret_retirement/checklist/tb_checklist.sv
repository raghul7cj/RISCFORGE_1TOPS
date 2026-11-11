`timescale 1ns/1ps
// Real core execution: no hierarchical force, no artificial WB packet stimulus.
// Reference PCs come from a small software executor of the assembled images.
module tb_checklist;
  reg clk=0,rst=0,timer_irq=0;
  always #5 clk=~clk;
  wire en,we,req,dwe;
  wire [3:0] wm,be;
  wire [29:0] ia;
  wire [31:0] iw,da,dw;
  reg [31:0] instructions[0:1023],data[0:1023];
  reg [31:0] expected_pc[0:511],handler_pc[0:31];
  integer iq=0,waits=0,cycles=0,wait_limit=0;
  integer reference_count,index=0,handler_count=0,irq_mode=0,irq_sent=0;
  integer i,b,j,trace_fd;
  reg [31:0] done_pc,trigger_pc,irq_end,expected_memory0,expected_memory1;
  reg [31:0] wb_pc,word;
  reg [63:0] before_count;
  integer delta;
  reg consumed,finished;
  string image,reference,handler_file,trace_file;
  wire stall=req && waits<wait_limit;
  top #(.RESET_PC(32'h80000000)) dut(
    .clk(clk),.rst(rst),.PCSrcE1(),.imem_sram_en(en),.imem_sram_we(we),
    .imem_sram_wmask(wm),.imem_sram_addr(ia),.imem_sram_wdata(iw),
    .imem_sram_rdata(instructions[iq]),.lsu_mem_req(req),.lsu_mem_we(dwe),
    .lsu_mem_addr(da),.lsu_mem_wdata(dw),.lsu_mem_be(be),
    .lsu_mem_rdata(data[da[11:2]]),.lsu_mem_stall(stall),.lsu_mem_err(1'b0),
    .fast_irq_i(16'b0),.timer_irq_i(timer_irq),.ext_irq_i(1'b0),.sw_irq_i(1'b0));

  initial begin
    for(i=0;i<1024;i=i+1) begin instructions[i]=32'h13;data[i]=0;end
    if(!$value$plusargs("HEX=%s",image)) $fatal(1,"HEX required");
    if(!$value$plusargs("REFERENCE=%s",reference)) $fatal(1,"REFERENCE required");
    if(!$value$plusargs("COUNT=%d",reference_count)) $fatal(1,"COUNT required");
    if(!$value$plusargs("DONE=%h",done_pc)) $fatal(1,"DONE required");
    if(!$value$plusargs("TRACE=%s",trace_file)) $fatal(1,"TRACE required");
    if(!$value$plusargs("MEM0=%h",expected_memory0)) $fatal(1,"MEM0 required");
    if(!$value$plusargs("MEM1=%h",expected_memory1)) $fatal(1,"MEM1 required");
    if($value$plusargs("WAIT=%d",wait_limit)) begin end
    if($value$plusargs("IRQ=%d",irq_mode)) begin end
    $readmemh(image,instructions);
    $readmemh(reference,expected_pc,0,reference_count-1);
    if(irq_mode) begin
      if(!$value$plusargs("HANDLER=%s",handler_file)) $fatal(1,"HANDLER required");
      if(!$value$plusargs("HANDLER_COUNT=%d",handler_count)) $fatal(1,"HANDLER_COUNT required");
      if(!$value$plusargs("TRIGGER=%h",trigger_pc)) $fatal(1,"TRIGGER required");
      if(!$value$plusargs("IRQ_END=%h",irq_end)) $fatal(1,"IRQ_END required");
      $readmemh(handler_file,handler_pc,0,handler_count-1);
    end
    trace_fd=$fopen(trace_file,"w");
    if(!trace_fd) $fatal(1,"cannot create trace");
    $fdisplay(trace_fd,"cycle,pc,instruction,delta,event,cause,counter");
    repeat(5) @(negedge clk);
    rst=1;
  end

  // Pulse the actual timer interrupt pin once in the unique-PC NOP window.
  always @(negedge clk) if(rst && irq_mode) begin
    if(!irq_sent && dut.valid_E && dut.PCE>=trigger_pc && dut.PCE<irq_end) begin
      timer_irq=1;
      irq_sent=1;
    end else timer_irq=0;
  end

  always @(posedge clk) begin
    if(!rst) begin iq<=0;waits<=0;end
    else begin
      cycles<=cycles+1;
      if(cycles>6000) $fatal(1,"TIMEOUT pc=%h",dut.Fetch.PCF);
      if(en) iq <= (ia>=30'h20000000 && ia<30'h20000400) ? ia-30'h20000000 : 0;
      if(req) begin
        if(waits<wait_limit) waits<=waits+1;
        else waits<=0;
      end else waits<=0;
      if(req && dwe && !stall)
        for(b=0;b<4;b=b+1) if(be[b]) data[da[11:2]][8*b+:8]<=dw[8*b+:8];
    end
  end

  // Check EVERY edge, including bubbles, holds, exceptions and redirects.
  // Final counter must also equal the independent dynamic instruction path.
  always @(posedge clk) if(rst) begin
    if(dut.FlushD && dut.valid_D && dut.InstrD==32'hffffffff)
      $display("SQUASH pc=%08x",dut.PCD);
    before_count=dut.csr_file.minstret_r;
    wb_pc=dut.PC_W;
    word=(wb_pc>=32'h80000000 && wb_pc<32'h80001000) ?
         instructions[(wb_pc-32'h80000000)>>2] : 0;
    if(dut.trap_commit_valid && dut.trap_commit_is_interrupt) begin
      if(!irq_mode || dut.trap_commit_cause!=7 || dut.trap_commit_pc< trigger_pc || dut.trap_commit_pc>=irq_end)
        $fatal(1,"unexpected IRQ cause/PC");
      if(expected_pc[index]!==dut.trap_commit_pc)
        $fatal(1,"IRQ precise boundary mismatch index=%0d expected=%h trap=%h",index,expected_pc[index],dut.trap_commit_pc);
      // Interrupt is an external event at the reported precise boundary.
      // Insert only the statically assembled handler, then replay the interrupted
      // instruction. No trace/count is copied from the DUT's retirement signal.
      for(j=reference_count-1;j>=index;j=j-1) expected_pc[j+handler_count]=expected_pc[j];
      for(j=0;j<handler_count;j=j+1) expected_pc[index+j]=handler_pc[j];
      reference_count=reference_count+handler_count;
    end
    consumed=dut.valid_W && !dut.exc_valid_W &&
             (dut.mret_commit || (!dut.mem_stall_out && !dut.FlushW));
    finished=consumed && wb_pc==done_pc;
    if(consumed) begin
      if(index>=reference_count || wb_pc!==expected_pc[index])
        $fatal(1,"path mismatch at %0d pc=%h expected=%h",index,wb_pc,expected_pc[index]);
      index=index+1;
      $fwrite(trace_fd,"%0d,%08x,%08x,1,retired,0,",cycles,wb_pc,word);
    end else if(dut.trap_commit_valid)
      $fwrite(trace_fd,"%0d,%08x,%08x,0,%s,%0d,",cycles,wb_pc,word,
              dut.trap_commit_is_interrupt ? "interrupt" : "exception",dut.trap_commit_cause);
    else if(!dut.valid_W)
      $fwrite(trace_fd,"%0d,%08x,%08x,0,bubble,0,",cycles,wb_pc,word);
    else if(dut.mem_stall_out)
      $fwrite(trace_fd,"%0d,%08x,%08x,0,held,0,",cycles,wb_pc,word);
    else $fwrite(trace_fd,"%0d,%08x,%08x,0,flushed,0,",cycles,wb_pc,word);
    delta=consumed ? 1 : 0;
    #1;
    $fdisplay(trace_fd,"%0d",dut.csr_file.minstret_r);
    if(dut.csr_file.minstret_r!==before_count+delta)
      $fatal(1,"counter delta mismatch pc=%h expected=%0d before=%0d after=%0d",wb_pc,delta,before_count,dut.csr_file.minstret_r);
    if(finished) begin
      if(index!=reference_count || dut.csr_file.minstret_r!==reference_count)
        $fatal(1,"final count/path mismatch expected=%0d actual=%0d index=%0d",reference_count,dut.csr_file.minstret_r,index);
      if(irq_mode && (!irq_sent || reference_count<=handler_count)) $fatal(1,"IRQ not stimulated");
      if(data[0]!==expected_memory0 || data[1]!==expected_memory1)
        $fatal(1,"completed memory mismatch actual=%h/%h expected=%h/%h",data[0],data[1],expected_memory0,expected_memory1);
      $display("PASS retired=%0d counter=%0d cycles=%0d wait=%0d irq=%0d",reference_count,dut.csr_file.minstret_r,cycles,wait_limit,irq_mode);
      $fclose(trace_fd);
      $finish;
    end
  end
endmodule
