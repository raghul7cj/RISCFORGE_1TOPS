-access +rwc

// 32 KB ISRAM + 32 KB DSRAM variant, exercising the chunked SPI burst fetch.
// Mirrors bootloader.f but selects the 32KB-SRAM testbench as the top module.
// Run with:  xrun -f bootloader_32KB_sram.f

../SOC_FILES/include/common_cells/axi_pkg.sv

rtl/bootloader_tb_all_testcases_32KB_sram.sv
rtl/bootloader.sv

../spi/spi_master/spi_master_clkgen.sv
../spi/spi_master/spi_master_fifo.sv
../spi/spi_master/spi_master_rx.sv
../spi/spi_master/spi_master_tx.sv
../spi/spi_master/spi_master_controller.sv
../spi/spi_master/spi_master_apb_if.sv
../spi/spi_master/apb_spi_master.sv

../spi_slave_infinion/S25fs512s/model/s25fs512s.sv
