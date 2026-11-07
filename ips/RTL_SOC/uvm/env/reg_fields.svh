function void add_fields();
  add("I2C.PRE.prescale",        0, 'h000,  0, 16, RW, ANY);
  add("I2C.CTRL.ien",            0, 'h004,  6,  1, RW, ANY);
  add("I2C.CTRL.en",             0, 'h004,  7,  1, RW, ANY);
  add("I2C.RX.data",             0, 'h008,  0,  8, RO, ANY);
  add("I2C.STATUS.irq",          0, 'h00C,  0,  1, RO, ANY);
  add("I2C.STATUS.tip",          0, 'h00C,  1,  1, RO, ANY);
  add("I2C.STATUS.al",           0, 'h00C,  5,  1, RO, ANY);
  add("I2C.STATUS.busy",         0, 'h00C,  6,  1, RO, ANY);
  add("I2C.STATUS.rxack",        0, 'h00C,  7,  1, RO, ANY);
  add("I2C.TX.data",             0, 'h010,  0,  8, RW, ANY);
  add("I2C.CMD.iack",            0, 'h014,  0,  1, WO, ANY);
  add("I2C.CMD.ack",             0, 'h014,  3,  1, WO, ANY);
  add("I2C.CMD.wr",              0, 'h014,  4,  1, WO, ANY);
  add("I2C.CMD.rd",              0, 'h014,  5,  1, WO, ANY);
  add("I2C.CMD.sto",             0, 'h014,  6,  1, WO, ANY);
  add("I2C.CMD.sta",             0, 'h014,  7,  1, WO, ANY);

  for (int t = 0; t < 2; t++) begin
    int    s = t ? 5 : 1;
    string n = t ? "TIMER1" : "TIMER0";
    for (int c = 0; c < 2; c++) begin
      int    o = c * 'h10;
      string p = $sformatf("%s.CH%0d", n, c);
      add({p, ".VAL.value"},      s, o + 'h0,  0, 32, RW, ANY);
      add({p, ".CTRL.enable"},    s, o + 'h4,  0,  1, RW, ANY);
      add({p, ".CTRL.prescaler"}, s, o + 'h4,  3,  3, RW, ANY);
      add({p, ".CMP.value"},      s, o + 'h8,  0, 32, RW, ANY);
    end
  end

  add("UART.RBR.data",           2, 'h000,  0,  8, RO, DLAB0);
  add("UART.THR.data",           2, 'h000,  0,  8, WO, DLAB0);
  add("UART.IER.dtr",            2, 'h004,  0,  1, RW, DLAB0);
  add("UART.IER.thr_empty",      2, 'h004,  1,  1, RW, DLAB0);
  add("UART.IER.rlstat",         2, 'h004,  2,  1, RW, DLAB0);
  add("UART.IER.mstat",          2, 'h004,  3,  1, RW, DLAB0);
  add("UART.IIR.status",         2, 'h008,  0,  1, RO, ANY);
  add("UART.IIR.id",             2, 'h008,  1,  3, RO, ANY);
  add("UART.IIR.fifos_en",       2, 'h008,  6,  2, RO, ANY);
  add("UART.FCR.fifo_en",        2, 'h008,  0,  1, WO, ANY);
  add("UART.FCR.rx_fifo_rst",    2, 'h008,  1,  1, WO, ANY);
  add("UART.FCR.tx_fifo_rst",    2, 'h008,  2,  1, WO, ANY);
  add("UART.FCR.rx_fifo_tl",     2, 'h008,  6,  2, WO, ANY);
  add("UART.LCR.word_len",       2, 'h00C,  0,  2, RW, ANY);
  add("UART.LCR.stop_bits",      2, 'h00C,  2,  1, RW, ANY);
  add("UART.LCR.par_en",         2, 'h00C,  3,  1, RW, ANY);
  add("UART.LCR.even_par",       2, 'h00C,  4,  1, RW, ANY);
  add("UART.LCR.force_par",      2, 'h00C,  5,  1, RW, ANY);
  add("UART.LCR.set_break",      2, 'h00C,  6,  1, RW, ANY);
  add("UART.LCR.dlab",           2, 'h00C,  7,  1, RW, ANY);
  add("UART.MCR.dtr",            2, 'h010,  0,  1, RW, ANY);
  add("UART.MCR.rts",            2, 'h010,  1,  1, RW, ANY);
  add("UART.MCR.out1",           2, 'h010,  2,  1, RW, ANY);
  add("UART.MCR.out2",           2, 'h010,  3,  1, RW, ANY);
  add("UART.MCR.loopback",       2, 'h010,  4,  1, RW, ANY);
  add("UART.LSR.status",         2, 'h014,  0,  8, RO, ANY);
  add("UART.MSR.status",         2, 'h018,  0,  8, RO, ANY);
  add("UART.DLL.value",          2, 'h000,  0,  8, RW, DLAB1);
  add("UART.DLM.value",          2, 'h004,  0,  8, RW, DLAB1);

  add("GPIO.INFO.gpio_cnt",      3, 'h000,  0, 10, RO, ANY);
  add("GPIO.INFO.version",       3, 'h000, 10, 10, RO, ANY);
  add("GPIO.CFG.intrpt_mode",    3, 'h004,  0,  1, RW, ANY);
  add("GPIO.CFG.pin_lvl_mode",   3, 'h004,  1,  1, RW, ANY);
  for (int i = 0; i < 32; i++) begin
    add($sformatf("GPIO.MODE%0d.gpio%0d", i / 16, i), 3, 'h008 + 4 * (i / 16), 2 * (i % 16), 2, RW, ANY);
    add($sformatf("GPIO.EN.gpio%0d", i),         3, 'h080, i, 1, RW, ANY);
    add($sformatf("GPIO.OUT.gpio%0d", i),        3, 'h180, i, 1, RW, ANY);
    add($sformatf("GPIO.RISE_EN.gpio%0d", i),    3, 'h380, i, 1, RW, ANY);
    add($sformatf("GPIO.FALL_EN.gpio%0d", i),    3, 'h400, i, 1, RW, ANY);
    add($sformatf("GPIO.LVLH_EN.gpio%0d", i),    3, 'h480, i, 1, RW, ANY);
    add($sformatf("GPIO.LVLL_EN.gpio%0d", i),    3, 'h500, i, 1, RW, ANY);
  end
  add("GPIO.IN.value",           3, 'h100,  0, 32, RO, ANY);
  add("GPIO.SET.value",          3, 'h200,  0, 32, WO, ANY);
  add("GPIO.CLEAR.value",        3, 'h280,  0, 32, WO, ANY);
  add("GPIO.TOGGLE.value",       3, 'h300,  0, 32, WO, ANY);
  add("GPIO.INT_STS.value",      3, 'h580,  0, 32, RO, ANY);
  add("GPIO.RISE_STS.value",     3, 'h600,  0, 32, RO, ANY);
  add("GPIO.FALL_STS.value",     3, 'h680,  0, 32, RO, ANY);
  add("GPIO.LVLH_STS.value",     3, 'h700,  0, 32, RO, ANY);
  add("GPIO.LVLL_STS.value",     3, 'h780,  0, 32, RO, ANY);

  add("SPI.STATUS.state",        4, 'h000,  0, 32, RO, ANY);
  add("SPI.STATUS.rd",           4, 'h000,  0,  1, WO, ANY);
  add("SPI.STATUS.wr",           4, 'h000,  1,  1, WO, ANY);
  add("SPI.STATUS.qrd",          4, 'h000,  2,  1, WO, ANY);
  add("SPI.STATUS.qwr",          4, 'h000,  3,  1, WO, ANY);
  add("SPI.STATUS.swrst",        4, 'h000,  4,  1, WO, ANY);
  add("SPI.STATUS.csreg",        4, 'h000,  8,  4, WO, ANY);
  add("SPI.CLKDIV.div",          4, 'h004,  0,  8, RW, ANY);
  add("SPI.SPICMD.cmd",          4, 'h008,  0, 32, RW, ANY);
  add("SPI.SPIADR.addr",         4, 'h00C,  0, 32, RW, ANY);
  add("SPI.SPILEN.cmd_len",      4, 'h010,  0,  6, RW, ANY);
  add("SPI.SPILEN.addr_len",     4, 'h010,  8,  6, RW, ANY);
  add("SPI.SPILEN.data_len",     4, 'h010, 16, 16, RW, ANY);
  add("SPI.SPIDUM.dummy_rd",     4, 'h014,  0, 16, RW, ANY);
  add("SPI.SPIDUM.dummy_wr",     4, 'h014, 16, 16, RW, ANY);
  add("SPI.TXFIFO.data",         4, 'h018,  0, 32, WO, ANY);
  add("SPI.RXFIFO.data",         4, 'h020,  0, 32, RO, ANY);
  add("SPI.INTCFG.th_tx",        4, 'h024,  0,  5, RW, ANY);
  add("SPI.INTCFG.th_rx",        4, 'h024,  8,  5, RW, ANY);
  add("SPI.INTCFG.cnt_tx",       4, 'h024, 16,  5, RW, ANY);
  add("SPI.INTCFG.cnt_rx",       4, 'h024, 24,  5, RW, ANY);
  add("SPI.INTCFG.cnt_en",       4, 'h024, 30,  1, RW, ANY);
  add("SPI.INTCFG.int_en",       4, 'h024, 31,  1, RW, ANY);
  add("SPI.INTSTA.status",       4, 'h028,  0, 32, RO, ANY);
endfunction
