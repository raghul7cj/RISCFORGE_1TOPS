class hazard_transaction;
    rand bit rst;

    rand bit RegWriteM; 
    rand bit RegWriteW;

    rand bit [4:0] RD_M;
    rand bit [4:0] RD_W;

    rand bit [4:0] Rs1_E;
    rand bit [4:0] Rs2_E;

    rand bit [4:0] Rs1_D;
    rand bit [4:0] Rs2_D;

    rand bit [4:0] RdE;

    rand bit [1:0] ResultSrcE;

    rand bit PCSrcE;

    rand bit illegal_instr;

    rand bit csr_valid_D;

    rand bit [11:0] csr_raddr_D;
    rand bit [11:0] csr_raddr_E;
    rand bit [11:0] csr_raddr_W;

    rand bit [11:0] csr_addr_E;
    rand bit [11:0] csr_addr_M;
    rand bit [11:0] csr_addr_W;

    rand bit csr_write_en_E;
    rand bit csr_write_en_M;
    rand bit csr_write_en_W;

    rand bit [3:0] flush_pipeline_onehot;

    rand bit valid_E;
    rand bit exc_valid_E;

    rand bit valid_M;
    rand bit exc_valid_M;

    rand bit wb_redirect;

    rand bit stallM;

    // outputs
    bit [1:0] ForwardAE;
    bit [1:0] ForwardBE;

    bit StallF;
    bit StallD;

    bit FlushD;
    bit FlushE;
    bit FlushM;
    bit FlushW;

    function hazard_transaction copy();
        copy = new();
        copy.rst = this.rst;
    
        copy.RegWriteM = this.RegWriteM;
        copy.RegWriteW = this.RegWriteW;
        
        copy.RD_M = this.RD_M;
        copy.RD_W = this.RD_W;
        
        copy.Rs1_E = this.Rs1_E;
        copy.Rs2_E = this.Rs2_E;
        
        copy.Rs1_D = this.Rs1_D;
        copy.Rs2_D = this.Rs2_D;
        
        copy.RdE = this.RdE;
        
        copy.ResultSrcE = this.ResultSrcE;
        
        copy.PCSrcE = this.PCSrcE;
        
        copy.ForwardAE = this.ForwardAE;
        copy.ForwardBE = this.ForwardBE;
        
        copy.StallF = this.StallF;
        copy.StallD = this.StallD;
        
        copy.FlushD = this.FlushD;
        copy.FlushE = this.FlushE;
        copy.FlushM = this.FlushM;
        copy.FlushW = this.FlushW;   
    endfunction

    function void display(string tag="TXN");
        $display("[%s] Rs1_E=%0d Rs2_E=%0d RD_M=%0d RD_W=%0d RegWriteM=%0b RegWriteW=%0b ForwardAE=%0b ForwardBE=%0b",
                 tag, Rs1_E, Rs2_E, RD_M, RD_W, RegWriteM, RegWriteW, ForwardAE, ForwardBE);
    endfunction

endclass

class mem_forward_txn extends hazard_transaction;
   constraint mem_fwd_c {
      rst == 1;
      RegWriteM == 1;
      Rs1_E inside {[1:31]};
      RD_M == Rs1_E;
   }
endclass


class wb_forward_txn extends hazard_transaction;
   constraint wb_fwd_c {
      rst == 1;
      RegWriteW == 1
      RegWriteM == 0;
      Rs1_E inside {[1:31]};
      RD_W == Rs1_E;
   }
endclass

class mem_priority_txn extends hazard_transaction;
   constraint mem_pri_c {
      rst == 1;
      RegWriteM == 1;
      RegWriteW == 1;
      Rs1_E inside {[1:31]};
      RD_M == Rs1_E;
      RD_W == Rs1_E;
   }
endclass


class load_use_txn extends hazard_transaction;
   constraint load_c {
      rst == 1;
      ResultSrcE == 2'b01;
      RdE inside {[1:31]};
      Rs1_D == RdE;
   }
endclass


class csr_stall_txn extends hazard_transaction;
   constraint csr_c {
      rst == 1;
      csr_valid_D == 1;
      csr_write_en_E == 1;
      csr_raddr_D == csr_addr_E;
   }
endclass


class csr_gpr_stall_txn extends hazard_transaction;
   constraint csr_gpr_c {
      rst == 1;
      ResultSrcE == 2'b11;
      RdE inside {[1:31]};
      Rs1_D == RdE;
   }
endclass


class redirect_txn extends hazard_transaction;
   constraint redirect_c {
      wb_redirect == 1;
   }
endclass


class x0_forward_txn extends hazard_transaction;
   constraint x0_c {
      rst == 1;
      RegWriteM == 1;
      Rs1_E == 0;
      RD_M == 0;
   }
endclass