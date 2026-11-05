class soc_cfg extends uvm_object;
  `uvm_object_utils(soc_cfg)

  int unsigned uart_bit_clks = 16;
  bit [31:0]   tohost_addr   = 32'h0001_0FFC;
  int unsigned timeout_clks  = 200_000;
  string       uart_expect   = "";
  uvm_event    done_ev;

  function new(string name = "soc_cfg");
    super.new(name);
    done_ev = new("done_ev");
  endfunction

  function void read_plusargs();
    void'($value$plusargs("UART_BIT_CLKS=%d", uart_bit_clks));
    void'($value$plusargs("TIMEOUT=%d", timeout_clks));
    void'($value$plusargs("UART_EXPECT=%s", uart_expect));
  endfunction
endclass
