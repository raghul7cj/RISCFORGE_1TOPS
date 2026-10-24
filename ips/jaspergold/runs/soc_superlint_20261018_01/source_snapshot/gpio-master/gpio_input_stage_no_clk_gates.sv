module gpio_input_stage #(
  parameter NrSyncStages=2
) (
   input logic  clk_i,
   input logic  rst_ni,
   input logic  en_i,
   input logic  serial_i,
   output logic r_edge_o,
   output logic f_edge_o,
   output logic serial_o
);

  logic         serial, serial_q;

  assign serial_o =  serial_q;
  // The edge outputs are qualified with en_i. Unlike the clock-gated version of
  // this stage, the synchronizer here keeps running while the GPIO is disabled
  // while serial_q stays frozen, so without this qualifier the edge outputs
  // stay asserted for as long as the pin differs from the frozen sample. That
  // raises interrupts on a disabled GPIO and holds global_interrupt_o high
  // instead of pulsing it.
  assign f_edge_o = en_i & (~serial) & serial_q;
  assign r_edge_o = en_i & serial & (~serial_q);

  sync #(
    .STAGES (NrSyncStages)
  ) i_sync (
    .clk_i(clk_i),
    .rst_ni,
    .serial_i,
    .serial_o ( serial )
  );

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      serial_q <= 1'b0;
    end else begin
      if (en_i) begin
        serial_q <= serial;
      end
    end
  end


endmodule : gpio_input_stage
