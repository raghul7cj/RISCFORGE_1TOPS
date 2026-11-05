class soc_base_test extends uvm_test;
  `uvm_component_utils(soc_base_test)

  soc_env                 env;
  soc_cfg                 cfg;
  virtual soc_ctrl_if     ctrl;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    cfg = soc_cfg::type_id::create("cfg");
    cfg.read_plusargs();
    set_cfg();
    uvm_config_db #(soc_cfg)::set(this, "*", "cfg", cfg);
    if (!uvm_config_db #(virtual soc_ctrl_if)::get(this, "", "ctrl", ctrl))
      `uvm_fatal("NOVIF", "soc_ctrl_if not set")
    env = soc_env::type_id::create("env", this);
  endfunction

  virtual function void set_cfg();
  endfunction

  virtual task main_stim();
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    reset_dut();
    fork
      main_stim();
    join_none
    fork
      cfg.done_ev.wait_trigger();
      begin
        repeat (cfg.timeout_clks) @(posedge ctrl.clk);
        `uvm_error("TIMEOUT", "test timed out")
      end
    join_any
    disable fork;
    repeat (cfg.uart_bit_clks * 20) @(posedge ctrl.clk);
    phase.drop_objection(this);
  endtask

  task reset_dut();
    ctrl.hard_rst_n <= 1'b0;
    ctrl.soft_rst_n <= 1'b1;
    ctrl.test_mode  <= 1'b0;
    ctrl.fetch_en   <= 1'b1;
    ctrl.boot_addr  <= 32'h0;
    repeat (20) @(posedge ctrl.clk);
    ctrl.hard_rst_n <= 1'b1;
    `uvm_info("TEST", "reset released", UVM_LOW)
  endtask
endclass
