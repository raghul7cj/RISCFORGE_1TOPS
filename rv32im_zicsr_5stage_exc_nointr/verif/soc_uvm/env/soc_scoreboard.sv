`uvm_analysis_imp_decl(_uart)
`uvm_analysis_imp_decl(_commit)

class soc_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(soc_scoreboard)

  uvm_analysis_imp_uart   #(uart_item,   soc_scoreboard) uart_imp;
  uvm_analysis_imp_commit #(commit_item, soc_scoreboard) commit_imp;

  soc_cfg      cfg;
  string       uart_text;
  int unsigned commits;
  bit          done;
  bit [31:0]   result;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    uart_imp   = new("uart_imp", this);
    commit_imp = new("commit_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(soc_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "soc_cfg not set")
  endfunction

  function void write_uart(uart_item item);
    uart_text = {uart_text, string'(item.data)};
  endfunction

  function void write_commit(commit_item item);
    if (!item.tohost) begin
      commits++;
      return;
    end
    if (done) return;
    done   = 1'b1;
    result = item.data;
    `uvm_info("SCB", $sformatf("tohost = 0x%08h", result), UVM_LOW)
    cfg.done_ev.trigger();
  endfunction

  function void check_phase(uvm_phase phase);
    if (!done)
      `uvm_error("SCB", "program did not finish")
    else if (result != 1)
      `uvm_error("SCB", $sformatf("program failed, code %0d", result >> 1))
    if (cfg.uart_expect != "" && uart_text != cfg.uart_expect)
      `uvm_error("SCB", $sformatf("uart got \"%s\" expected \"%s\"", uart_text, cfg.uart_expect))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB", $sformatf("commits = %0d, uart = \"%s\"", commits, uart_text), UVM_LOW)
  endfunction
endclass
