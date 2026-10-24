`timescale 1ns/1ps

module tb_apb_timeout_monitor;
  localparam int unsigned TIMEOUT_CYCLES = 3;
  localparam logic [31:0] TIMEOUT_DATA = 32'hDEAD_BEEF;

  typedef struct packed {
    logic psel;
    logic penable;
  } apb_req_t;

  typedef struct packed {
    logic        pready;
    logic [31:0] prdata;
    logic        pslverr;
  } apb_resp_t;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  apb_req_t req;
  apb_resp_t slave_resp, bridge_resp;
  logic timeout_pulse, timeout_sticky;
  int unsigned checks = 0;
  int unsigned failures = 0;

  always #5 clk = ~clk;

  apb_timeout_monitor #(
    .apb_req_t(apb_req_t),
    .apb_resp_t(apb_resp_t),
    .TimeoutCycles(TIMEOUT_CYCLES),
    .TimeoutData(TIMEOUT_DATA)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .apb_req_i(req),
    .apb_resp_slv_i(slave_resp),
    .apb_resp_mst_o(bridge_resp),
    .timeout_pulse_o(timeout_pulse),
    .timeout_sticky_o(timeout_sticky)
  );

  task automatic check(input string name, input logic condition);
    checks++;
    if (condition !== 1'b1) begin
      failures++;
      $display("CHECK_FAIL %s", name);
    end else begin
      $display("CHECK_PASS %s", name);
    end
  endtask

  task automatic reset_dut;
    @(negedge clk);
    rst_n = 1'b0;
    req = '0;
    slave_resp = '{pready: 1'b1, prdata: 32'h1234_5678, pslverr: 1'b0};
    repeat (2) @(posedge clk);
    #1;
    check("reset clears status", !timeout_pulse && !timeout_sticky);
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  initial begin
    req = '0;
    slave_resp = '0;
    reset_dut();

    // A ready slave remains transparent, including payload and error status.
    @(negedge clk);
    req = '{psel: 1'b1, penable: 1'b1};
    slave_resp = '{pready: 1'b1, prdata: 32'hCAFE_1234, pslverr: 1'b0};
    #1;
    check("ready response passes through", bridge_resp == slave_resp);
    check("ready response no timeout", !timeout_pulse && !timeout_sticky);
    @(negedge clk);
    req = '0;

    // Completion before the threshold must keep the slave's response.
    @(negedge clk);
    req = '{psel: 1'b1, penable: 1'b1};
    slave_resp = '{pready: 1'b0, prdata: 32'h1111_2222, pslverr: 1'b0};
    repeat (2) @(posedge clk);
    @(negedge clk);
    slave_resp.pready = 1'b1;
    slave_resp.prdata = 32'h3333_4444;
    #1;
    check("pre-threshold completion passes", bridge_resp == slave_resp);
    check("pre-threshold completion no timeout", !timeout_pulse && !timeout_sticky);
    @(negedge clk);
    req = '0;

    // Hold an ACCESS phase unanswered until the configured threshold.
    @(negedge clk);
    req = '{psel: 1'b1, penable: 1'b1};
    slave_resp = '{pready: 1'b0, prdata: 32'hAAAA_5555, pslverr: 1'b0};
    repeat (2) @(posedge clk);
    #1;
    check("timeout pulse asserted", timeout_pulse);
    check("timeout response forces ready", bridge_resp.pready);
    check("timeout response sets slverr", bridge_resp.pslverr);
    check("timeout response uses sentinel", bridge_resp.prdata == TIMEOUT_DATA);
    @(posedge clk);
    #1;
    check("timeout becomes sticky", timeout_sticky);

    // Model the bridge accepting the injected response by dropping PSEL.
    @(negedge clk);
    req = '0;
    slave_resp.pready = 1'b1;
    #1;
    check("pulse clears after access", !timeout_pulse);
    @(posedge clk);
    #1;
    check("sticky survives access", timeout_sticky);

    reset_dut();
    check("reset clears sticky", !timeout_sticky);

    if (failures == 0) begin
      $display("TEST_PASS checks=%0d", checks);
    end else begin
      $display("TEST_FAIL checks=%0d failures=%0d", checks, failures);
      $fatal(1, "APB timeout monitor test failed");
    end
    $finish;
  end

  initial begin
    #10000;
    $display("TEST_FAIL watchdog");
    $fatal(1, "APB timeout monitor test watchdog");
  end
endmodule
