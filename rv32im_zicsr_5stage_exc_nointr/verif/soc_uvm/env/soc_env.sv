class soc_env extends uvm_env;
  `uvm_component_utils(soc_env)

  uart_agent     uart;
  trace_monitor  trace;
  soc_scoreboard scb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    uart  = uart_agent::type_id::create("uart", this);
    trace = trace_monitor::type_id::create("trace", this);
    scb   = soc_scoreboard::type_id::create("scb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    uart.mon.ap.connect(scb.uart_imp);
    trace.ap.connect(scb.commit_imp);
  endfunction
endclass
