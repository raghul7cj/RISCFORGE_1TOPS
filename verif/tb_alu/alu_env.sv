// alu_env.sv
class alu_env;
  virtual alu_if vif;
  mailbox #(alu_transaction) drv_mbx;
  mailbox #(alu_transaction) mon_to_sb;
  mailbox #(alu_transaction) mon_to_cov;

  alu_driver     driver;
  alu_monitor    monitor;
  alu_scoreboard scoreboard;
  alu_coverage   coverage;

  function new(virtual alu_if vif);
    this.vif = vif;
    drv_mbx = new();
    mon_to_sb = new();
    mon_to_cov = new();

    driver     = new(vif, drv_mbx);
    monitor    = new(vif, mon_to_sb, mon_to_cov);
    scoreboard = new(mon_to_sb);
    coverage   = new(mon_to_cov);
  endfunction

  task run();
    fork
      driver.run();
      monitor.run();
      scoreboard.run();
      coverage.run();
    join_none
  endtask
endclass: alu_env
