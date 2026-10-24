// =============================================================================
// RISCFORGE 1TOPS — First-Fatal Diagnostic Failure Reporter (failure_reporter.sv)
// =============================================================================

`timescale 1ns/1ps

module failure_reporter import tb_pkg::*; (
  input logic clk,
  input logic rst_n,
  output logic freeze_monitors
);

  logic first_fatal_latched;
  int   failing_layer;
  string failing_check_id;
  string error_message;
  longint unsigned fail_cycle;

  // Total number of fatal checks that fired. The anti-vacuity guard in
  // soc_tb_top requires n_find == 0 before it will honour a firmware PASS:
  // a run that quietly tripped a checker and then reported PASS must not be
  // counted as green.
  int unsigned n_find;

  initial begin
    first_fatal_latched = 1'b0;
    freeze_monitors     = 1'b0;
    failing_layer       = 0;
    failing_check_id    = "";
    error_message       = "";
    fail_cycle          = 0;
    n_find              = 0;
  end

  task automatic report_failure(
    input int    layer,
    input string check_id,
    input string msg,
    input logic [31:0] failing_pc = 32'h0
  );
    n_find++;
    if (!first_fatal_latched) begin
      first_fatal_latched = 1'b1;
      freeze_monitors     = 1'b1;
      failing_layer       = layer;
      failing_check_id    = check_id;
      error_message       = msg;
      fail_cycle          = $time / 10; // assuming 10ns clock

      $display("\n================================================================================");
      $display("                 RISCFORGE SoC VERIFICATION FAILURE REPORT                      ");
      $display("================================================================================");
      $display("  FATAL CHECK ID   : %s", check_id);
      $display("  BLAME LAYER      : %0d (1:Protocol, 2:Path, 3:Reg, 4:Pin, 5:IRQ, 6:Firmware)", layer);
      $display("  SIMULATION TIME  : %0t (Cycle ~%0d)", $time, fail_cycle);
      $display("  FAILING PC       : 0x%08X", failing_pc);
      $display("  DETAILS          : %s", msg);
      $display("  FATALS RECORDED  : %0d", n_find);
      $display("================================================================================\n");

      // Write failure summary to failure_report.md
      begin
        int fd = $fopen("failure_report.md", "w");
        if (fd) begin
          $fdisplay(fd, "# RISCFORGE SoC Verification Failure Report\n");
          $fdisplay(fd, "| Parameter | Value |");
          $fdisplay(fd, "|:---|:---|");
          $fdisplay(fd, "| **Status** | `FAILED` |");
          $fdisplay(fd, "| **Check ID** | `%s` |", check_id);
          $fdisplay(fd, "| **Layer** | `%0d` |", layer);
          $fdisplay(fd, "| **Cycle** | `%0d` |", fail_cycle);
          $fdisplay(fd, "| **Failing PC** | `0x%08X` |", failing_pc);
          $fdisplay(fd, "\n### Error Summary\n> %s\n", msg);
          $fclose(fd);
        end
      end
    end else begin
      $display("[FATAL #%0d] %s (layer %0d): %s", n_find, check_id, layer, msg);
    end
  endtask

endmodule
