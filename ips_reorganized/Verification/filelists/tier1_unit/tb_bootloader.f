// RISCFORGE 1TOPS — Tier 1 IP Unit: bootloader
// Invocation root: rtl/ips
// Top: bootloader_spi_tb

SOC_FILES/include/common_cells/axi_pkg.sv

bootloader/bootloader_tb_all_testcases.sv
bootloader/bootloader.sv

spi_master_ip/spi_master/spi_master_clkgen.sv
spi_master_ip/spi_master/spi_master_fifo.sv
spi_master_ip/spi_master/spi_master_rx.sv
spi_master_ip/spi_master/spi_master_tx.sv
spi_master_ip/spi_master/spi_master_controller.sv
spi_master_ip/spi_master/spi_master_apb_if.sv
spi_master_ip/spi_master/apb_spi_master.sv

spi_slave_infinion/S25fs512s/model/s25fs512s.sv
