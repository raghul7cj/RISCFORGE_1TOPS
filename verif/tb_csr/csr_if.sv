// csr_if.sv
interface csr_if(input logic clk);
    logic        rst_n_i;

    logic [11:0] csr_raddr_i;
    logic [31:0] csr_rdata_o;
    logic        csr_valid_o;
    
    logic [11:0] csr_waddr_normal_i;
    logic [31:0] csr_wdata_normal_i;
    logic        csr_write_en_normal_i;
    
    logic [11:0] csr_waddr_mret_i;
    logic [31:0] csr_wdata_mret_i;
    logic        csr_write_en_mret_i;

    logic        trap_valid_i;
    logic [30:0] trap_cause_i;
    logic [31:0] trap_pc_i;
    logic [31:0] trap_addr_i;
    logic        trap_addr_valid_i;
    logic        trap_is_interrupt_i;

    logic        instr_retired_i;
    
    logic        timer_intr_i;
    logic        ext_intr_i;
    logic        msft_intr_i;
    
    logic [31:0] mtvec_out_o;
    logic [31:0] mie_out_o;
    logic [31:0] mip_out_o;
    logic        mstatus_mie_out_o;
    logic [31:0] mepc_out_o;
    logic [31:0] mcause_out_o;
    logic [31:0] mstatus_out_o;

    clocking mon_clk @(posedge clk);
        input rst_n_i;
        input csr_raddr_i;
        input csr_rdata_o;
        input csr_valid_o;
        input csr_waddr_normal_i;
        input csr_wdata_normal_i;
        input csr_write_en_normal_i;
        input csr_waddr_mret_i;
        input csr_wdata_mret_i;
        input csr_write_en_mret_i;
        input trap_valid_i;
        input trap_cause_i;
        input trap_pc_i;
        input trap_addr_i;
        input trap_addr_valid_i;
        input trap_is_interrupt_i;
        input timer_intr_i;
        input ext_intr_i;
        input msft_intr_i;
        input mtvec_out_o;
        input mie_out_o;
        input mip_out_o;
        input mstatus_mie_out_o;
        input mepc_out_o;
        input mcause_out_o;
        input mstatus_out_o;
    endclocking 

endinterface: csr_if