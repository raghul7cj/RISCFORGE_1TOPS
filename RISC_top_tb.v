`timescale 1ns / 1ps
`include"RISC_top.v"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.01.2026 13:31:10
// Design Name: 
// Module Name: RISC_top_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module RISC_top_tb();

 reg clk,rst;
 wire [31:0] PC_next1,PC1; //PC
 wire [31:0] A_i1,RD_i1;  //instruction memory 
 wire [31:0] A11,A21,A31,WD31,RD11,RD21,WE31;   //Register file
 wire [31:0] operand11,operand21,alu_result1;  //ALU
 wire [31:0] alu_r1;
 wire [3:0] ctrl1,flags1;
 wire ALUSrc1;//,ALUControl1;
 wire WE1;   //data memory
 wire [31:0] A_d1,WD_d1,RD_d1;
 //wire [31:0] pc_target_jalr1;     //JALR wire to PC next mux
 wire [31:0] pc_plus1;       //pc+4 wire to PC next mux
 //wire [31:0] pc_target11;     //pc target/branch wire to PC next mux
 wire  [31:0] Imm_Ext1;   //Extension unit
 wire  [1:0] ImmSrc1;
 wire  LUISrc1;   
 wire isLUI1;          //LUI Unit
 wire isJALR1;
 wire [31:0] pc_target_jb1;
 wire  [31:0] lui_result1;
 wire   PCSrc1;            //PC mux
 wire  [31:0] result1;  //result mux
 wire  [1:0] ResultSrc1;
 wire  [31:0] in_l1,out_l1;   //load unit
// wire  [2:0] ctrl_l1;
 wire [3:0] strobe1;
RISC_top dut(
    .rst(rst),
    .clk(clk),
    .PC_next1(PC_next1),.PC1(PC1), //PC
    .A_i1(A_i1),.RD_i1(RD_i1),  //instruction memory 
    .A11(A11),.A21(A21),.A31(A31),.WD31(WD31),.RD11(RD11),.RD21(RD21),.WE31(WE31),   //Register file
    .operand11(operand11),.operand21(operand21),.alu_result1(alu_result1),  //ALU
    .alu_r1(alu_r1),
    .ctrl1(ctrl1),.flags1(flags1),
    .ALUSrc1(ALUSrc1),//.ALUControl1(ALUControl1),
    .WE1(WE1),   //data memory
    .A_d1(A_d1),.WD_d1(WD_d1),.RD_d1(RD_d1),
   // .pc_target_jalr1(pc_target_jalr1),     //JALR wire to PC next mux
    .pc_plus1(pc_plus1),       //pc+4 wire to PC next mux
   // .pc_target11(pc_target11),     //pc target/branch wire to PC next mux
    .Imm_Ext1(Imm_Ext1),    //Extension unit
    .ImmSrc1(ImmSrc1),
    .LUISrc1(LUISrc1),             //LUI Unit
    .isLUI1(isLUI1),
    .isJALR1(isJALR1),
    .pc_target_jb1(pc_target_jb1),
    .lui_result1(lui_result1),
    .PCSrc1(PCSrc1),            //PC mux
    .result1(result1),  //result mux
    .ResultSrc1(ResultSrc1),
    .in_l1(in_l1),.out_l1(out_l1),   //load unit
  //  .ctrl_l1(ctrl_l1),
    .strobe1(strobe1));
    
    
    initial 
    begin
    clk=1'b1;
    rst=1'b1;
    end
    
    always
    begin
    #5 clk=~clk;
    end
         
    integer i;   
initial
begin
    $dumpfile("RISC_Core.vcd");
    $dumpvars(0,RISC_top_tb);
    #0 rst=1'b0;
    #32 rst=1'b1;
    #250 dump_registers;   // print register values
    #10  $finish;
end

initial
begin
    #260;
    for (i = 0; i < 32; i = i + 1)
    $dumpvars(0, dut.register_file.Register[i]);
end

    task dump_registers;
begin
    $display("\n==================================================");
    $display("                RISC-V REGISTER DUMP");
    $display("==================================================");
    $display("Reg   ABI      Value (Hex)");
    $display("--------------------------------------------------");

    $display("x0   zero    %h", dut.register_file.Register[0]);
    $display("x1   ra      %h", dut.register_file.Register[1]);
    $display("x2   sp      %h", dut.register_file.Register[2]);
    $display("x3   gp      %h", dut.register_file.Register[3]);
    $display("x4   tp      %h", dut.register_file.Register[4]);
    $display("x5   t0      %h", dut.register_file.Register[5]);
    $display("x6   t1      %h", dut.register_file.Register[6]);
    $display("x7   t2      %h", dut.register_file.Register[7]);
    $display("x8   s0/fp   %h", dut.register_file.Register[8]);
    $display("x9   s1      %h", dut.register_file.Register[9]);
    $display("x10  a0      %h", dut.register_file.Register[10]);
    $display("x11  a1      %h", dut.register_file.Register[11]);
    $display("x12  a2      %h", dut.register_file.Register[12]);
    $display("x13  a3      %h", dut.register_file.Register[13]);
    $display("x14  a4      %h", dut.register_file.Register[14]);
    $display("x15  a5      %h", dut.register_file.Register[15]);
    $display("x16  a6      %h", dut.register_file.Register[16]);
    $display("x17  a7      %h", dut.register_file.Register[17]);
    $display("x18  s2      %h", dut.register_file.Register[18]);
    $display("x19  s3      %h", dut.register_file.Register[19]);
    $display("x20  s4      %h", dut.register_file.Register[20]);
    $display("x21  s5      %h", dut.register_file.Register[21]);
    $display("x22  s6      %h", dut.register_file.Register[22]);
    $display("x23  s7      %h", dut.register_file.Register[23]);
    $display("x24  s8      %h", dut.register_file.Register[24]);
    $display("x25  s9      %h", dut.register_file.Register[25]);
    $display("x26  s10     %h", dut.register_file.Register[26]);
    $display("x27  s11     %h", dut.register_file.Register[27]);
    $display("x28  t3      %h", dut.register_file.Register[28]);
    $display("x29  t4      %h", dut.register_file.Register[29]);
    $display("x30  t5      %h", dut.register_file.Register[30]);
    $display("x31  t6      %h", dut.register_file.Register[31]);

    $display("==================================================\n");
end
endtask







endmodule
