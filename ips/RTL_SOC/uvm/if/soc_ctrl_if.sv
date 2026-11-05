interface soc_ctrl_if (input logic clk);
  logic        hard_rst_n;
  logic        soft_rst_n;
  logic        test_mode;
  logic        fetch_en;
  logic [31:0] boot_addr;
  logic        boot_done;
  logic        core_rst_n;
endinterface
