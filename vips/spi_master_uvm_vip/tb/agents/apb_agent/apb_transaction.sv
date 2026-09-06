//------------------------------------------------------------------------------
// apb_transaction : single APB3 read or write beat.
//------------------------------------------------------------------------------
typedef enum bit { APB_READ = 1'b0, APB_WRITE = 1'b1 } apb_dir_e;

class apb_transaction extends uvm_sequence_item;

    rand bit [11:0] addr;
    rand bit [31:0] wdata;
    rand apb_dir_e  dir;

         bit [31:0] rdata;   // filled in by the driver/monitor on completion
         bit        error;   // PSLVERR observed during ACCESS phase
         int unsigned wait_states; // number of extra cycles PREADY was low

    `uvm_object_utils_begin(apb_transaction)
        `uvm_field_int(addr,        UVM_ALL_ON)
        `uvm_field_int(wdata,       UVM_ALL_ON)
        `uvm_field_enum(apb_dir_e, dir, UVM_ALL_ON)
        `uvm_field_int(rdata,       UVM_ALL_ON)
        `uvm_field_int(error,       UVM_ALL_ON)
        `uvm_field_int(wait_states, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "apb_transaction");
        super.new(name);
    endfunction

    function string convey();
        if (dir == APB_WRITE)
            return $sformatf("APB WR addr=0x%03h wdata=0x%08h", addr, wdata);
        else
            return $sformatf("APB RD addr=0x%03h rdata=0x%08h err=%0b", addr, rdata, error);
    endfunction

endclass : apb_transaction
