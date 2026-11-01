`timescale 1ns/1ns

module directed_tb;

    localparam int APB_ADDR_WIDTH = 12;

    localparam logic [APB_ADDR_WIDTH-1:0] REG_PRE    = 12'h000;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CTRL   = 12'h004;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_RX     = 12'h008;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_STATUS = 12'h00C;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_TX     = 12'h010;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CMD    = 12'h014;

    localparam logic [7:0] CMD_START_WRITE = 8'h90; // STA + WR
    localparam logic [7:0] CMD_WRITE_STOP  = 8'h50; // STO + WR
    localparam logic [7:0] CMD_READ_STOP   = 8'h68; // STO + RD + NACK
    localparam logic [7:0] CMD_IACK        = 8'h01;

    logic HCLK, HRESETn;
    logic [APB_ADDR_WIDTH-1:0] PADDR;
    logic [31:0] PWDATA;
    logic PWRITE, PSEL, PENABLE;
    logic [31:0] PRDATA;
    logic PREADY, PSLVERR, interrupt_o;

    logic scl_pad_i, scl_pad_o, scl_padoen_o;
    logic sda_pad_i, sda_pad_o, sda_padoen_o;

    tri1 scl;
    tri1 sda;

    logic slave_sda_low;
    integer pass_count, fail_count;
    integer start_count, stop_count;

    logic [6:0] slave_seen_addr;
    logic       slave_seen_rw;
    logic [7:0] slave_seen_data;
    logic [7:0] slave_tx_data;

    assign scl = (!scl_padoen_o) ? scl_pad_o : 1'bz;
    assign sda = (!sda_padoen_o) ? sda_pad_o : 1'bz;
    assign sda = slave_sda_low ? 1'b0 : 1'bz;

    assign scl_pad_i = scl;
    assign sda_pad_i = sda;

    apb_i2c #(
        .APB_ADDR_WIDTH(APB_ADDR_WIDTH)
    ) dut (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .PADDR(PADDR),
        .PWDATA(PWDATA),
        .PWRITE(PWRITE),
        .PSEL(PSEL),
        .PENABLE(PENABLE),
        .PRDATA(PRDATA),
        .PREADY(PREADY),
        .PSLVERR(PSLVERR),
        .interrupt_o(interrupt_o),
        .scl_pad_i(scl_pad_i),
        .scl_pad_o(scl_pad_o),
        .scl_padoen_o(scl_padoen_o),
        .sda_pad_i(sda_pad_i),
        .sda_pad_o(sda_pad_o),
        .sda_padoen_o(sda_padoen_o)
    );

    initial begin
        HCLK = 1'b0;
        forever #5 HCLK = ~HCLK;
    end

    task automatic check(input bit condition, input string name);
        begin
            if (condition) begin
                pass_count++;
                $display("[%0t] PASS : %s", $time, name);
            end else begin
                fail_count++;
                $display("[%0t] FAIL : %s", $time, name);
            end
        end
    endtask

    task automatic apb_write(
        input logic [APB_ADDR_WIDTH-1:0] addr,
        input logic [31:0] data
    );
        begin
            @(negedge HCLK);
            PADDR   = addr;
            PWDATA  = data;
            PWRITE  = 1'b1;
            PSEL    = 1'b1;
            PENABLE = 1'b0;

            @(negedge HCLK);
            PENABLE = 1'b1;

            @(posedge HCLK);
            #1;
            if (!PREADY || PSLVERR) begin
                fail_count++;
                $display("[%0t] FAIL : APB WRITE addr=%h", $time, addr);
            end

            @(negedge HCLK);
            PSEL    = 1'b0;
            PENABLE = 1'b0;
            PWRITE  = 1'b0;
            PADDR   = '0;
            PWDATA  = '0;
        end
    endtask

    task automatic apb_read(
        input  logic [APB_ADDR_WIDTH-1:0] addr,
        output logic [31:0] data
    );
        begin
            @(negedge HCLK);
            PADDR   = addr;
            PWRITE  = 1'b0;
            PSEL    = 1'b1;
            PENABLE = 1'b0;

            @(negedge HCLK);
            PENABLE = 1'b1;

            @(posedge HCLK);
            #1;
            data = PRDATA;

            if (!PREADY || PSLVERR) begin
                fail_count++;
                $display("[%0t] FAIL : APB READ addr=%h", $time, addr);
            end

            @(negedge HCLK);
            PSEL    = 1'b0;
            PENABLE = 1'b0;
            PADDR   = '0;
        end
    endtask

    task automatic wait_irq;
        logic [31:0] status;
        integer timeout;
        begin
            timeout = 0;
            forever begin
                apb_read(REG_STATUS, status);
                if (status[0])
                    break;

                timeout++;
                if (timeout >= 2000) begin
                    fail_count++;
                    $display("[%0t] FAIL : IRQ timeout STATUS=%02h", $time, status[7:0]);
                    disable wait_irq;
                end
            end
        end
    endtask

    task automatic clear_irq;
        logic [31:0] status;
        integer timeout;
        begin
            apb_write(REG_CMD, CMD_IACK);
            timeout = 0;
            forever begin
                apb_read(REG_STATUS, status);
                if (!status[0])
                    break;

                timeout++;
                if (timeout >= 20) begin
                    fail_count++;
                    $display("[%0t] FAIL : IRQ did not clear", $time);
                    disable clear_irq;
                end
            end
        end
    endtask

    task automatic wait_start;
        begin
            forever begin
                @(negedge sda);
                if (scl === 1'b1) begin
                    start_count++;
                    break;
                end
            end
        end
    endtask

    task automatic wait_stop;
        begin
            forever begin
                @(posedge sda);
                if (scl === 1'b1) begin
                    stop_count++;
                    break;
                end
            end
        end
    endtask

    task automatic slave_receive_byte(output logic [7:0] value);
        integer i;
        begin
            value = 8'h00;
            for (i = 7; i >= 0; i--) begin
                @(posedge scl);
                #1;
                value[i] = sda;
            end
        end
    endtask

    task automatic slave_ack;
        begin
            @(negedge scl);
            slave_sda_low = 1'b1;
            @(posedge scl);
            @(negedge scl);
            slave_sda_low = 1'b0;
        end
    endtask

    task automatic slave_send_byte(input logic [7:0] value);
        integer i;
        begin
            // We enter this task while SCL is already low, immediately after
            // the address ACK. Put bit[7] on SDA now, before its rising edge.
            slave_sda_low = ~value[7];

            for (i = 7; i >= 0; i--) begin
                @(posedge scl);
                if (i != 0) begin
                    @(negedge scl);
                    slave_sda_low = ~value[i-1];
                end
            end

            // Release SDA for the master's ACK/NACK bit.
            @(negedge scl);
            slave_sda_low = 1'b0;
        end
    endtask

    task automatic slave_sample_master_ack(output logic master_ack);
        begin
            @(posedge scl);
            #1;
            master_ack = (sda === 1'b0);
            @(negedge scl);
        end
    endtask

    task automatic slave_write_transaction;
        logic [7:0] address_byte;
        logic [7:0] data_byte;
        begin
            wait_start();

            slave_receive_byte(address_byte);
            slave_seen_addr = address_byte[7:1];
            slave_seen_rw   = address_byte[0];

            slave_ack();

            slave_receive_byte(data_byte);
            slave_seen_data = data_byte;

            slave_ack();
            wait_stop();
        end
    endtask

    task automatic slave_read_transaction;
        logic [7:0] address_byte;
        logic master_ack;
        begin
            wait_start();

            slave_receive_byte(address_byte);
            slave_seen_addr = address_byte[7:1];
            slave_seen_rw   = address_byte[0];

            slave_ack();

            slave_send_byte(slave_tx_data);
            slave_sample_master_ack(master_ack);

            // For the last byte the master must NACK (SDA high).
            if (master_ack) begin
                fail_count++;
                $display("[%0t] FAIL : Master ACKed final read byte; expected NACK", $time);
            end

            wait_stop();
        end
    endtask

    task automatic master_write_byte(
        input logic [6:0] slave_addr,
        input logic [7:0] data
    );
        logic [31:0] status;
        begin
            apb_write(REG_TX, {24'h0, slave_addr, 1'b0});
            apb_write(REG_CMD, CMD_START_WRITE);

            wait_irq();
            apb_read(REG_STATUS, status);
            if (status[7]) begin
                fail_count++;
                $display("[%0t] FAIL : Address NACK during WRITE", $time);
            end
            clear_irq();

            apb_write(REG_TX, {24'h0, data});
            apb_write(REG_CMD, CMD_WRITE_STOP);

            wait_irq();
            apb_read(REG_STATUS, status);
            if (status[7]) begin
                fail_count++;
                $display("[%0t] FAIL : Data NACK during WRITE", $time);
            end
            clear_irq();
        end
    endtask

    task automatic master_read_byte(
        input  logic [6:0] slave_addr,
        output logic [7:0] data
    );
        logic [31:0] status;
        logic [31:0] temp;
        begin
            // Address phase is still a WRITE command: the transmitted byte is
            // {7-bit address, R/W=1}.
            apb_write(REG_TX, {24'h0, slave_addr, 1'b1});
            apb_write(REG_CMD, CMD_START_WRITE);

            wait_irq();
            apb_read(REG_STATUS, status);
            if (status[7]) begin
                fail_count++;
                $display("[%0t] FAIL : Address NACK during READ", $time);
            end
            clear_irq();

            // RD + ACK=1 + STOP => receive one byte, NACK it, then STOP.
            apb_write(REG_CMD, CMD_READ_STOP);

            wait_irq();
            apb_read(REG_RX, temp);
            data = temp[7:0];
            clear_irq();
        end
    endtask

    task automatic test_write(
        input logic [6:0] addr,
        input logic [7:0] data,
        input string test_name
    );
        begin
            slave_seen_addr = 'x;
            slave_seen_rw   = 'x;
            slave_seen_data = 'x;

            fork
                slave_write_transaction();
                master_write_byte(addr, data);
            join

            check(slave_seen_addr == addr &&
                  slave_seen_rw   == 1'b0 &&
                  slave_seen_data == data,
                  test_name);
        end
    endtask

    task automatic test_read(
        input logic [6:0] addr,
        input logic [7:0] expected,
        input string test_name
    );
        logic [7:0] received;
        begin
            slave_tx_data   = expected;
            slave_seen_addr = 'x;
            slave_seen_rw   = 'x;

            fork
                slave_read_transaction();
                master_read_byte(addr, received);
            join

            check(slave_seen_addr == addr &&
                  slave_seen_rw   == 1'b1 &&
                  received        == expected,
                  test_name);
        end
    endtask

    task automatic reset_dut;
        begin
            HRESETn = 1'b0;
            PADDR   = '0;
            PWDATA  = '0;
            PWRITE  = 1'b0;
            PSEL    = 1'b0;
            PENABLE = 1'b0;
            slave_sda_low = 1'b0;

            repeat (10) @(posedge HCLK);
            HRESETn = 1'b1;
            repeat (10) @(posedge HCLK);
        end
    endtask

    task automatic configure_controller;
        begin
            // Small divider keeps directed simulation short.
            apb_write(REG_PRE, 32'd10);
            // CTRL[7]=core enable, CTRL[6]=interrupt enable.
            apb_write(REG_CTRL, 32'h0000_00C0);
        end
    endtask

    initial begin
        logic [31:0] rdata;

        pass_count  = 0;
        fail_count  = 0;
        start_count = 0;
        stop_count  = 0;

        HRESETn = 1'b0;
        PADDR   = '0;
        PWDATA  = '0;
        PWRITE  = 1'b0;
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        slave_sda_low = 1'b0;

        $display("");
        $display("================================================");
        $display("      APB-I2C DIRECTED FUNCTIONAL TEST");
        $display("================================================");

        reset_dut();

        check(scl === 1'b1 && sda === 1'b1,
              "I2C bus idle after reset");

        apb_read(REG_PRE, rdata);
        check(rdata[15:0] == 16'h0000,
              "Prescaler reset value");

        apb_read(REG_CTRL, rdata);
        check(rdata[7:0] == 8'h00,
              "Control register reset value");

        apb_read(REG_TX, rdata);
        check(rdata[7:0] == 8'h00,
              "TX register reset value");

        configure_controller();

        apb_read(REG_PRE, rdata);
        check(rdata[15:0] == 16'd10,
              "APB prescaler write/read");

        apb_read(REG_CTRL, rdata);
        check(rdata[7:0] == 8'hC0,
              "APB control register write/read");

        test_write(7'h32, 8'hAA, "Basic I2C WRITE");
        test_read (7'h45, 8'h5A, "Basic I2C READ");

        test_write(7'h20, 8'h00, "WRITE data 0x00");
        test_write(7'h21, 8'hFF, "WRITE data 0xFF");
        test_write(7'h22, 8'h55, "WRITE data 0x55");
        test_write(7'h23, 8'hAA, "WRITE data 0xAA");

        test_read(7'h30, 8'h00, "READ data 0x00");
        test_read(7'h31, 8'hFF, "READ data 0xFF");
        test_read(7'h32, 8'h55, "READ data 0x55");
        test_read(7'h33, 8'hAA, "READ data 0xAA");

        test_write(7'h10, 8'hA1, "Back-to-back WRITE #1");
        test_write(7'h11, 8'hB2, "Back-to-back WRITE #2");

        test_read(7'h40, 8'h19, "Back-to-back READ #1");
        test_read(7'h41, 8'h28, "Back-to-back READ #2");

        test_write(7'h50, 8'hDE, "WRITE before READ");
        test_read (7'h50, 8'hAD, "READ after WRITE");

        reset_dut();
        check(scl === 1'b1 && sda === 1'b1,
              "Bus idle after second reset");

        configure_controller();
        test_write(7'h2A, 8'h96, "WRITE after reset recovery");
        test_read (7'h35, 8'h69, "READ after reset recovery");

        repeat (20) @(posedge HCLK);

        check(scl === 1'b1 && sda === 1'b1,
              "I2C bus idle after all transfers");

        check(start_count > 0, "START condition generated");
        check(stop_count  > 0, "STOP condition generated");

        $display("");
        $display("================================================");
        $display("            DIRECTED TEST REPORT");
        $display("================================================");
        $display("PASS        = %0d", pass_count);
        $display("FAIL        = %0d", fail_count);
        $display("START COUNT = %0d", start_count);
        $display("STOP COUNT  = %0d", stop_count);
        $display("================================================");

        if (fail_count == 0)
            $display("        APB-I2C VERIFICATION PASSED");
        else
            $display("        APB-I2C VERIFICATION FAILED");

        $display("================================================");

        #100;
        $finish;
    end

    initial begin
        #1_000_000;
        $display("[%0t] FAIL : GLOBAL TESTBENCH TIMEOUT", $time);
        $finish;
    end

endmodule
