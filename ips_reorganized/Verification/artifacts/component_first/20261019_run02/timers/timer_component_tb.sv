`timescale 1ns/1ps
module timer_component_tb;
 logic HCLK=0, HRESETn=0;
 logic [11:0] PADDR=0; logic [31:0] PWDATA=0;
 logic PWRITE=0, PENABLE=0; logic [1:0] PSEL=0;
 logic [31:0] PRDATA0,PRDATA1; logic PREADY0,PREADY1,PSLVERR0,PSLVERR1;
 logic [3:0] irq0,irq1;
 int pass_cnt=0,fail_cnt=0;
 always #5 HCLK=~HCLK;
 apb_timer #(.APB_ADDR_WIDTH(12),.TIMER_CNT(2)) timer0(.HCLK,.HRESETn,.PADDR,.PWDATA,.PWRITE,.PSEL(PSEL[0]),.PENABLE,.PRDATA(PRDATA0),.PREADY(PREADY0),.PSLVERR(PSLVERR0),.irq_o(irq0));
 apb_timer #(.APB_ADDR_WIDTH(12),.TIMER_CNT(2)) timer1(.HCLK,.HRESETn,.PADDR,.PWDATA,.PWRITE,.PSEL(PSEL[1]),.PENABLE,.PRDATA(PRDATA1),.PREADY(PREADY1),.PSLVERR(PSLVERR1),.irq_o(irq1));
 task automatic check(input string label, input logic cond); if(cond===1'b1) begin $display("[PASS] %s",label); pass_cnt++; end else begin $display("[FAIL] %s",label); fail_cnt++; end endtask
 task automatic apb_write(input int which,input logic [11:0] addr,input logic [31:0] data);
   @(negedge HCLK); PSEL=2'b01<<which; PADDR=addr; PWDATA=data; PWRITE=1; PENABLE=0;
   @(negedge HCLK); PENABLE=1;
   @(posedge HCLK); if (!(which?PREADY1:PREADY0)) begin $display("[FAIL] write not ready"); fail_cnt++; end
   @(negedge HCLK); PSEL=0; PENABLE=0; PWRITE=0;
 endtask
 task automatic apb_read(input int which,input logic [11:0] addr,output logic [31:0] data);
   @(negedge HCLK); PSEL=2'b01<<which; PADDR=addr; PWDATA=0; PWRITE=0; PENABLE=0;
   @(negedge HCLK); PENABLE=1; #1; data=which?PRDATA1:PRDATA0;
   @(posedge HCLK); if (!(which?PREADY1:PREADY0)) begin $display("[FAIL] read not ready"); fail_cnt++; end
   @(negedge HCLK); PSEL=0; PENABLE=0;
 endtask
 logic [31:0] rd,rd2; int t;
 initial begin
   repeat(4) @(posedge HCLK); @(negedge HCLK); HRESETn=1;
   apb_read(0,12'h000,rd); check("Timer0 channel 0 reset count is zero",rd==0);
   apb_read(1,12'h010,rd); check("Timer1 channel 1 reset count is zero",rd==0);
   apb_write(0,12'h004,32'h1); repeat(5) @(posedge HCLK); apb_read(0,12'h000,rd); check("Timer0 channel 0 counts when enabled",rd>0);
   apb_write(0,12'h004,32'h0); apb_read(0,12'h000,rd); repeat(3) @(posedge HCLK); apb_read(0,12'h000,rd2); check("Timer0 channel 0 stops when disabled",rd==rd2);
   apb_write(1,12'h014,32'h1); repeat(5) @(posedge HCLK); apb_read(1,12'h010,rd); check("Timer1 channel 1 counts independently",rd>0);
   apb_write(1,12'h014,32'h0);
   apb_write(0,12'h004,32'h0); apb_write(0,12'h000,32'h0); apb_write(0,12'h008,32'd3); apb_write(0,12'h004,32'h1);
   t=0; while(!irq0[1] && t<12) begin @(negedge HCLK); t++; end
   check("Timer0 compare IRQ occurs at programmed count",irq0[1]);
   apb_write(0,12'h004,32'h0);
   apb_write(0,12'h000,32'hffff_fffe); apb_write(0,12'h004,32'h1);
   t=0; while(!irq0[0] && t<6) begin @(negedge HCLK); t++; end
   check("Timer0 overflow IRQ occurs at 32-bit wrap",irq0[0]);
   apb_write(0,12'h004,32'h0);
   apb_read(0,12'h00c,rd); check("Invalid timer register reads zero",rd==0);
   check("Timer APB response is ready and no-error",PREADY0 && !PSLVERR0 && PREADY1 && !PSLVERR1);
   $display("TIMER_COMPONENT_RESULT pass=%0d fail=%0d",pass_cnt,fail_cnt);
   if(fail_cnt) $fatal(1,"timer component test failed");
   $finish;
 end
endmodule
