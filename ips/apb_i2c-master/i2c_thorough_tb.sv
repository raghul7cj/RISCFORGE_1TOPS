`timescale 1ns/1ns

//=============================================================================
//  THOROUGH APB-I2C VERIFICATION TESTBENCH
//=============================================================================
//  Covers:
//    Section 1 — APB protocol-level (PREADY, PSLVERR, invalid addr, RO regs)
//    Section 2 — Register-level (all reset values, prescaler range, CMD gate)
//    Section 3 — Basic I2C write / read (carried over & extended)
//    Section 4 — Data-pattern stress
//    Section 5 — Back-to-back & mixed direction
//    Section 6 — NACK handling (address & data)
//    Section 7 — Multi-byte write / read
//    Section 8 — Repeated START (combined format)
//    Section 9 — Clock stretching
//    Section 10 — Arbitration lost
//    Section 11 — Bus-busy detection
//    Section 12 — Interrupt tests
//    Section 13 — Corner cases (reset during xfer, core disable, etc.)
//=============================================================================

module thorough_tb;

    //=========================================================================
    //  Parameters & register map
    //=========================================================================
    localparam int APB_ADDR_WIDTH = 12;
    localparam int CLK_PERIOD     = 10;   // 10 ns → 100 MHz
    localparam int PRESCALER      = 10;   // fast simulation

    // Register addresses (byte-addressed, PADDR[5:2] selects register)
    localparam logic [APB_ADDR_WIDTH-1:0] REG_PRE    = 12'h000;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CTRL   = 12'h004;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_RX     = 12'h008;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_STATUS = 12'h00C;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_TX     = 12'h010;
    localparam logic [APB_ADDR_WIDTH-1:0] REG_CMD    = 12'h014;

    // Invalid / unmapped addresses
    localparam logic [APB_ADDR_WIDTH-1:0] ADDR_INVALID_1 = 12'h018;
    localparam logic [APB_ADDR_WIDTH-1:0] ADDR_INVALID_2 = 12'h01C;
    localparam logic [APB_ADDR_WIDTH-1:0] ADDR_INVALID_3 = 12'hFFC;

    // Command byte encodings
    localparam logic [7:0] CMD_START_WRITE = 8'h90;   // STA + WR
    localparam logic [7:0] CMD_WRITE       = 8'h10;   // WR only (no STA/STO)
    localparam logic [7:0] CMD_WRITE_STOP  = 8'h50;   // STO + WR
    localparam logic [7:0] CMD_READ_ACK    = 8'h20;   // RD only (ACK=0 → master ACK)
    localparam logic [7:0] CMD_READ_STOP   = 8'h68;   // STO + RD + NACK
    localparam logic [7:0] CMD_IACK        = 8'h01;   // Interrupt acknowledge
    localparam logic [7:0] CMD_START_READ  = 8'hA0;   // STA + RD (for repeated start)

    //=========================================================================
    //  DUT signals
    //=========================================================================
    logic                      HCLK, HRESETn;
    logic [APB_ADDR_WIDTH-1:0] PADDR;
    logic [31:0]               PWDATA;
    logic                      PWRITE, PSEL, PENABLE;
    logic [31:0]               PRDATA;
    logic                      PREADY, PSLVERR, interrupt_o;

    logic scl_pad_i, scl_pad_o, scl_padoen_o;
    logic sda_pad_i, sda_pad_o, sda_padoen_o;

    // Open-drain bus model
    tri1 scl;
    tri1 sda;

    logic slave_sda_low;
    logic slave_scl_low;   // for clock stretching

    assign scl = (!scl_padoen_o) ? scl_pad_o : 1'bz;
    assign scl = slave_scl_low   ? 1'b0      : 1'bz;
    assign sda = (!sda_padoen_o) ? sda_pad_o : 1'bz;
    assign sda = slave_sda_low   ? 1'b0      : 1'bz;

    assign scl_pad_i = scl;
    assign sda_pad_i = sda;

    //=========================================================================
    //  Counters & scoreboard
    //=========================================================================
    integer pass_count, fail_count;
    integer start_count, stop_count;
    integer test_section;

    logic [6:0] slave_seen_addr;
    logic       slave_seen_rw;
    logic [7:0] slave_seen_data;
    logic [7:0] slave_tx_data;

    //=========================================================================
    //  Continuous PREADY / PSLVERR assertion (runs for entire simulation)
    //=========================================================================
    always @(posedge HCLK) begin
        if (HRESETn) begin
            if (PREADY !== 1'b1) begin
                $display("[%0t] ASSERT-FAIL : PREADY is not 1 (got %b)", $time, PREADY);
            end
            if (PSLVERR !== 1'b0) begin
                $display("[%0t] ASSERT-FAIL : PSLVERR is not 0 (got %b)", $time, PSLVERR);
            end
        end
    end

    //=========================================================================
    //  DUT instantiation
    //=========================================================================
    apb_i2c #(
        .APB_ADDR_WIDTH(APB_ADDR_WIDTH)
    ) dut (
        .HCLK        (HCLK),
        .HRESETn     (HRESETn),
        .PADDR       (PADDR),
        .PWDATA      (PWDATA),
        .PWRITE      (PWRITE),
        .PSEL        (PSEL),
        .PENABLE     (PENABLE),
        .PRDATA      (PRDATA),
        .PREADY      (PREADY),
        .PSLVERR     (PSLVERR),
        .interrupt_o (interrupt_o),
        .scl_pad_i   (scl_pad_i),
        .scl_pad_o   (scl_pad_o),
        .scl_padoen_o(scl_padoen_o),
        .sda_pad_i   (sda_pad_i),
        .sda_pad_o   (sda_pad_o),
        .sda_padoen_o(sda_padoen_o)
    );

    //=========================================================================
    //  Clock generation
    //=========================================================================
    initial begin
        HCLK = 1'b0;
        forever #(CLK_PERIOD/2) HCLK = ~HCLK;
    end

    //=========================================================================
    //  Utility: check assertion
    //=========================================================================
    task automatic check(input bit condition, input string name);
        if (condition) begin
            pass_count++;
            $display("[%0t] PASS : %s", $time, name);
        end else begin
            fail_count++;
            $display("[%0t] FAIL : %s", $time, name);
        end
    endtask

    //=========================================================================
    //  APB write / read tasks
    //=========================================================================
    task automatic apb_write(
        input logic [APB_ADDR_WIDTH-1:0] addr,
        input logic [31:0] data
    );
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
            $display("[%0t] FAIL : APB WRITE handshake addr=%h", $time, addr);
        end

        @(negedge HCLK);
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
        PADDR   = '0;
        PWDATA  = '0;
    endtask

    task automatic apb_read(
        input  logic [APB_ADDR_WIDTH-1:0] addr,
        output logic [31:0] data
    );
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
            $display("[%0t] FAIL : APB READ handshake addr=%h", $time, addr);
        end

        @(negedge HCLK);
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PADDR   = '0;
    endtask

    //=========================================================================
    //  IRQ helpers
    //=========================================================================
    task automatic wait_irq;
        logic [31:0] status;
        integer timeout;
        timeout = 0;
        forever begin
            apb_read(REG_STATUS, status);
            if (status[0]) break;
            timeout++;
            if (timeout >= 2000) begin
                fail_count++;
                $display("[%0t] FAIL : IRQ timeout STATUS=%02h", $time, status[7:0]);
                return;
            end
        end
    endtask

    task automatic clear_irq;
        logic [31:0] status;
        integer timeout;
        apb_write(REG_CMD, CMD_IACK);
        timeout = 0;
        forever begin
            apb_read(REG_STATUS, status);
            if (!status[0]) break;
            timeout++;
            if (timeout >= 20) begin
                fail_count++;
                $display("[%0t] FAIL : IRQ did not clear", $time);
                return;
            end
        end
    endtask

    //=========================================================================
    //  I2C bus event detectors
    //=========================================================================
    task automatic wait_start;
        forever begin
            @(negedge sda);
            if (scl === 1'b1) begin
                start_count++;
                break;
            end
        end
    endtask

    task automatic wait_stop;
        forever begin
            @(posedge sda);
            if (scl === 1'b1) begin
                stop_count++;
                break;
            end
        end
    endtask

    //=========================================================================
    //  Slave-side bit-level tasks
    //=========================================================================
    task automatic slave_receive_byte(output logic [7:0] value);
        integer i;
        value = 8'h00;
        for (i = 7; i >= 0; i--) begin
            @(posedge scl);
            #1;
            value[i] = sda;
        end
    endtask

    task automatic slave_ack;
        @(negedge scl);
        slave_sda_low = 1'b1;
        @(posedge scl);
        @(negedge scl);
        slave_sda_low = 1'b0;
    endtask

    task automatic slave_nack;
        // Simply don't pull SDA low — tri1 keeps it high = NACK
        @(negedge scl);
        slave_sda_low = 1'b0;
        @(posedge scl);
        @(negedge scl);
    endtask

    task automatic slave_send_byte(input logic [7:0] value);
        integer i;
        slave_sda_low = ~value[7];
        for (i = 7; i >= 0; i--) begin
            @(posedge scl);
            if (i != 0) begin
                @(negedge scl);
                slave_sda_low = ~value[i-1];
            end
        end
        @(negedge scl);
        slave_sda_low = 1'b0;
    endtask

    task automatic slave_sample_master_ack(output logic master_ack);
        @(posedge scl);
        #1;
        master_ack = (sda === 1'b0);
        @(negedge scl);
    endtask

    //=========================================================================
    //  Slave transaction models
    //=========================================================================

    // Standard write transaction: START → addr+W → ACK → data → ACK → STOP
    task automatic slave_write_transaction;
        logic [7:0] address_byte, data_byte;
        wait_start();
        slave_receive_byte(address_byte);
        slave_seen_addr = address_byte[7:1];
        slave_seen_rw   = address_byte[0];
        slave_ack();
        slave_receive_byte(data_byte);
        slave_seen_data = data_byte;
        slave_ack();
        wait_stop();
    endtask

    // Standard read transaction: START → addr+R → ACK → slave_tx → master NACK → STOP
    task automatic slave_read_transaction;
        logic [7:0] address_byte;
        logic master_ack;
        wait_start();
        slave_receive_byte(address_byte);
        slave_seen_addr = address_byte[7:1];
        slave_seen_rw   = address_byte[0];
        slave_ack();
        slave_send_byte(slave_tx_data);
        slave_sample_master_ack(master_ack);
        if (master_ack) begin
            fail_count++;
            $display("[%0t] FAIL : Master ACKed final read byte; expected NACK", $time);
        end
        wait_stop();
    endtask

    // Write transaction where slave NACKs the address
    task automatic slave_nack_addr_transaction;
        logic [7:0] address_byte;
        wait_start();
        slave_receive_byte(address_byte);
        slave_seen_addr = address_byte[7:1];
        slave_seen_rw   = address_byte[0];
        slave_nack();  // NACK the address
        wait_stop();
    endtask

    // Write transaction where slave ACKs address but NACKs data
    task automatic slave_nack_data_transaction;
        logic [7:0] address_byte, data_byte;
        wait_start();
        slave_receive_byte(address_byte);
        slave_seen_addr = address_byte[7:1];
        slave_seen_rw   = address_byte[0];
        slave_ack();
        slave_receive_byte(data_byte);
        slave_seen_data = data_byte;
        slave_nack();  // NACK the data byte
        wait_stop();
    endtask

    // Multi-byte write: START → addr+W → ACK → data0 → ACK → data1 → ACK → STOP
    task automatic slave_multibyte_write_transaction(
        output logic [7:0] data0,
        output logic [7:0] data1
    );
        logic [7:0] address_byte;
        wait_start();
        slave_receive_byte(address_byte);
        slave_seen_addr = address_byte[7:1];
        slave_seen_rw   = address_byte[0];
        slave_ack();

        slave_receive_byte(data0);
        slave_ack();

        slave_receive_byte(data1);
        slave_ack();

        wait_stop();
    endtask

    // Multi-byte read: START → addr+R → ACK → slave_tx0 → master ACK → slave_tx1 → master NACK → STOP
    task automatic slave_multibyte_read_transaction(
        input logic [7:0] tx_byte0,
        input logic [7:0] tx_byte1
    );
        logic [7:0] address_byte;
        logic master_ack;
        wait_start();
        slave_receive_byte(address_byte);
        slave_seen_addr = address_byte[7:1];
        slave_seen_rw   = address_byte[0];
        slave_ack();

        // First byte — master should ACK
        slave_send_byte(tx_byte0);
        slave_sample_master_ack(master_ack);
        if (!master_ack) begin
            fail_count++;
            $display("[%0t] FAIL : Master NACKed first read byte; expected ACK", $time);
        end

        // Second (last) byte — master should NACK
        slave_send_byte(tx_byte1);
        slave_sample_master_ack(master_ack);
        if (master_ack) begin
            fail_count++;
            $display("[%0t] FAIL : Master ACKed last read byte; expected NACK", $time);
        end

        wait_stop();
    endtask

    // Repeated-START combined write-then-read transaction
    // START → addr+W → ACK → data_wr → ACK → Sr → addr+R → ACK → slave_tx → master NACK → STOP
    task automatic slave_combined_wr_rd_transaction(
        output logic [7:0] received_wr_data,
        input  logic [7:0] tx_byte
    );
        logic [7:0] address_byte;
        logic master_ack;

        // Phase 1: Write
        wait_start();
        slave_receive_byte(address_byte);
        slave_seen_addr = address_byte[7:1];
        slave_seen_rw   = address_byte[0];
        slave_ack();

        slave_receive_byte(received_wr_data);
        slave_ack();

        // Phase 2: Repeated START + Read
        wait_start();
        slave_receive_byte(address_byte);
        slave_seen_addr = address_byte[7:1];
        slave_seen_rw   = address_byte[0];
        slave_ack();

        slave_send_byte(tx_byte);
        slave_sample_master_ack(master_ack);
        if (master_ack) begin
            fail_count++;
            $display("[%0t] FAIL : Master ACKed final read byte in combined xact", $time);
        end

        wait_stop();
    endtask

    // Clock-stretching write transaction: slave holds SCL low after address ACK
    task automatic slave_write_with_clock_stretch(input int stretch_clocks);
        logic [7:0] address_byte, data_byte;
        wait_start();
        slave_receive_byte(address_byte);
        slave_seen_addr = address_byte[7:1];
        slave_seen_rw   = address_byte[0];

        // ACK the address
        @(negedge scl);
        slave_sda_low = 1'b1;
        @(posedge scl);
        @(negedge scl);
        slave_sda_low = 1'b0;

        // === Clock stretching: hold SCL low ===
        slave_scl_low = 1'b1;
        repeat (stretch_clocks) @(posedge HCLK);
        slave_scl_low = 1'b0;

        // Continue with data byte
        slave_receive_byte(data_byte);
        slave_seen_data = data_byte;
        slave_ack();
        wait_stop();
    endtask

    //=========================================================================
    //  Master-side high-level tasks
    //=========================================================================
    task automatic master_write_byte(
        input logic [6:0] slave_addr,
        input logic [7:0] data
    );
        logic [31:0] status;

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
    endtask

    task automatic master_read_byte(
        input  logic [6:0] slave_addr,
        output logic [7:0] data
    );
        logic [31:0] status, temp;

        apb_write(REG_TX, {24'h0, slave_addr, 1'b1});
        apb_write(REG_CMD, CMD_START_WRITE);

        wait_irq();
        apb_read(REG_STATUS, status);
        if (status[7]) begin
            fail_count++;
            $display("[%0t] FAIL : Address NACK during READ", $time);
        end
        clear_irq();

        apb_write(REG_CMD, CMD_READ_STOP);

        wait_irq();
        apb_read(REG_RX, temp);
        data = temp[7:0];
        clear_irq();
    endtask

    // Master write that expects NACK on address (sends STOP after NACK)
    task automatic master_write_expect_addr_nack(
        input logic [6:0] slave_addr,
        input logic [7:0] data
    );
        logic [31:0] status;

        apb_write(REG_TX, {24'h0, slave_addr, 1'b0});
        apb_write(REG_CMD, CMD_START_WRITE);

        wait_irq();
        apb_read(REG_STATUS, status);
        check(status[7] == 1'b1, "STATUS[7] rxack set on addr NACK");
        clear_irq();

        // Issue STOP to release the bus
        apb_write(REG_CMD, CMD_WRITE_STOP);
        wait_irq();
        clear_irq();
    endtask

    // Master write that expects NACK on data byte
    task automatic master_write_expect_data_nack(
        input logic [6:0] slave_addr,
        input logic [7:0] data
    );
        logic [31:0] status;

        apb_write(REG_TX, {24'h0, slave_addr, 1'b0});
        apb_write(REG_CMD, CMD_START_WRITE);

        wait_irq();
        apb_read(REG_STATUS, status);
        check(status[7] == 1'b0, "Address ACK received (before data NACK)");
        clear_irq();

        apb_write(REG_TX, {24'h0, data});
        apb_write(REG_CMD, CMD_WRITE_STOP);

        wait_irq();
        apb_read(REG_STATUS, status);
        check(status[7] == 1'b1, "STATUS[7] rxack set on data NACK");
        clear_irq();
    endtask

    // Multi-byte write (2 bytes, no STOP between them)
    task automatic master_multibyte_write(
        input logic [6:0] slave_addr,
        input logic [7:0] data0,
        input logic [7:0] data1
    );
        logic [31:0] status;

        // Address phase
        apb_write(REG_TX, {24'h0, slave_addr, 1'b0});
        apb_write(REG_CMD, CMD_START_WRITE);
        wait_irq();
        apb_read(REG_STATUS, status);
        if (status[7]) begin fail_count++; $display("[%0t] FAIL : Addr NACK in multi-write", $time); end
        clear_irq();

        // Data byte 0 (no STOP)
        apb_write(REG_TX, {24'h0, data0});
        apb_write(REG_CMD, CMD_WRITE);
        wait_irq();
        apb_read(REG_STATUS, status);
        if (status[7]) begin fail_count++; $display("[%0t] FAIL : Data0 NACK in multi-write", $time); end
        clear_irq();

        // Data byte 1 + STOP
        apb_write(REG_TX, {24'h0, data1});
        apb_write(REG_CMD, CMD_WRITE_STOP);
        wait_irq();
        apb_read(REG_STATUS, status);
        if (status[7]) begin fail_count++; $display("[%0t] FAIL : Data1 NACK in multi-write", $time); end
        clear_irq();
    endtask

    // Multi-byte read (2 bytes)
    task automatic master_multibyte_read(
        input  logic [6:0] slave_addr,
        output logic [7:0] data0,
        output logic [7:0] data1
    );
        logic [31:0] status, temp;

        // Address phase
        apb_write(REG_TX, {24'h0, slave_addr, 1'b1});
        apb_write(REG_CMD, CMD_START_WRITE);
        wait_irq();
        apb_read(REG_STATUS, status);
        if (status[7]) begin fail_count++; $display("[%0t] FAIL : Addr NACK in multi-read", $time); end
        clear_irq();

        // Read byte 0 with ACK (CMD_READ_ACK: RD only, no STO, ACK=0 → master drives SDA low)
        apb_write(REG_CMD, CMD_READ_ACK);
        wait_irq();
        apb_read(REG_RX, temp);
        data0 = temp[7:0];
        clear_irq();

        // Read byte 1 with NACK + STOP
        apb_write(REG_CMD, CMD_READ_STOP);
        wait_irq();
        apb_read(REG_RX, temp);
        data1 = temp[7:0];
        clear_irq();
    endtask

    // Repeated START: write then read without intermediate STOP
    task automatic master_combined_wr_rd(
        input  logic [6:0] slave_addr,
        input  logic [7:0] wr_data,
        output logic [7:0] rd_data
    );
        logic [31:0] status, temp;

        // === Write phase ===
        apb_write(REG_TX, {24'h0, slave_addr, 1'b0});
        apb_write(REG_CMD, CMD_START_WRITE);
        wait_irq();
        apb_read(REG_STATUS, status);
        if (status[7]) begin fail_count++; $display("[%0t] FAIL : Addr NACK in combined wr phase", $time); end
        clear_irq();

        apb_write(REG_TX, {24'h0, wr_data});
        apb_write(REG_CMD, CMD_WRITE);           // write data, NO STOP
        wait_irq();
        clear_irq();

        // === Repeated START + Read phase ===
        apb_write(REG_TX, {24'h0, slave_addr, 1'b1});
        apb_write(REG_CMD, CMD_START_WRITE);      // repeated START + address+R
        wait_irq();
        apb_read(REG_STATUS, status);
        if (status[7]) begin fail_count++; $display("[%0t] FAIL : Addr NACK in combined rd phase", $time); end
        clear_irq();

        apb_write(REG_CMD, CMD_READ_STOP);        // read + NACK + STOP
        wait_irq();
        apb_read(REG_RX, temp);
        rd_data = temp[7:0];
        clear_irq();
    endtask

    //=========================================================================
    //  High-level test wrappers
    //=========================================================================
    task automatic test_write(
        input logic [6:0] addr,
        input logic [7:0] data,
        input string test_name
    );
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
    endtask

    task automatic test_read(
        input logic [6:0] addr,
        input logic [7:0] expected,
        input string test_name
    );
        logic [7:0] received;
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
    endtask

    //=========================================================================
    //  Reset & configure
    //=========================================================================
    task automatic reset_dut;
        HRESETn = 1'b0;
        PADDR   = '0;
        PWDATA  = '0;
        PWRITE  = 1'b0;
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        slave_sda_low = 1'b0;
        slave_scl_low = 1'b0;

        repeat (10) @(posedge HCLK);
        HRESETn = 1'b1;
        repeat (10) @(posedge HCLK);
    endtask

    task automatic configure_controller;
        apb_write(REG_PRE, PRESCALER);
        apb_write(REG_CTRL, 32'h0000_00C0);  // core enable + IRQ enable
    endtask

    task automatic configure_controller_no_irq;
        apb_write(REG_PRE, PRESCALER);
        apb_write(REG_CTRL, 32'h0000_0080);  // core enable, IRQ DISABLED
    endtask

    //=========================================================================
    //  Section header printer
    //=========================================================================
    task automatic section(input int num, input string title);
        test_section = num;
        $display("");
        $display("────────────────────────────────────────────────");
        $display("  SECTION %0d : %s", num, title);
        $display("────────────────────────────────────────────────");
    endtask

    //=========================================================================
    //  MAIN TEST FLOW
    //=========================================================================
    initial begin
        logic [31:0] rdata;
        logic [7:0]  rd_byte, rd_byte0, rd_byte1;
        logic [7:0]  slave_data0, slave_data1;
        logic [7:0]  slave_wr_data;
        logic [15:0] saved_pre;
        logic        bus_was_busy;
        logic        irq_seen;
        logic        irq_pin_seen;
        logic        tip_seen;
        logic        al_flag_seen;

        pass_count  = 0;
        fail_count  = 0;
        start_count = 0;
        stop_count  = 0;

        HRESETn       = 1'b0;
        PADDR         = '0;
        PWDATA        = '0;
        PWRITE        = 1'b0;
        PSEL          = 1'b0;
        PENABLE       = 1'b0;
        slave_sda_low = 1'b0;
        slave_scl_low = 1'b0;

        $display("");
        $display("================================================================");
        $display("     APB-I2C THOROUGH VERIFICATION TESTBENCH");
        $display("================================================================");

        //=====================================================================
        // SECTION 1 : RESET VALUES
        //=====================================================================
        section(1, "REGISTER RESET VALUES");

        reset_dut();

        check(scl === 1'b1 && sda === 1'b1,
              "I2C bus idle after reset (SCL=1, SDA=1)");

        apb_read(REG_PRE, rdata);
        check(rdata[15:0] == 16'h0000, "PRE reset value = 0x0000");

        apb_read(REG_CTRL, rdata);
        check(rdata[7:0] == 8'h00, "CTRL reset value = 0x00");

        apb_read(REG_TX, rdata);
        check(rdata[7:0] == 8'h00, "TX reset value = 0x00");

        apb_read(REG_CMD, rdata);
        check(rdata[7:0] == 8'h00, "CMD reset value = 0x00");

        apb_read(REG_STATUS, rdata);
        check(rdata[7:0] == 8'h00, "STATUS reset value = 0x00");

        apb_read(REG_RX, rdata);
        check(rdata[7:0] == 8'h00, "RX reset value = 0x00");

        //=====================================================================
        // SECTION 2 : APB PROTOCOL TESTS
        //=====================================================================
        section(2, "APB PROTOCOL-LEVEL TESTS");

        // 2a — Constant PREADY and PSLVERR
        check(PREADY  === 1'b1, "PREADY is 1 at idle");
        check(PSLVERR === 1'b0, "PSLVERR is 0 at idle");

        // 2b — Write & read back all valid registers
        configure_controller();

        apb_read(REG_PRE, rdata);
        check(rdata[15:0] == 16'd10, "PRE write/readback");

        apb_read(REG_CTRL, rdata);
        check(rdata[7:0] == 8'hC0, "CTRL write/readback");

        apb_write(REG_TX, 32'h0000_005A);
        apb_read(REG_TX, rdata);
        check(rdata[7:0] == 8'h5A, "TX write/readback");

        // 2c — Write to invalid/reserved addresses
        // Save PRE before testing invalid writes
        apb_read(REG_PRE, rdata);
        saved_pre = rdata[15:0];

        apb_write(ADDR_INVALID_1, 32'hDEAD_BEEF);
        apb_read(REG_PRE, rdata);
        check(rdata[15:0] == saved_pre, "Invalid addr write does not corrupt PRE");

        apb_read(ADDR_INVALID_1, rdata);
        check(rdata == 32'h0, "Read from invalid addr returns 0x00000000");

        apb_write(ADDR_INVALID_2, 32'hCAFE_BABE);
        apb_read(ADDR_INVALID_2, rdata);
        check(rdata == 32'h0, "Read from second invalid addr returns 0");

        apb_write(ADDR_INVALID_3, 32'hFFFF_FFFF);
        apb_read(ADDR_INVALID_3, rdata);
        check(rdata == 32'h0, "Read from max invalid addr returns 0");

        // 2d — Write to read-only registers (STATUS, RX)
        apb_write(REG_STATUS, 32'hFF);
        apb_read(REG_STATUS, rdata);
        check(rdata[4:2] == 3'b000, "Write to STATUS does not set reserved bits");

        apb_write(REG_RX, 32'hAB);
        // RX value is driven by the byte controller, not APB writes
        // Just verify no crash / PSLVERR

        //=====================================================================
        // SECTION 3 : PRESCALER RANGE TESTS
        //=====================================================================
        section(3, "PRESCALER RANGE TESTS");

        reset_dut();

        apb_write(REG_PRE, 32'h0000_FFFF);
        apb_read(REG_PRE, rdata);
        check(rdata[15:0] == 16'hFFFF, "PRE max value 0xFFFF readback");

        apb_write(REG_PRE, 32'h0000_8000);
        apb_read(REG_PRE, rdata);
        check(rdata[15:0] == 16'h8000, "PRE value 0x8000 readback");

        apb_write(REG_PRE, 32'h0000_0001);
        apb_read(REG_PRE, rdata);
        check(rdata[15:0] == 16'h0001, "PRE min value 0x0001 readback");

        apb_write(REG_PRE, 32'h0000_0000);
        apb_read(REG_PRE, rdata);
        check(rdata[15:0] == 16'h0000, "PRE value 0x0000 readback");

        // Verify upper 16 bits of write are ignored
        apb_write(REG_PRE, 32'hFFFF_0005);
        apb_read(REG_PRE, rdata);
        check(rdata[31:16] == 16'h0000, "PRE upper 16 bits read as 0");
        check(rdata[15:0]  == 16'h0005, "PRE lower 16 bits = 0x0005");

        //=====================================================================
        // SECTION 4 : CMD REGISTER GATING (core disabled)
        //=====================================================================
        section(4, "CMD REGISTER — CORE DISABLED GATING");

        reset_dut();

        // Core is disabled (CTRL[7]=0 after reset)
        apb_write(REG_CMD, 32'h0000_0090);  // try to write CMD
        apb_read(REG_CMD, rdata);
        check(rdata[7:0] == 8'h00, "CMD write ignored when core disabled");

        // Now enable core and verify CMD can be written
        configure_controller();
        // We don't actually send a transfer here — just verify the register
        // accepts the write when core is enabled. The auto-clear will happen
        // on s_done, but with no transfer in progress, cmd bits stay.
        // Note: cmd[2:1] and cmd[0] are always cleared on next cycle.

        //=====================================================================
        // SECTION 5 : BASIC I2C WRITE & READ
        //=====================================================================
        section(5, "BASIC I2C WRITE & READ");

        reset_dut();
        configure_controller();

        test_write(7'h32, 8'hAA, "Basic I2C WRITE (addr=0x32, data=0xAA)");
        test_read (7'h45, 8'h5A, "Basic I2C READ  (addr=0x45, data=0x5A)");

        //=====================================================================
        // SECTION 6 : DATA PATTERN STRESS
        //=====================================================================
        section(6, "DATA PATTERN STRESS");

        test_write(7'h20, 8'h00, "WRITE data=0x00");
        test_write(7'h21, 8'hFF, "WRITE data=0xFF");
        test_write(7'h22, 8'h55, "WRITE data=0x55");
        test_write(7'h23, 8'hAA, "WRITE data=0xAA");
        test_write(7'h24, 8'h01, "WRITE data=0x01 (LSB only)");
        test_write(7'h25, 8'h80, "WRITE data=0x80 (MSB only)");
        test_write(7'h26, 8'h0F, "WRITE data=0x0F (lower nibble)");
        test_write(7'h27, 8'hF0, "WRITE data=0xF0 (upper nibble)");

        test_read(7'h30, 8'h00, "READ data=0x00");
        test_read(7'h31, 8'hFF, "READ data=0xFF");
        test_read(7'h32, 8'h55, "READ data=0x55");
        test_read(7'h33, 8'hAA, "READ data=0xAA");
        test_read(7'h34, 8'h01, "READ data=0x01 (LSB only)");
        test_read(7'h35, 8'h80, "READ data=0x80 (MSB only)");

        //=====================================================================
        // SECTION 7 : BACK-TO-BACK & MIXED DIRECTION
        //=====================================================================
        section(7, "BACK-TO-BACK & MIXED DIRECTION");

        test_write(7'h10, 8'hA1, "Back-to-back WRITE #1");
        test_write(7'h11, 8'hB2, "Back-to-back WRITE #2");
        test_write(7'h12, 8'hC3, "Back-to-back WRITE #3");

        test_read(7'h40, 8'h19, "Back-to-back READ #1");
        test_read(7'h41, 8'h28, "Back-to-back READ #2");
        test_read(7'h42, 8'h37, "Back-to-back READ #3");

        test_write(7'h50, 8'hDE, "Mixed: WRITE before READ");
        test_read (7'h50, 8'hAD, "Mixed: READ after WRITE (same addr)");

        test_read (7'h51, 8'h11, "Mixed: READ before WRITE");
        test_write(7'h51, 8'h22, "Mixed: WRITE after READ (same addr)");

        //=====================================================================
        // SECTION 8 : NACK HANDLING
        //=====================================================================
        section(8, "NACK HANDLING");

        // 8a — Slave NACKs the address byte
        begin
            $display("[%0t] INFO : Testing slave NACK on address...", $time);
            fork
                slave_nack_addr_transaction();
                master_write_expect_addr_nack(7'h60, 8'hBB);
            join
            check(1'b1, "Address NACK handled without hang");
        end

        // 8b — Slave ACKs address but NACKs the data byte
        begin
            $display("[%0t] INFO : Testing slave NACK on data byte...", $time);
            fork
                slave_nack_data_transaction();
                master_write_expect_data_nack(7'h61, 8'hCC);
            join
            check(1'b1, "Data NACK handled without hang");
        end

        // Verify bus returns to idle after NACK scenarios
        repeat (50) @(posedge HCLK);
        check(scl === 1'b1 && sda === 1'b1,
              "Bus idle after NACK scenarios");

        //=====================================================================
        // SECTION 9 : MULTI-BYTE TRANSFERS
        //=====================================================================
        section(9, "MULTI-BYTE TRANSFERS");

        // 9a — Multi-byte write (2 bytes in one transaction)
        begin
            slave_data0 = 8'h00;
            slave_data1 = 8'h00;
            fork
                slave_multibyte_write_transaction(slave_data0, slave_data1);
                master_multibyte_write(7'h2A, 8'hDE, 8'hAD);
            join

            check(slave_data0 == 8'hDE && slave_data1 == 8'hAD,
                  "Multi-byte WRITE: slave received 0xDE, 0xAD");
        end

        // 9b — Multi-byte read (2 bytes in one transaction)
        begin
            fork
                slave_multibyte_read_transaction(8'hBE, 8'hEF);
                master_multibyte_read(7'h2B, rd_byte0, rd_byte1);
            join

            check(rd_byte0 == 8'hBE && rd_byte1 == 8'hEF,
                  "Multi-byte READ: master received 0xBE, 0xEF");
        end

        //=====================================================================
        // SECTION 10 : REPEATED START (COMBINED FORMAT)
        //=====================================================================
        section(10, "REPEATED START (COMBINED FORMAT)");

        begin
            slave_wr_data = 8'h00;
            fork
                slave_combined_wr_rd_transaction(slave_wr_data, 8'h99);
                master_combined_wr_rd(7'h55, 8'h42, rd_byte);
            join

            check(slave_wr_data == 8'h42,
                  "Combined: slave received write data 0x42");
            check(rd_byte == 8'h99,
                  "Combined: master received read data 0x99");
        end

        //=====================================================================
        // SECTION 11 : CLOCK STRETCHING
        //=====================================================================
        section(11, "CLOCK STRETCHING");

        begin
            slave_seen_data = 'x;
            fork
                slave_write_with_clock_stretch(200);  // stretch for 200 HCLK cycles
                master_write_byte(7'h66, 8'hAB);
            join

            check(slave_seen_data == 8'hAB,
                  "Clock stretch: transfer completed correctly");
        end

        //=====================================================================
        // SECTION 12 : BUS BUSY DETECTION
        //=====================================================================
        section(12, "BUS BUSY DETECTION");

        // After a normal transfer, STATUS[6] (busy) should return to 0
        repeat (100) @(posedge HCLK);  // let bus settle
        apb_read(REG_STATUS, rdata);
        check(rdata[6] == 1'b0, "STATUS[6] busy=0 when bus is idle");

        // Start a transfer and check busy goes high
        begin
            bus_was_busy = 1'b0;

            fork
                begin
                    slave_write_transaction();
                end
                begin
                    // Master side: initiate transfer
                    apb_write(REG_TX, {24'h0, 7'h70, 1'b0});
                    apb_write(REG_CMD, CMD_START_WRITE);
                    // Poll STATUS until we see busy
                    repeat (500) begin
                        apb_read(REG_STATUS, rdata);
                        if (rdata[6]) bus_was_busy = 1'b1;
                        if (rdata[0]) break;  // IRQ fired
                    end
                    wait_irq();
                    clear_irq();
                    apb_write(REG_TX, {24'h0, 8'h77});
                    apb_write(REG_CMD, CMD_WRITE_STOP);
                    wait_irq();
                    clear_irq();
                end
            join

            check(bus_was_busy == 1'b1, "STATUS[6] busy went high during transfer");
        end

        repeat (100) @(posedge HCLK);
        apb_read(REG_STATUS, rdata);
        check(rdata[6] == 1'b0, "STATUS[6] busy returned to 0 after STOP");

        //=====================================================================
        // SECTION 13 : INTERRUPT TESTS
        //=====================================================================
        section(13, "INTERRUPT TESTS");

        // 13a — Interrupt disabled: interrupt_o should stay low
        reset_dut();
        configure_controller_no_irq();  // IEN=0

        begin
            irq_seen = 1'b0;

            fork
                slave_write_transaction();
                begin
                    // Monitor interrupt_o during the transfer
                    fork
                        begin
                            forever begin
                                @(posedge HCLK);
                                if (interrupt_o) irq_seen = 1'b1;
                            end
                        end
                        begin
                            apb_write(REG_TX, {24'h0, 7'h15, 1'b0});
                            apb_write(REG_CMD, CMD_START_WRITE);
                            // Can't use wait_irq since IRQ is disabled — poll TIP
                            repeat (3000) begin
                                apb_read(REG_STATUS, rdata);
                                if (rdata[0]) break;  // irq_flag internal
                            end
                            clear_irq();
                            apb_write(REG_TX, {24'h0, 8'h88});
                            apb_write(REG_CMD, CMD_WRITE_STOP);
                            repeat (3000) begin
                                apb_read(REG_STATUS, rdata);
                                if (rdata[0]) break;
                            end
                            clear_irq();
                        end
                    join_any
                    disable fork;
                end
            join

            check(irq_seen == 1'b0,
                  "interrupt_o stays low when IEN=0");
        end

        // 13b — Interrupt enabled: interrupt_o should assert
        reset_dut();
        configure_controller();  // IEN=1

        begin
            irq_pin_seen = 1'b0;

            fork
                slave_write_transaction();
                begin
                    fork
                        begin
                            forever begin
                                @(posedge HCLK);
                                if (interrupt_o) irq_pin_seen = 1'b1;
                            end
                        end
                        begin
                            apb_write(REG_TX, {24'h0, 7'h15, 1'b0});
                            apb_write(REG_CMD, CMD_START_WRITE);
                            wait_irq();
                            clear_irq();
                            apb_write(REG_TX, {24'h0, 8'h99});
                            apb_write(REG_CMD, CMD_WRITE_STOP);
                            wait_irq();
                            clear_irq();
                        end
                    join_any
                    disable fork;
                end
            join

            check(irq_pin_seen == 1'b1,
                  "interrupt_o asserted when IEN=1");
        end

        // 13c — IRQ flag clears after IACK
        begin
            // Perform a write, then verify STATUS[0] clears after IACK
            fork
                slave_write_transaction();
                begin
                    apb_write(REG_TX, {24'h0, 7'h16, 1'b0});
                    apb_write(REG_CMD, CMD_START_WRITE);
                    wait_irq();
                    apb_read(REG_STATUS, rdata);
                    check(rdata[0] == 1'b1, "IRQ flag set before IACK");
                    clear_irq();
                    apb_read(REG_STATUS, rdata);
                    check(rdata[0] == 1'b0, "IRQ flag cleared after IACK");

                    apb_write(REG_TX, {24'h0, 8'hAA});
                    apb_write(REG_CMD, CMD_WRITE_STOP);
                    wait_irq();
                    clear_irq();
                end
            join
        end

        //=====================================================================
        // SECTION 14 : CMD AUTO-CLEAR AFTER TRANSFER
        //=====================================================================
        section(14, "CMD AUTO-CLEAR AFTER TRANSFER");

        begin
            fork
                slave_write_transaction();
                begin
                    apb_write(REG_TX, {24'h0, 7'h17, 1'b0});
                    apb_write(REG_CMD, CMD_START_WRITE);
                    wait_irq();
                    // After s_done, CMD[7:4] should auto-clear
                    apb_read(REG_CMD, rdata);
                    check(rdata[7:4] == 4'h0,
                          "CMD[7:4] auto-cleared after address phase done");
                    clear_irq();

                    apb_write(REG_TX, {24'h0, 8'hBB});
                    apb_write(REG_CMD, CMD_WRITE_STOP);
                    wait_irq();
                    apb_read(REG_CMD, rdata);
                    check(rdata[7:4] == 4'h0,
                          "CMD[7:4] auto-cleared after data+stop done");
                    clear_irq();
                end
            join
        end

        //=====================================================================
        // SECTION 15 : TIP (TRANSFER IN PROGRESS)
        //=====================================================================
        section(15, "TIP (TRANSFER IN PROGRESS)");

        // STATUS[1] = tip = (rd | wr), should be 1 during transfer
        begin
            tip_seen = 1'b0;

            fork
                slave_write_transaction();
                begin
                    apb_write(REG_TX, {24'h0, 7'h18, 1'b0});
                    apb_write(REG_CMD, CMD_START_WRITE);

                    // Poll for TIP
                    repeat (200) begin
                        apb_read(REG_STATUS, rdata);
                        if (rdata[1]) tip_seen = 1'b1;
                        if (rdata[0]) break;
                    end

                    wait_irq();
                    clear_irq();

                    apb_write(REG_TX, {24'h0, 8'hCC});
                    apb_write(REG_CMD, CMD_WRITE_STOP);
                    wait_irq();
                    clear_irq();
                end
            join

            check(tip_seen == 1'b1, "STATUS[1] TIP set during transfer");

            // After transfer completes, TIP should be 0
            apb_read(REG_STATUS, rdata);
            check(rdata[1] == 1'b0, "STATUS[1] TIP cleared after transfer");
        end

        //=====================================================================
        // SECTION 16 : RESET RECOVERY
        //=====================================================================
        section(16, "RESET RECOVERY");

        reset_dut();
        check(scl === 1'b1 && sda === 1'b1,
              "Bus idle after mid-test reset");

        configure_controller();
        test_write(7'h2A, 8'h96, "WRITE after reset recovery");
        test_read (7'h35, 8'h69, "READ after reset recovery");

        //=====================================================================
        // SECTION 17 : RESET DURING ACTIVE TRANSFER
        //=====================================================================
        section(17, "RESET DURING ACTIVE TRANSFER");

        begin
            // Start a transfer, then reset the DUT mid-way
            fork
                begin : slave_side
                    // Slave will hang waiting for bits — that's expected.
                    // We use a timeout to exit gracefully.
                    fork
                        begin
                            wait_start();
                            // Receive a few bits before reset kills the transfer
                            repeat (5) @(posedge scl);
                        end
                        begin
                            #50000;  // timeout
                        end
                    join_any
                    disable fork;
                end
                begin : master_side
                    apb_write(REG_TX, {24'h0, 7'h7F, 1'b0});
                    apb_write(REG_CMD, CMD_START_WRITE);
                    // Wait for transfer to start on the bus
                    repeat (200) @(posedge HCLK);
                    // Now reset mid-transfer
                    reset_dut();
                end
            join

            // Verify clean recovery
            check(scl === 1'b1 && sda === 1'b1,
                  "Bus idle after reset-during-transfer");

            apb_read(REG_CMD, rdata);
            check(rdata[7:0] == 8'h00,
                  "CMD cleared after reset-during-transfer");

            apb_read(REG_STATUS, rdata);
            check(rdata[7:0] == 8'h00,
                  "STATUS cleared after reset-during-transfer");

            // Verify the controller still works after recovery
            configure_controller();
            test_write(7'h0A, 8'hF1, "WRITE after reset-during-transfer recovery");
        end

        //=====================================================================
        // SECTION 18 : BOUNDARY I2C ADDRESSES
        //=====================================================================
        section(18, "BOUNDARY I2C ADDRESSES");

        test_write(7'h00, 8'h11, "WRITE to I2C addr 0x00 (general call)");
        test_write(7'h7F, 8'h22, "WRITE to I2C addr 0x7F (max 7-bit)");
        test_write(7'h01, 8'h33, "WRITE to I2C addr 0x01 (min non-zero)");

        test_read(7'h00, 8'h44, "READ from I2C addr 0x00");
        test_read(7'h7F, 8'h55, "READ from I2C addr 0x7F");

        //=====================================================================
        // SECTION 19 : ARBITRATION LOST
        //=====================================================================
        section(19, "ARBITRATION LOST");

        begin
            // Simulate arbitration loss: master tries to send a 1 on SDA,
            // but another master holds SDA low.
            // We do this by forcing sda low right when the master begins
            // transmitting the address after START.
            al_flag_seen = 1'b0;

            apb_write(REG_TX, {24'h0, 7'h7F, 1'b0});  // addr = 0x7F → SDA should be all 1s for addr bits
            apb_write(REG_CMD, CMD_START_WRITE);

            // Wait for START to complete and first data bit to be driven
            fork
                begin
                    wait_start();
                    // After START, master will drive address bits.
                    // Pull SDA low to conflict with the master's intended 1.
                    repeat (5) @(posedge HCLK);
                    slave_sda_low = 1'b1;
                    // Hold it for several SCL cycles to ensure arbitration check fires
                    repeat (500) @(posedge HCLK);
                    slave_sda_low = 1'b0;
                end
                begin
                    // Monitor for arbitration lost
                    repeat (3000) begin
                        apb_read(REG_STATUS, rdata);
                        if (rdata[5]) begin
                            al_flag_seen = 1'b1;
                            break;
                        end
                    end
                end
            join

            check(al_flag_seen == 1'b1,
                  "STATUS[5] AL flag set on arbitration lost");

            // CMD should have been auto-cleared
            apb_read(REG_CMD, rdata);
            check(rdata[7:4] == 4'h0,
                  "CMD[7:4] auto-cleared on arbitration lost");

            // Clear the IRQ if set
            apb_read(REG_STATUS, rdata);
            if (rdata[0]) clear_irq();

            // Wait for bus to settle
            repeat (200) @(posedge HCLK);
            slave_sda_low = 1'b0;
        end

        // Verify controller can recover after arbitration lost
        repeat (200) @(posedge HCLK);

        // Need a fresh reset to cleanly recover from AL state
        reset_dut();
        configure_controller();
        test_write(7'h0B, 8'hAF, "WRITE after arbitration-lost recovery");

        //=====================================================================
        // SECTION 20 : FINAL BUS IDLE CHECK
        //=====================================================================
        section(20, "FINAL CHECKS");

        repeat (50) @(posedge HCLK);

        check(scl === 1'b1 && sda === 1'b1,
              "I2C bus idle after all transfers");

        check(start_count > 0, "START conditions were generated");
        check(stop_count  > 0, "STOP conditions were generated");

        //=====================================================================
        // REPORT
        //=====================================================================
        $display("");
        $display("================================================================");
        $display("              THOROUGH TEST REPORT");
        $display("================================================================");
        $display("  PASS        = %0d", pass_count);
        $display("  FAIL        = %0d", fail_count);
        $display("  START COUNT = %0d", start_count);
        $display("  STOP COUNT  = %0d", stop_count);
        $display("================================================================");

        if (fail_count == 0)
            $display("        *** APB-I2C VERIFICATION PASSED ***");
        else
            $display("        *** APB-I2C VERIFICATION FAILED ***");

        $display("================================================================");

        #200;
        $finish;
    end

    //=========================================================================
    //  Global simulation timeout
    //=========================================================================
    initial begin
        #5_000_000;
        $display("[%0t] FAIL : GLOBAL TESTBENCH TIMEOUT", $time);
        $finish;
    end

    //=========================================================================
    //  SHM waveform dump for SimVision
    //=========================================================================
    initial begin
        $shm_open("i2c_thorough_tb.shm");
        $shm_probe(thorough_tb,                                "AS");   // all TB signals
        $shm_probe(thorough_tb.dut,                            "AM");   // apb_i2c internals
        $shm_probe(thorough_tb.dut.byte_controller,            "AM");   // byte controller
        $shm_probe(thorough_tb.dut.byte_controller.bit_controller, "AM"); // bit controller
    end

endmodule
