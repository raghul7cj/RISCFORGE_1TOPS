`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.01.2026 14:36:50
// Design Name: 
// Module Name: instruction_memory
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


module instruction_memory(
  input rst,
  input [29:0] A,
  output [31:0] RD);

  reg [31:0] mem [4095:0];
  
  assign RD = (~rst) ? {32{1'b0}} : mem[A];

  initial begin
    $readmemh("firmware.mem", mem);
  end



  initial begin
    //mem[0]=32'h01C02303;
   // mem[0] = 32'hFFC4A303;
    //mem[1] = 32'h00832383;
     //mem[0] = 32'h0064A423;
     //mem[1] = 32'h00B62423;
   // mem[0] = 32'h0062E233;
    // mem[1] = 32'h00B62423;
    
    //.....Below are R type Arithematic instructions 
    /*
    mem[0]=32'h002081B3;
    mem[1]=32'h40118233;
    mem[2]=32'h002092B3;
    mem[3]=32'h0020A333;
    mem[4]=32'h0020B3B3;
    mem[5]=32'h0020C433;
    mem[6]=32'h0020D4B3;
    mem[7]=32'h4020D533;
    mem[8]=32'h0020E5B3;
    mem[9]=32'h0020F633;
    */
    
    //....Below are I type Arithematic instructions
   /* 
    mem[0]=32'h00A08193;
    mem[1]=32'h0050A213;
    mem[2]=32'h0050B293;
    mem[3]=32'h00F0C313;
    mem[4]=32'h00F0E393;
    mem[5]=32'h00F0F413;
    mem[6]=32'h00309493;
    mem[7]=32'h0030D513;
    mem[8]=32'h4030D593;
   // mem[9]=32'h0020F633;
   
   */
   /*
   //.......test code for branch......
   
 mem[0]=32'h00000193;  // addi x3, x0, 0
 mem[1]=32'h00500093;  // addi x1, x0, 5
 mem[2]=32'h00500113;  // addi x2, x0, 5
 
 mem[3]=32'h00208463;  // beq  x1,x2,+8
 mem[4]=32'hF9C18193;  // addi x3,x3,-100
 mem[5]=32'h00118193;  // addi x3,x3,1
 
 mem[6]=32'h00209663;  // bne  x1,x2,+12
 mem[7]=32'h00118193;  // addi x3,x3,1
 mem[8]=32'h0080006F;  // jal  x0,+8
 mem[9]=32'hF9C18193;  // addi x3,x3,-100
 mem[10]=32'h00118193;  // addi x3,x3,1
 
 mem[11]=32'hFFB00093;  // addi x1,x0,-5
 mem[12]=32'h00300113;  // addi x2,x0,3
 
 mem[13]=32'h0020C463;  // blt  x1,x2,+8
 mem[14]=32'hF9C18193;  // addi x3,x3,-100
 mem[15]=32'h00118193;  // addi x3,x3,1
 
 mem[16]=32'h0020D663;  // bge  x1,x2,+12
 mem[17]=32'h00118193;  // addi x3,x3,1
 mem[18]=32'h0080006F;  // jal  x0,+8
 mem[19]=32'hF9C18193;  // addi x3,x3,-100
 mem[20]=32'h00118193;  // addi x3,x3,1
 
 mem[21]=32'hFFB00093;  // addi x1,x0,-5
 mem[22]=32'h00300113;  // addi x2,x0,3
 
 mem[23]=32'h0020E663;  // bltu x1,x2,+12
 mem[24]=32'h00118193;  // addi x3,x3,1
 mem[25]=32'h0080006F;  // jal  x0,+8
 mem[26]=32'hF9C18193;  // addi x3,x3,-100
 mem[27]=32'h00118193;  // addi x3,x3,1
 
 mem[28]=32'h0020F463;  // bgeu x1,x2,+8
 mem[29]=32'hF9C18193;  // addi x3,x3,-100
 mem[30]=32'h00118193;  // addi x3,x3,1
*/

//......code to jump and U type instructions
/*
    mem[0]=32'h00000193;   // addi  x3, x0, 0
    mem[1]=32'h12345237;   // lui   x4, 0x12345
    mem[2]=32'h00118193;   // addi  x3, x3, 1
    mem[3]=32'h00001297;   // auipc x5, 0x1
    mem[4]=32'h00118193;   // addi  x3, x3, 1
    mem[5]=32'h008000EF;   // jal   x1, +8
    mem[6]=32'hF9C18193;   // addi  x3, x3, -100
    mem[7]=32'h00118193;   // addi  x3, x3, 1
    mem[8]=32'h02C00113;   // addi  x2, x0, 40 (0x28)
    mem[9]=32'h000100E7;   // jalr  x1, 0(x2)
    mem[10]=32'hF9C18193;   // addi  x3, x3, -100
    mem[11]=32'h00118193;   // addi  x3, x3, 1
   

*/
 /*
mem[0]=32'h02000093;   // addi x1, x0, 0x20

mem[1]=32'h11223137;   // lui  x2, 0x11223
mem[2]=32'h34410113;   // addi x2, x2, 0x344
mem[3]=32'h0020A023;   // sw   x2, 0(x1)

mem[4]=32'h0AA00113;   // addi x2, x0, 0xAA
mem[5]=32'h00208023;   // sb   x2, 0(x1)
mem[6]=32'h0000A183;   // lw   x3, 0(x1)

mem[7]=32'h55667137;   // lui  x2, 0x55667
mem[8]=32'h78810113;   // addi x2, x2, 0x788
mem[9]=32'h00209023;   // sh   x2, 0(x1)
mem[10]=32'h0000A203;   // lw   x4, 0(x1)

mem[11]=32'hDEADB137;   // lui  x2, 0xDEADB
mem[12]=32'hEEF10113;   // addi x2, x2, -273
mem[13]=32'h0020A023;   // sw   x2, 0(x1)
mem[14]=32'h0000A283;   // lw   x5, 0(x1)

*/
/*
mem[0]  = 32'h02000093;   // addi x1, x0, 0x20   (base address)

mem[1]  = 32'h11223137;   // lui  x2, 0x11223
mem[2]  = 32'h34410113;   // addi x2, x2, 0x344  -> x2 = 0x11223344
mem[3]  = 32'h0020A023;   // sw   x2, 0(x1)
mem[4]  = 32'h0000A183;   // lw   x3, 0(x1)     // CHECK SW

mem[5]  = 32'h0AA00113;   // addi x2, x0, 0xAA
mem[6]  = 32'h00208023;   // sb   x2, 0(x1)
mem[7]  = 32'h0000A203;   // lw   x4, 0(x1)     // CHECK SB

mem[8]  = 32'h55667137;   // lui  x2, 0x55667
mem[9]  = 32'h78810113;   // addi x2, x2, 0x788 -> x2 = 0x55667788
mem[10] = 32'h00209023;   // sh   x2, 0(x1)
mem[11] = 32'h0000A283;   // lw   x5, 0(x1)     // CHECK SH

mem[12] = 32'hDEADB137;   // lui  x2, 0xDEADB
mem[13] = 32'hEEF10113;   // addi x2, x2, -273  -> x2 = 0xDEADBEEF
mem[14] = 32'h0020A023;   // sw   x2, 0(x1)
mem[15] = 32'h0000A303;   // lw   x6, 0(x1)     // CHECK SW (final)
*/

/*
mem[0]  = 32'h02000093;   // addi x1, x0, 0x20

mem[1]  = 32'hA1B2C137;   // lui  x2, 0xA1B2C
mem[2]  = 32'h3D410113;   // addi x2, x2, 0x3D4
mem[3]  = 32'h0020A023;   // sw   x2, 0(x1)

mem[4]  = 32'h00008183;   // lb   x3, 0(x1)
mem[5]  = 32'h0000C203;   // lbu  x4, 0(x1)

mem[6]  = 32'h00209283;   // lh   x5, 2(x1)
mem[7]  = 32'h0020D303;   // lhu  x6, 2(x1)

mem[8]  = 32'h0000A383;   // lw   x7, 0(x1)
*/
  /*  mem[0] = 32'h02000093;   // addi x1, x0, 0x20
    mem[1] = 32'h12345137;   // lui  x2, 0x12345
    mem[2] = 32'h67810113;   // addi x2, x2, 0x678
    mem[3] = 32'h00209023;  //sh   x2, 0(x1)

 */

 /*
//below given code is infinte loop as the loop from mem[35] to mem[40] is infinite
 mem[0]  = 32'h000012B7; // LUI   x5, 0x1        -> x5 = 0x00001000 (upper immediate)
mem[1]  = 32'h00001317; // AUIPC x6, 0x1        -> x6 = PC + 0x1000 (PC-relative add)

mem[2]  = 32'h010000EF; // JAL   x1, +16        -> jump forward, x1 = return address
mem[3]  = 32'h00100013; // ADDI  x0, x0, 1      -> dummy (should be skipped)

mem[4]  = 32'hFF1FF06F; // JAL   x0, -16        -> backward jump (PC logic check)
mem[5]  = 32'h00008067; // JALR  x0, 0(x1)      -> jump to x1, LSB forced to 0

mem[6]  = 32'h00500093; // ADDI  x1, x0, 5      -> x1 = 5
mem[7]  = 32'hFFB00113; // ADDI  x2, x0, -5     -> x2 = -5 (sign-extension test)

mem[8]  = 32'h0020A193; // SLTI  x3, x1, 2      -> signed compare (false)
mem[9]  = 32'h0060B213; // SLTIU x4, x1, 6      -> unsigned compare (true)

mem[10] = 32'h00F0C293; // XORI  x5, x1, 15     -> immediate XOR
mem[11] = 32'h00F0E313; // ORI   x6, x1, 15     -> immediate OR
mem[12] = 32'h00F0F393; // ANDI  x7, x1, 15     -> immediate AND

mem[13] = 32'h00209413; // SLLI  x8, x1, 2      -> logical left shift immediate
mem[14] = 32'h0020D493; // SRLI  x9, x1, 2      -> logical right shift immediate
mem[15] = 32'h4020D513; // SRAI  x10,x1, 2      -> arithmetic right shift immediate

mem[16] = 32'h002081B3; // ADD   x3, x1, x2     -> register add
mem[17] = 32'h40208233; // SUB   x4, x1, x2     -> register subtract

mem[18] = 32'h002092B3; // SLL   x5, x1, x2     -> shift left by reg value
mem[19] = 32'h0020A333; // SLT   x6, x1, x2     -> signed register compare
mem[20] = 32'h0020B3B3; // SLTU  x7, x1, x2     -> unsigned register compare

mem[21] = 32'h0020C433; // XOR   x8, x1, x2     -> register XOR
mem[22] = 32'h0020E4B3; // OR    x9, x1, x2     -> register OR
mem[23] = 32'h0020F533; // AND   x10,x1, x2     -> register AND

mem[24] = 32'h0020D5B3; // SRL   x11,x1, x2     -> logical right shift (reg)
mem[25] = 32'h4020D633; // SRA   x12,x1, x2     -> arithmetic right shift (reg)

mem[26] = 32'h10000113; // ADDI  x2, x0, 256    -> base address for memory ops

mem[27] = 32'h00A12023; // SW    x10,0(x2)     -> store word
mem[28] = 32'h00911223; // SH    x9, 4(x2)     -> store halfword
mem[29] = 32'h00810423; // SB    x8, 8(x2)     -> store byte

mem[30] = 32'h00012183; // LW    x3, 0(x2)     -> load word
mem[31] = 32'h00411203; // LH    x4, 4(x2)     -> load half (signed)
mem[32] = 32'h00810283; // LB    x5, 8(x2)     -> load byte (signed)

mem[33] = 32'h00415203; // LHU   x4, 4(x2)     -> load half (unsigned)
mem[34] = 32'h00814283; // LBU   x5, 8(x2)     -> load byte (unsigned)

mem[35] = 32'h00100093; // ADDI  x1, x0, 1      -> x1 = 1
mem[36] = 32'h00200113; // ADDI  x2, x0, 2      -> x2 = 2

mem[37] = 32'h00208663; // BEQ   x1,x2,+12     -> not taken
mem[38] = 32'h00209463; // BNE   x1,x2,+8      -> taken

mem[39] = 32'h00000013; // NOP                 -> skipped if branch works

//mem[40] = 32'hFE209AE3; // BLT   x1,x2,-20     -> backward branch (taken)
mem[40] = 32'hFE20C6E3; // BLT   x1,x2,-20     -> backward branch (taken)
mem[41] = 32'h0020D463; // BGE   x1,x2,+8      -> not taken

mem[42] = 32'h0020E663; // BLTU  x1,x2,+12     -> unsigned less-than (taken)
mem[43] = 32'h0020F463; // BGEU  x1,x2,+8      -> unsigned greater/equal (not taken)

mem[44] = 32'h0000006F; // JAL   x0, 0          -> infinite loop (end of program)

*/

// ==========================
// MAIN (0x0000)
// ==========================
/*
mem[0]  = 32'h020000EF; // jal x1, 0x20        -> jump to funcA
mem[1]  = 32'h00100213; // addi x4, x0, 1      -> should execute last
mem[2]  = 32'h00200293; // addi x5, x0, 2
mem[3]  = 32'h0000006F; // jal x0, 0           -> infinite loop


// ==========================
// funcA (0x0020)
// ==========================
mem[8]  = 32'h00A00313; // addi x6, x0, 10     -> marker A reached

mem[9]  = 32'h00108513; // addi x10, x1, 1     -> create MISALIGNED addr
mem[10] = 32'h000502E7; // jalr x5, 0(x10)     -> x5 = return addr

mem[11] = 32'h06300393; // addi x7, x0, 99     -> executes after funcB
mem[12] = 32'h00008067; // jalr x0, 0(x1)      -> return to main


// ==========================
// funcB (0x0040)
// ==========================
mem[16] = 32'h03700413; // addi x8, x0, 55     -> marker B reached

mem[17] = 32'h00028267; // jalr x4, 0(x5)      -> nested return
mem[18] = 32'h00000013; // nop (should not execute)
*/

  end
  
endmodule