`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : axi_lite_dummy_slave
// Description : Simple Zero-Latency AXI4-Lite Slave Stub (No internal memory array).
//               Responds to read/write transactions immediately to prevent stalls.
//////////////////////////////////////////////////////////////////////////////////

module axi_lite_dummy_slave (
    input             clk,
    input             rst_n,

    // ── Write Address Channel ──────────────────────────────────────────
    input      [31:0] s_axi_awaddr,
    input             s_axi_awvalid,
    output            s_axi_awready,

    // ── Write Data Channel ─────────────────────────────────────────────
    input      [31:0] s_axi_wdata,
    input      [3:0]  s_axi_wstrb,
    input             s_axi_wvalid,
    output            s_axi_wready,

    // ── Write Response Channel ─────────────────────────────────────────
    output reg [1:0]  s_axi_bresp,
    output reg        s_axi_bvalid,
    input             s_axi_bready,

    // ── Read Address Channel ───────────────────────────────────────────
    input      [31:0] s_axi_araddr,
    input             s_axi_arvalid,
    output            s_axi_arready,

    // ── Read Data Channel ──────────────────────────────────────────────
    output reg [31:0] s_axi_rdata,
    output reg [1:0]  s_axi_rresp,
    output reg        s_axi_rvalid,
    input             s_axi_rready
);

    // Assert ready immediately when valid is high (zero latency handshakes)
    assign s_axi_awready = 1'b1;
    assign s_axi_wready  = 1'b1;
    assign s_axi_arready = 1'b1;

    // Internal mock registers (4 x 32-bit registers)
    reg [31:0] slave_regs [0:3];

    // Write Response Handshake & Register Write
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            slave_regs[0] <= 32'h0;
            slave_regs[1] <= 32'h0;
            slave_regs[2] <= 32'h0;
            slave_regs[3] <= 32'h0;
        end else begin
            if (s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00; // OKAY
                if (s_axi_wstrb[0]) slave_regs[s_axi_awaddr[3:2]][7:0]   <= s_axi_wdata[7:0];
                if (s_axi_wstrb[1]) slave_regs[s_axi_awaddr[3:2]][15:8]  <= s_axi_wdata[15:8];
                if (s_axi_wstrb[2]) slave_regs[s_axi_awaddr[3:2]][23:16] <= s_axi_wdata[23:16];
                if (s_axi_wstrb[3]) slave_regs[s_axi_awaddr[3:2]][31:24] <= s_axi_wdata[31:24];
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // Read Response Handshake (returns stored register value)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= 2'b00;
            s_axi_rdata  <= 32'h0;
        end else begin
            if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00; // OKAY
                s_axi_rdata  <= slave_regs[s_axi_araddr[3:2]];
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
