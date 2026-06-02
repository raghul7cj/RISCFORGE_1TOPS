`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: clic
//
// Description:
//  Dummy stub Core Local Interrupt Controller (CLIC) module.
//  Preserves all parameter and port signatures for interface compatibility.
//
//////////////////////////////////////////////////////////////////////////////////

module clic #(
  parameter type reg_req_t = logic,
  parameter type reg_rsp_t = logic,
  parameter int  N_SOURCE = 256,
  parameter int  INTCTLBITS = 8,
  parameter bit  SSCLIC = 0,
  parameter bit  USCLIC = 0,
  parameter bit  VSCLIC = 0,
  parameter int unsigned N_VSCTXTS = 0,
  parameter bit  VSPRIO = 0,
  parameter int  VSPRIO_W = 1,
  localparam int SRC_W = (N_SOURCE > 1) ? $clog2(N_SOURCE) : 1
)(
  input logic        clk_i,
  input logic        rst_ni,

  // Bus Interface (device)
  input reg_req_t    reg_req_i,
  output reg_rsp_t   reg_rsp_o,

  // Interrupt Sources
  input [N_SOURCE-1:0] intr_src_i,

  // Interrupt notification to core
  output logic              irq_valid_o,
  input  logic              irq_ready_i,
  output logic [SRC_W-1:0]  irq_id_o,
  output logic [7:0]        irq_level_o,
  output logic              irq_shv_o,
  output logic [1:0]        irq_priv_o,
  output logic [2:0]        irq_vsid_o,
  output logic              irq_v_o,
  output logic              irq_kill_req_o,
  input  logic              irq_kill_ack_i
);

  assign reg_rsp_o       = '0;
  assign irq_valid_o     = 1'b0;
  assign irq_id_o        = '0;
  assign irq_level_o     = 8'b0;
  assign irq_shv_o       = 1'b0;
  assign irq_priv_o      = 2'b0;
  assign irq_vsid_o      = 3'b0;
  assign irq_v_o         = 1'b0;
  assign irq_kill_req_o  = 1'b0;

endmodule
