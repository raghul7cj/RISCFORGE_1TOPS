interface hazard_if; 
    logic rst;

    logic RegWriteM; 
    logic RegWriteW;

    logic [4:0] RD_M;
    logic [4:0] RD_W;

    logic [4:0] Rs1_E;
    logic [4:0] Rs2_E;

    logic [4:0] Rs1_D;
    logic [4:0] Rs2_D;

    logic [4:0] RdE;

    logic [1:0] ResultSrcE;

    logic PCSrcE;

    logic illegal_instr;

    logic csr_valid_D;

    logic [11:0] csr_raddr_D; 
    logic [11:0] csr_raddr_E;
    logic [11:0] csr_raddr_W;

    logic [11:0] csr_addr_E; 
    logic [11:0] csr_addr_M;
    logic [11:0] csr_addr_W;

    logic csr_write_en_E;  
    logic csr_write_en_M; 
    logic csr_write_en_W;

    logic [3:0] flush_pipeline_onehot;

    logic valid_E;
    logic exc_valid_E;

    logic valid_M;
    logic exc_valid_M;

    logic wb_redirect; 

    logic stallM; 

    // outputs
    logic [1:0] ForwardAE; 
    logic [1:0] ForwardBE; 

    logic StallF;
    logic StallD;

    logic FlushD;
    logic FlushE;
    logic FlushM;
    logic FlushW;
endinterface