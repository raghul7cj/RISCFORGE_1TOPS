package soc_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "env/soc_cfg.sv"
  `include "agents/uart_agent.sv"
  `include "agents/gpio_agent.sv"
  `include "agents/spi_agent.sv"
  `include "agents/i2c_agent.sv"
  `include "env/irq_monitor.sv"
  `include "env/trace_monitor.sv"
  `include "env/soc_scoreboard.sv"
  `include "env/soc_coverage.sv"
  `include "env/soc_env.sv"
  `include "seq/soc_seqs.sv"
  `include "tests/soc_base_test.sv"
  `include "tests/soc_tests.sv"
endpackage
