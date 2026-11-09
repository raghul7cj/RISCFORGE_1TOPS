interface reg_bus_if (input logic clk);
  logic        rst_n;
  logic [5:0]  psel;
  logic [5:0]  penable;
  logic [5:0]  pwrite;
  logic [5:0]  pready;
  logic [11:0] paddr  [6];
  logic [31:0] pwdata [6];
  logic [31:0] prdata [6];
endinterface
