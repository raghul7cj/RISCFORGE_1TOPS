`uvm_analysis_imp_decl(_uart)
`uvm_analysis_imp_decl(_commit)
`uvm_analysis_imp_decl(_gpio)
`uvm_analysis_imp_decl(_spi)
`uvm_analysis_imp_decl(_i2c)
`uvm_analysis_imp_decl(_irq)

class soc_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(soc_scoreboard)

  uvm_analysis_imp_uart   #(uart_item,   soc_scoreboard) uart_imp;
  uvm_analysis_imp_commit #(commit_item, soc_scoreboard) commit_imp;
  uvm_analysis_imp_gpio   #(gpio_item,   soc_scoreboard) gpio_imp;
  uvm_analysis_imp_spi    #(spi_item,    soc_scoreboard) spi_imp;
  uvm_analysis_imp_i2c    #(i2c_item,    soc_scoreboard) i2c_imp;
  uvm_analysis_imp_irq    #(irq_item,    soc_scoreboard) irq_imp;

  soc_cfg      cfg;
  string       uart_text;
  int unsigned commits;
  bit          done;
  bit [31:0]   result;
  bit          gpio_ok;
  spi_item     spi_frames[$];
  bit [7:0]    i2c_writes[$];
  bit [12:0]   irq_seen;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    uart_imp   = new("uart_imp", this);
    commit_imp = new("commit_imp", this);
    gpio_imp   = new("gpio_imp", this);
    spi_imp    = new("spi_imp", this);
    i2c_imp    = new("i2c_imp", this);
    irq_imp    = new("irq_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(soc_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "soc_cfg not set")
  endfunction

  function void write_uart(uart_item item);
    uart_text = {uart_text, string'(item.data)};
    if (item.par_err)
      `uvm_error("SCB", $sformatf("uart tx parity error on 0x%02h", item.data))
    if (item.frame_err)
      `uvm_error("SCB", $sformatf("uart tx stop bit missing on 0x%02h", item.data))
    if (item.stop2_err)
      `uvm_error("SCB", $sformatf("uart tx second stop bit missing on 0x%02h", item.data))
  endfunction

  function void write_commit(commit_item item);
    if (item.trap) return;
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

  function void write_gpio(gpio_item item);
    if ((item.value & item.tx_en) == cfg.gpio_expect && item.tx_en != 0)
      gpio_ok = 1'b1;
  endfunction

  function void write_spi(spi_item item);
    spi_frames.push_back(item);
  endfunction

  function void write_i2c(i2c_item item);
    if (!item.rw) i2c_writes.push_back(item.data);
  endfunction

  function void write_irq(irq_item item);
    irq_seen |= item.rise;
  endfunction

  function void check_phase(uvm_phase phase);
    if (!done)
      `uvm_error("SCB", "program did not finish")
    else if (result != 1)
      `uvm_error("SCB", $sformatf("program failed, code %0d", result >> 1))

    if (cfg.uart_expect != "" && uart_text != cfg.uart_expect)
      `uvm_error("SCB", $sformatf("uart got \"%s\" expected \"%s\"", uart_text, cfg.uart_expect))

    if (cfg.check_gpio && !gpio_ok)
      `uvm_error("SCB", $sformatf("gpio out 0x%08h never seen", cfg.gpio_expect))

    if (cfg.check_spi) begin
      if (spi_frames.size() == 0)
        `uvm_error("SCB", "no spi frame seen")
      else if (spi_frames[0].bits != 32 || spi_frames[0].data != cfg.spi_expect)
        `uvm_error("SCB", $sformatf("spi got 0x%08h (%0d bits) expected 0x%08h",
                   spi_frames[0].data, spi_frames[0].bits, cfg.spi_expect))
    end

    if (cfg.check_i2c && !(cfg.i2c_expect inside {i2c_writes}))
      `uvm_error("SCB", $sformatf("i2c write 0x%02h never seen", cfg.i2c_expect))

    if ((irq_seen & cfg.irq_expect) != cfg.irq_expect)
      `uvm_error("SCB", $sformatf("irq seen 0x%04h expected 0x%04h", irq_seen, cfg.irq_expect))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB", $sformatf("commits=%0d uart=\"%s\" spi_frames=%0d i2c_writes=%0d irq=0x%04h",
              commits, uart_text, spi_frames.size(), i2c_writes.size(), irq_seen), UVM_LOW)
  endfunction
endclass
