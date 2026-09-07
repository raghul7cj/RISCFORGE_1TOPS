class apb_base_seq extends uvm_sequence #(apb_timer_txn);

    `uvm_object_utils(apb_base_seq)

    function new(string name = "apb_base_seq");
        super.new(name);
    endfunction

    task send_write(bit [11:0] addr, bit [31:0] data);

        apb_timer_txn tr;

        tr = apb_timer_txn::type_id::create("tr");

        start_item(tr);

        tr.write = 1'b1;
        tr.addr  = addr;
        tr.wdata = data;

        finish_item(tr);

    endtask

    task send_read(bit [11:0] addr);

        apb_timer_txn tr;

        tr = apb_timer_txn::type_id::create("tr");

        start_item(tr);

        tr.write = 1'b0;
        tr.addr  = addr;
        tr.wdata = '0;

        finish_item(tr);

    endtask

endclass


class apb_random_seq extends apb_base_seq;

    `uvm_object_utils(apb_random_seq)

    int count = 2000;

    function new(string name = "apb_random_seq");
        super.new(name);
    endfunction

    task body();

        apb_timer_txn tr;

        repeat (count) begin

            tr = apb_timer_txn::type_id::create("tr");

            start_item(tr);

            if (!tr.randomize())
                `uvm_fatal("RAND", "Transaction randomization failed")

            finish_item(tr);

        end

    endtask

endclass


class apb_register_seq extends apb_base_seq;

    `uvm_object_utils(apb_register_seq)

    function new(string name = "apb_register_seq");
        super.new(name);
    endfunction

    task body();

        send_write(12'h000, 32'h1234_5678);
        send_read (12'h000);

        send_write(12'h004, 32'h0000_0000);
        send_read (12'h004);

        send_write(12'h008, 32'd10);
        send_read (12'h008);

        send_write(12'h010, 32'h8765_4321);
        send_read (12'h010);

        send_write(12'h014, 32'h0000_0000);
        send_read (12'h014);

        send_write(12'h018, 32'd15);
        send_read (12'h018);

    endtask

endclass


class apb_prescaler_seq extends apb_base_seq;

    `uvm_object_utils(apb_prescaler_seq)

    function new(string name = "apb_prescaler_seq");
        super.new(name);
    endfunction

    task body();

        bit [11:0] base;
        bit [31:0] ctrl;

        for (int t = 0; t < 2; t++) begin

            base = t ? 12'h010 : 12'h000;

            for (int p = 0; p <= 7; p++) begin

                ctrl = (p << 3) | 1;

                send_write(base + 12'h004, 0);
                send_write(base + 12'h000, 0);
                send_write(base + 12'h008, 0);
                send_write(base + 12'h004, ctrl);

                repeat (3)
                    send_read(base + 12'h000);

                send_write(base + 12'h004, 0);

            end

        end

    endtask

endclass


class apb_compare_irq_seq extends apb_base_seq;

    `uvm_object_utils(apb_compare_irq_seq)

    function new(string name = "apb_compare_irq_seq");
        super.new(name);
    endfunction

    task body();

        bit [11:0] base;

        for (int t = 0; t < 2; t++) begin

            base = t ? 12'h010 : 12'h000;

            send_write(base + 12'h004, 0);
            send_write(base + 12'h000, 0);
            send_write(base + 12'h008, 5 + t);
            send_write(base + 12'h004, 1);

            repeat (6)
                send_read(base + 12'h000);

            send_write(base + 12'h004, 0);

        end

    endtask

endclass


class apb_overflow_seq extends apb_base_seq;

    `uvm_object_utils(apb_overflow_seq)

    function new(string name = "apb_overflow_seq");
        super.new(name);
    endfunction

    task body();

        bit [11:0] base;

        for (int t = 0; t < 2; t++) begin

            base = t ? 12'h010 : 12'h000;

            send_write(base + 12'h004, 0);
            send_write(base + 12'h008, 0);
            send_write(base + 12'h000, 32'hFFFF_FFFE);
            send_write(base + 12'h004, 1);

            repeat (4)
                send_read(base + 12'h000);

            send_write(base + 12'h004, 0);

        end

    endtask

endclass


class apb_cmp_zero_seq extends apb_base_seq;

    `uvm_object_utils(apb_cmp_zero_seq)

    function new(string name = "apb_cmp_zero_seq");
        super.new(name);
    endfunction

    task body();

        send_write(12'h004, 0);
        send_write(12'h000, 0);
        send_write(12'h008, 0);
        send_write(12'h004, 1);

        repeat (5)
            send_read(12'h000);

        send_write(12'h004, 0);

    endtask

endclass


class apb_independence_seq extends apb_base_seq;

    `uvm_object_utils(apb_independence_seq)

    function new(string name = "apb_independence_seq");
        super.new(name);
    endfunction

    task body();

        send_write(12'h004, 0);
        send_write(12'h014, 0);

        send_write(12'h008, 32'd11);
        send_write(12'h018, 32'd17);

        send_read(12'h008);
        send_read(12'h018);

        send_write(12'h000, 32'd3);
        send_write(12'h010, 32'd8);

        send_read(12'h000);
        send_read(12'h010);

    endtask

endclass
