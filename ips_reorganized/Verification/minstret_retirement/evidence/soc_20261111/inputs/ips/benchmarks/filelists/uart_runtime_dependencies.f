// Current apb_uart.sv instantiates apb_uart_wrap and the OBI UART IP.
// These real RTL dependencies are omitted by the legacy design-only list.
+incdir+apb_uart-main/include/obi
+incdir+apb_uart-main/include
+incdir+axi_lite_xbar/include/common_cells
axi_lite_xbar/include/common_cells/cf_math_pkg.sv
apb_uart-main/include/obi/obi_pkg.sv
apb_uart-main/include/obi/obi_uart_pkg.sv
apb_uart-main/include/obi/apb_to_obi.sv
apb_uart-main/include/obi/obi_uart_modem.sv
apb_uart-main/include/obi/obi_uart_baudgen.sv
apb_uart-main/include/obi/obi_uart_rx.sv
apb_uart-main/include/obi/obi_uart_tx.sv
apb_uart-main/include/obi/obi_uart_interrupts.sv
apb_uart-main/include/obi/obi_uart_register.sv
apb_uart-main/include/obi/obi_uart.sv
apb_uart-main/rtl/apb_uart_wrap.sv
