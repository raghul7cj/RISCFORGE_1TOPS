class apb_timer_txn extends uvm_sequence_item;

    rand bit write;
    rand bit [11:0] addr;
    rand bit [31:0] wdata;

    bit [31:0] rdata;
    bit slverr;

    constraint addr_c {
        addr inside {
            12'h000, 12'h004, 12'h008,
            12'h010, 12'h014, 12'h018
        };
    }

    constraint ctrl_c {
        if (write && (addr == 12'h004 || addr == 12'h014)) {
            wdata[0] inside {0,1};
            wdata[5:3] inside {[0:7]};
            wdata[2:1] == 0;
            wdata[31:6] == 0;
        }
    }

    constraint cmp_c {
        if (write && (addr == 12'h008 || addr == 12'h018))
            wdata inside {[0:20]};
    }

    `uvm_object_utils_begin(apb_timer_txn)
        `uvm_field_int(write,  UVM_ALL_ON)
        `uvm_field_int(addr,   UVM_ALL_ON)
        `uvm_field_int(wdata,  UVM_ALL_ON)
        `uvm_field_int(rdata,  UVM_ALL_ON)
        `uvm_field_int(slverr, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "apb_timer_txn");
        super.new(name);
    endfunction

endclass
