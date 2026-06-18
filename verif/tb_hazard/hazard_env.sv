// hazard_env.sv
class hazard_env;
  virtual hazard_if vif;
  mailbox #(hazard_transaction) drv_mbx;
  mailbox #(hazard_transaction) mon_mbx;

  hazard_driver     driver;
  hazard_monitor    monitor;
  hazard_scoreboard scoreboard;

  function new(virtual hazard_if vif);
    this.vif = vif;
    drv_mbx = new();
    mon_mbx = new();

    driver     = new(vif, drv_mbx);
    monitor    = new(vif, mon_mbx);
    scoreboard = new(mon_mbx);
  endfunction

  task run();
    fork
      driver.run();
      monitor.run();
      scoreboard.run();
    join_none
  endtask
endclass: hazard_env
