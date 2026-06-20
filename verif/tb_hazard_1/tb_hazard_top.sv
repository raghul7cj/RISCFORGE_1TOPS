module tb_hazard_top;
    hazard_if vif();
    hazard_test test;
    hazard_unit DUT(
        .rst(vif.rst),

        .RegWriteM(vif.RegWriteM),
        .RegWriteW(vif.RegWriteW),

        .RD_M(vif.RD_M),
        .RD_W(vif.RD_W),

        .Rs1_E(vif.Rs1_E),
        .Rs2_E(vif.Rs2_E),

        .Rs1_D(vif.Rs1_D),
        .Rs2_D(vif.Rs2_D),

        .RdE(vif.RdE),

        .ForwardAE(vif.ForwardAE),
        .ForwardBE(vif.ForwardBE),

        .ResultSrcE(vif.ResultSrcE),

        .PCSrcE(vif.PCSrcE),

        .StallF(vif.StallF),
        .StallD(vif.StallD),

        .FlushD(vif.FlushD),
        .FlushE(vif.FlushE),
        .FlushM(vif.FlushM),
        .FlushW(vif.FlushW),

        .illegal_instr(vif.illegal_instr),

        .csr_valid_D(vif.csr_valid_D),

        .csr_raddr_D(vif.csr_raddr_D),
        .csr_raddr_E(vif.csr_raddr_E),
        .csr_raddr_W(vif.csr_raddr_W),

        .csr_addr_E(vif.csr_addr_E),
        .csr_addr_M(vif.csr_addr_M),
        .csr_addr_W(vif.csr_addr_W),

        .csr_write_en_E(vif.csr_write_en_E),
        .csr_write_en_M(vif.csr_write_en_M),
        .csr_write_en_W(vif.csr_write_en_W),

        .flush_pipeline_onehot(vif.flush_pipeline_onehot),

        .valid_E(vif.valid_E),
        .exc_valid_E(vif.exc_valid_E),

        .valid_M(vif.valid_M),
        .exc_valid_M(vif.exc_valid_M),

        .wb_redirect(vif.wb_redirect),

        .stallM(vif.stallM)
    );

    initial begin
        test = new(vif);
        test.run();
    end
endmodule