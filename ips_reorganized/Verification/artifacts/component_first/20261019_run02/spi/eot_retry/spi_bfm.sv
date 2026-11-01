`timescale 1ns/1ps

module apb_master_bfm #(
  parameter APB_ADDR_WIDTH = 12
) (
  input  logic                     HCLK,
  input  logic                     HRESETn,
  output logic [APB_ADDR_WIDTH-1:0] PADDR,
  output logic [31:0]              PWDATA,
  output logic                     PWRITE,
  output logic                     PSEL,
  output logic                     PENABLE,
  input  logic [31:0]              PRDATA,
  input  logic                     PREADY
);
  task automatic idle_bus;
    begin
      PADDR   = '0;
      PWDATA  = '0;
      PWRITE  = 1'b0;
      PSEL    = 1'b0;
      PENABLE = 1'b0;
    end
  endtask

  task automatic apb_write(input logic [APB_ADDR_WIDTH-1:0] addr, input logic [31:0] data);
    begin
      @(posedge HCLK); #1;
      PADDR   = addr;
      PWDATA  = data;
      PWRITE  = 1'b1;
      PSEL    = 1'b1;
      PENABLE = 1'b0;
      @(posedge HCLK); #1;
      PENABLE = 1'b1;
      wait (PREADY === 1'b1);
      @(posedge HCLK); #1;
      PSEL    = 1'b0;
      PENABLE = 1'b0;
      PWRITE  = 1'b0;
      PADDR   = '0;
      PWDATA  = '0;
    end
  endtask

  task automatic apb_read(input logic [APB_ADDR_WIDTH-1:0] addr, output logic [31:0] data);
    begin
      @(posedge HCLK); #1;
      PADDR   = addr;
      PWRITE  = 1'b0;
      PSEL    = 1'b1;
      PENABLE = 1'b0;
      @(posedge HCLK); #1;
      PENABLE = 1'b1;
      wait (PREADY === 1'b1);
      data = PRDATA;
      @(posedge HCLK); #1;
      PSEL    = 1'b0;
      PENABLE = 1'b0;
      PADDR   = '0;
    end
  endtask
endmodule