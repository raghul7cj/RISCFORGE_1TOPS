`timescale 1ns / 1ps

`include "csr_transaction.sv"
`include "csr_driver.sv"
`include "csr_monitor.sv"
`include "csr_scoreboard.sv"
`include "csr_reference_model.sv"
`include "csr_coverage.sv"
`include "csr_sequencer.sv"
`include "csr_env.sv"
`include "csr_if.sv"

module csr_tb_top;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    csr_if inf(clk);
    csr_regfile dut (
        .clk_i(clk),
        .rst_n_i(inf.rst_n_i),
        .csr_valid_o(inf.csr_valid_o),
        .csr_raddr_i(inf.csr_raddr_i),
        .csr_rdata_o(inf.csr_rdata_o),
        .csr_waddr_normal_i(inf.csr_waddr_normal_i),
        .csr_wdata_normal_i(inf.csr_wdata_normal_i),
        .csr_write_en_normal_i(inf.csr_write_en_normal_i),
        .csr_waddr_mret_i(inf.csr_waddr_mret_i),
        .csr_wdata_mret_i(inf.csr_wdata_mret_i),
        .csr_write_en_mret_i(inf.csr_write_en_mret_i),
        .trap_valid_i(inf.trap_valid_i),
        .trap_cause_i(inf.trap_cause_i),
        .trap_pc_i(inf.trap_pc_i),
        .trap_addr_i(inf.trap_addr_i),
        .trap_addr_valid_i(inf.trap_addr_valid_i),
        .trap_is_interrupt_i(inf.trap_is_interrupt_i),
        .instr_retired_i(1'b0),
        .timer_intr_i(inf.timer_intr_i),
        .ext_intr_i(inf.ext_intr_i),
        .msft_intr_i(inf.msft_intr_i),
        .mtvec_out_o(inf.mtvec_out_o),
        .mie_out_o(inf.mie_out_o),
        .mip_out_o(inf.mip_out_o),
        .mstatus_mie_out_o(inf.mstatus_mie_out_o),
        .mepc_out_o(inf.mepc_out_o),
        .mcause_out_o(inf.mcause_out_o),
        .mstatus_out_o(inf.mstatus_out_o)
    );

    csr_env env;

    initial begin
        inf.rst_n_i = 1'b0;
        inf.csr_raddr_i = 12'h000;
        inf.csr_waddr_normal_i = 12'h000;
        inf.csr_wdata_normal_i = 32'h0;
        inf.csr_write_en_normal_i = 1'b0;
        inf.csr_waddr_mret_i = 12'h000;
        inf.csr_wdata_mret_i = 32'h0;
        inf.csr_write_en_mret_i = 1'b0;
        inf.trap_valid_i = 1'b0;
        inf.trap_cause_i = 31'h0;
        inf.trap_pc_i = 32'h0;
        inf.trap_addr_i = 32'h0;
        inf.trap_addr_valid_i = 1'b0;
        inf.trap_is_interrupt_i = 1'b0;
        inf.timer_intr_i = 1'b0;
        inf.ext_intr_i = 1'b0;
        inf.msft_intr_i = 1'b0;

        env = new(inf);
        env.build();
        env.run();

        repeat (2) @(posedge clk);
        inf.rst_n_i = 1'b1;

        // Allow the sequencer/driver/monitor pipeline to drain.
        repeat (160) @(posedge clk);

        env.report();
        $finish;
    end

endmodule
