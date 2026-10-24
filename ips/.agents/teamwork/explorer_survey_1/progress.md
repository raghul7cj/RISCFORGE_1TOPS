# Progress — explorer_survey_1

Last visited: 2026-10-01T21:32:00Z
Status: Survey completed, handoff report delivered

- [x] Initialized workspace and briefing
- [x] Survey SoC Top architecture and hierarchy (`riscforge_soc_subsystem.sv`)
- [x] Identify Monitor 1: Fetch Stage signal taps (`imem_sram_en`, `PCF`, `PCPlus4F`, `PC_next`, `InstrF`, `StallF`)
- [x] Identify Monitor 2: Retire Stage (RVFI/commit) signal taps (`valid_W & ~exc_valid_W`, `PC_W`, `RDW`, `ResultW`, `RegWriteW_gated`, `trap_commit_*`, `mret_commit`)
- [x] Identify Monitor 3: LSU signal taps (`lsu_mem_req`, `lsu_mem_we`, `lsu_mem_addr`, `lsu_mem_wdata`, `lsu_mem_be`, `lsu_mem_rdata`, `lsu_mem_stall`, `lsu_mem_err`, `PC_M`, `lsunitM`)
- [x] Identify Monitor 4: AXI4-Lite bus signal taps (`dut.core_axi_req` / `dut.core_axi_resp` packed structs, 5 channel handshakes)
- [x] Identify Monitor 5: APB 6-Slot peripheral bus signal taps (`dut.apb_req[0..5]`, `dut.apb_resp[0..5]`, `dut.apb_resp_slv[0..5]`, slot mapping 0:I2C, 1:Timer0, 2:UART, 3:GPIO, 4:SPI, 5:Timer1)
- [x] Identify Monitor 6: IRQ lines & interrupt controller signal taps (raw lines, `fast_irq_i`, `timer_irq_i`, `irq_gateway.pend_o`, `irq_arbiter`, shadow stack, `trap_commit_is_interrupt`)
- [x] Analyze non-intrusive tapping (passive read-only, Preponed #1step clocking, no backpressure)
- [x] Analyze circular freeze buffer architecture (64-entry, unified 64-bit timebase, broadcast `freeze_monitors`)
- [x] Compile and deliver `handoff.md`
- [x] Send completion message to parent
