interface trace_if (input logic clk);
  logic        rst_n;
  logic        wb_en;
  logic [4:0]  wb_rd;
  logic [31:0] wb_data;
  logic [31:0] wb_pc;
  logic        mem_req;
  logic        mem_we;
  logic [31:0] mem_addr;
  logic [31:0] mem_wdata;
endinterface
