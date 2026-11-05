package soc_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "env/soc_cfg.sv"
  `include "agents/uart_agent.sv"
  `include "env/trace_monitor.sv"
  `include "env/soc_scoreboard.sv"
  `include "env/soc_env.sv"
  `include "seq/uart_send_seq.sv"
  `include "tests/soc_base_test.sv"
  `include "tests/soc_tests.sv"
endpackage
