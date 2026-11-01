`timescale 1ns/1ps
module soc_gpio_aperture_tb;
  localparam int AW=32, DW=32, NS=6, NR=6, SW=$clog2(NS);
  typedef logic [AW-1:0] addr_t;
  typedef logic [DW-1:0] data_t;
  typedef logic [DW/8-1:0] strb_t;
  typedef struct packed {addr_t addr; axi_pkg::prot_t prot;} aw_chan_t;
  typedef struct packed {data_t data; strb_t strb;} w_chan_t;
  typedef struct packed {axi_pkg::resp_t resp;} b_chan_t;
  typedef struct packed {addr_t addr; axi_pkg::prot_t prot;} ar_chan_t;
  typedef struct packed {data_t data; axi_pkg::resp_t resp;} r_chan_t;
  typedef struct packed {aw_chan_t aw; logic aw_valid; w_chan_t w; logic w_valid; logic b_ready; ar_chan_t ar; logic ar_valid; logic r_ready;} axi_req_t;
  typedef struct packed {logic aw_ready; logic w_ready; b_chan_t b; logic b_valid; logic ar_ready; r_chan_t r; logic r_valid;} axi_resp_t;
  typedef struct packed {addr_t paddr; axi_pkg::prot_t pprot; logic psel; logic penable; logic pwrite; data_t pwdata; strb_t pstrb;} apb_req_t;
  typedef struct packed {logic pready; data_t prdata; logic pslverr;} apb_resp_t;
  typedef struct packed {logic [SW-1:0] idx; addr_t start_addr; addr_t end_addr;} rule_t;

  logic clk=0, rst_n;
  axi_req_t axi_req;
  axi_resp_t axi_resp;
  apb_req_t [NS-1:0] apb_req;
  apb_resp_t [NS-1:0] apb_resp;
  rule_t [NR-1:0] addr_map;
  logic [NS-1:0] selected_mask;
  int pass_cnt=0, fail_cnt=0;

  always #5 clk=~clk;
  assign addr_map[0]='{idx:3'd0,start_addr:32'h4000_0000,end_addr:32'h4000_1000};
  assign addr_map[1]='{idx:3'd1,start_addr:32'h4000_1000,end_addr:32'h4000_2000};
  assign addr_map[2]='{idx:3'd2,start_addr:32'h4000_2000,end_addr:32'h4000_3000};
  assign addr_map[3]='{idx:3'd3,start_addr:32'h4000_3000,end_addr:32'h4000_3800};
  assign addr_map[4]='{idx:3'd4,start_addr:32'h4000_4000,end_addr:32'h4000_5000};
  assign addr_map[5]='{idx:3'd5,start_addr:32'h4000_5000,end_addr:32'h4000_6000};

  for (genvar i=0;i<NS;i++) begin : gen_apb_response
    assign apb_resp[i].pready=apb_req[i].psel && apb_req[i].penable;
    assign apb_resp[i].prdata=32'h600D_0000+i;
    assign apb_resp[i].pslverr=1'b0;
  end
  always @(posedge clk) begin
    if (rst_n) for(int i=0;i<NS;i++) if(apb_req[i].psel) selected_mask[i]=1'b1;
  end

  axi_lite_to_apb #(.NoApbSlaves(NS),.NoRules(NR),.AddrWidth(AW),.DataWidth(DW),.axi_lite_req_t(axi_req_t),.axi_lite_resp_t(axi_resp_t),.apb_req_t(apb_req_t),.apb_resp_t(apb_resp_t),.rule_t(rule_t)) dut (
    .clk_i(clk),.rst_ni(rst_n),.axi_lite_req_i(axi_req),.axi_lite_resp_o(axi_resp),.apb_req_o(apb_req),.apb_resp_i(apb_resp),.addr_map_i(addr_map));

  task automatic check(input string label,input logic cond);
    if(cond) begin $display("[PASS] %s",label); pass_cnt++; end
    else begin $display("[FAIL] %s",label); fail_cnt++; end
  endtask
  task automatic axi_idle;
    axi_req='0; axi_req.b_ready=1; axi_req.r_ready=1;
  endtask
  task automatic read_check(input addr_t a,input logic [NS-1:0] exp_mask,input axi_pkg::resp_t exp_resp,input data_t exp_data,input string label);
    int t; data_t ignored;
    selected_mask='0; t=0;
    @(negedge clk); axi_req.ar.addr=a; axi_req.ar.prot='0; axi_req.ar_valid=1; axi_req.r_ready=0;
    do begin @(posedge clk); t++; if(t>100) $fatal(1,"AR timeout %h",a); end while(!axi_resp.ar_ready);
    @(negedge clk); axi_req.ar_valid=0;
    t=0; do begin @(posedge clk); t++; if(t>100) $fatal(1,"R timeout %h",a); end while(!axi_resp.r_valid);
    ignored=axi_resp.r.data;
    check({label," response"},axi_resp.r.resp===exp_resp);
    if(exp_resp==axi_pkg::RESP_OKAY) check({label," routed data"},ignored===exp_data);
    @(negedge clk); axi_req.r_ready=1;
    @(posedge clk); @(negedge clk); axi_req.r_ready=1;
    check({label," APB select mask"},selected_mask===exp_mask);
  endtask
  task automatic write_check(input addr_t a,input logic [NS-1:0] exp_mask,input axi_pkg::resp_t exp_resp,input string label);
    int t;
    selected_mask='0; t=0;
    @(negedge clk); axi_req.aw.addr=a; axi_req.aw.prot='0; axi_req.aw_valid=1; axi_req.w.data=32'h1234_ABCD; axi_req.w.strb=4'hF; axi_req.w_valid=1; axi_req.b_ready=0;
    do begin @(posedge clk); t++; if(t>100) $fatal(1,"AW/W timeout %h",a); end while(!(axi_resp.aw_ready&&axi_resp.w_ready));
    @(negedge clk); axi_req.aw_valid=0; axi_req.w_valid=0;
    t=0; do begin @(posedge clk); t++; if(t>100) $fatal(1,"B timeout %h",a); end while(!axi_resp.b_valid);
    check({label," response"},axi_resp.b.resp===exp_resp);
    @(negedge clk); axi_req.b_ready=1;
    @(posedge clk); @(negedge clk); axi_req.b_ready=1;
    check({label," APB select mask"},selected_mask===exp_mask);
  endtask

  initial begin
    axi_idle(); selected_mask='0; rst_n=1; #2; rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);
    read_check(32'h4000_0000,6'b000001,axi_pkg::RESP_OKAY,32'h600D_0000,"I2C slot read");
    read_check(32'h4000_1000,6'b000010,axi_pkg::RESP_OKAY,32'h600D_0001,"Timer0 slot read");
    read_check(32'h4000_2000,6'b000100,axi_pkg::RESP_OKAY,32'h600D_0002,"UART slot read");
    read_check(32'h4000_3000,6'b001000,axi_pkg::RESP_OKAY,32'h600D_0003,"GPIO slot base read");
    read_check(32'h4000_37FC,6'b001000,axi_pkg::RESP_OKAY,32'h600D_0003,"GPIO last aligned address 0x37FC");
    read_check(32'h4000_3800,6'b000000,axi_pkg::RESP_DECERR,32'h0,"GPIO first address outside 2KB aperture");
    read_check(32'h4000_3980,6'b000000,axi_pkg::RESP_DECERR,32'h0,"standalone alias case +0x980 is unmapped at SoC bridge");
    read_check(32'h4000_3FFC,6'b000000,axi_pkg::RESP_DECERR,32'h0,"end of unmapped 4KB gap");
    read_check(32'h4000_4000,6'b010000,axi_pkg::RESP_OKAY,32'h600D_0004,"SPI slot read");
    read_check(32'h4000_5000,6'b100000,axi_pkg::RESP_OKAY,32'h600D_0005,"Timer1 slot read");
    write_check(32'h4000_3800,6'b000000,axi_pkg::RESP_DECERR,"out-of-range GPIO write");
    write_check(32'h4000_3980,6'b000000,axi_pkg::RESP_DECERR,"standalone alias write case +0x980 is unmapped at SoC bridge");
    write_check(32'h4000_0000,6'b000001,axi_pkg::RESP_OKAY,"I2C slot write");
    write_check(32'h4000_1000,6'b000010,axi_pkg::RESP_OKAY,"Timer0 slot write");
    write_check(32'h4000_2000,6'b000100,axi_pkg::RESP_OKAY,"UART slot write");
    write_check(32'h4000_3000,6'b001000,axi_pkg::RESP_OKAY,"GPIO base write");
    write_check(32'h4000_4000,6'b010000,axi_pkg::RESP_OKAY,"SPI slot write");
    write_check(32'h4000_5000,6'b100000,axi_pkg::RESP_OKAY,"Timer1 slot write");
    $display("GPIO_APERTURE_SUMMARY pass=%0d fail=%0d",pass_cnt,fail_cnt);
    if(fail_cnt) $fatal(1,"GPIO aperture decode checks failed");
    $finish;
  end
endmodule

