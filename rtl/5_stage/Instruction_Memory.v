`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.01.2026 14:19:07
// Design Name: 
// Module Name: Instruction_Memory
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




module Instruction_Memory(rst,A,RD);

  input rst;
  input [29:0]A;//[31:0]A;
  output [31:0]RD;

  reg [31:0] mem [1023:0];
  
  assign RD = (!rst) ? {32{1'b0}} : mem[A];//[31:2]];

/*  initial begin
    $readmemh("instructions.mem",mem);
  end
*/


  initial begin
   // mem[0]=32'h00500093; //addi x1, x0, 5  
   
   // mem[0] = 32'h00500093;   // addi x1, x0, 5
   // mem[1] = 32'h00A00113;   // addi x2, x0, 10
   
    //mem[0] = 32'h00500093;   // addi x1, x0, 5
    //mem[1] = 32'h00308113;   // addi x2, x1, 3
    
    //mem[0] = 32'h00002083;   // lw   x1, 0(x0)
    //mem[1] = 32'h00108113;   // addi x2, x1, 1
    
    //mem[0] = 32'h00002083;   // lw   x1, 0(x0)
    //mem[1] = 32'h00102223;   // sw   x1, 4(x0)
    //mem[2] = 32'h00402103;   // lw   x2, 4(x0)
    
   // mem[0] = 32'h00500093;   // addi x1, x0, 5
   // mem[1] = 32'h00500113;   // addi x2, x0, 5
   // mem[2] = 32'h00208463;   // beq  x1, x2, +8  
   // mem[3] = 32'h06300193;   // addi x3, x0, 99   (wrong path)
  //  mem[4] = 32'h00100193;   // addi x3, x0, 1    (label)
  
   /* mem[0] = 32'h00500093;   // addi x1, x0, 5
    mem[1] = 32'h00600113;   // addi x2, x0, 6
    mem[2] = 32'h00208463;   // beq  x1, x2, +8  (NOT taken)
    mem[3] = 32'h00700193;   // addi x3, x0, 7
    mem[4] = 32'h00900213;   // addi x4, x0, 9  */
    
  /*  mem[0] = 32'h00A00093;   // addi x1, x0, 10
    mem[1] = 32'h008002EF;   // jal  x5, +8
    mem[2] = 32'h06300113;   // addi x2, x0, 99   (must be flushed)
    mem[3] = 32'h00300113;   // addi x2, x0, 3
    */
    
   /*
    mem[0] = 32'h01000093;   // addi x1, x0, 0x10
    mem[1] = 32'h000082E7;   // jalr x5, 0(x1)
    mem[2] = 32'h06300113;   // addi x2, x0, 99   (wrong path)
    mem[3] = 32'h05800193;   // addi x3, x0, 88   (wrong path)
    mem[4] = 32'h00700213;   // addi x4, x0, 7    (TARGET)
    */
    
   /*
    mem[0] = 32'h00500093;   // addi x1, x0, 5
    mem[1] = 32'h00008113;   // addi x2, x1, 0
    mem[2] = 32'h00208463;   // beq  x2, x1, +8
    mem[3] = 32'h06300193;   // addi x3, x0, 99   (wrong path)
    mem[4] = 32'h00100193;   // addi x3, x0, 1    (target)
    */
    
    /*
    mem[0] = 32'h02000093;   // addi x1, x0, 0x20
    mem[1] = 32'h00700113;   // addi x2, x0, 7
    mem[2] = 32'h0020A023;   // sw   x2, 0(x1)
    */
    
   
  /*  mem[0] = 32'h02000093;   // addi x1, x0, 0x20
    mem[1] = 32'h0AA00113;   // addi x2, x0, 0xAA
    mem[2] = 32'h00208023;   // sb   x2, 0(x1)
  */ 
   
  /*
    mem[0] = 32'h02000093;   // addi x1, x0, 0x20
    mem[1] = 32'h12345137;   // lui  x2, 0x12345
    mem[2] = 32'h67810113;   // addi x2, x2, 0x678
    mem[3] = 32'h00209023;  // sh   x2, 0(x1)
   */ 
    /*
    // -------- PROGRAM 1 : BASIC FUNCTIONAL TEST --------

    mem[0] = 32'h01000093;   // addi x1, x0, 16        ; base address
    mem[1] = 32'h00500113;   // addi x2, x0, 5
    mem[2] = 32'h00A00193;   // addi x3, x0, 10

    mem[3] = 32'h00310233;   // add  x4, x2, x3       ; x4 = 15
    mem[4] = 32'h00412023;   // sw   x4, 0(x2)        ; MEM[x2] = 15
    mem[5] = 32'h00012283;   // lw   x5, 0(x2)        ; x5 = 15

    mem[6] = 32'h00128333;   // add  x6, x5, x1       ; x6 = 31
    //mem[7] = 32'h00000013;   // addi x0, x0, 0        ; nop
    */
    
   /*
    // -------- PROGRAM 2 : PIPELINE & HAZARD TEST --------

    mem[0] = 32'h00000093;   // addi x1, x0, 0
    mem[1] = 32'h00100113;   // addi x2, x0, 1
    mem[2] = 32'h00208193;   // addi x3, x1, 2

    mem[3] = 32'h00310233;   // add  x4, x2, x3       ; RAW hazard
    mem[4] = 32'h00412023;   // sw   x4, 0(x2)

    mem[5] = 32'h00012283;   // lw   x5, 0(x2)
    mem[6] = 32'h00528333;   // add  x6, x5, x5       ; load-use hazard

    mem[7] = 32'h00630463;   // beq  x6, x6, +8       ; taken
    mem[8] = 32'h00100393;   // addi x7, x0, 1        ; should be flushed
    mem[9] = 32'h00200413;   // addi x8, x0, 2        ; branch target

   */
   
   /*
   // -------- PROGRAM 3 : ADVANCED PIPELINE STRESS (NO NOP) --------

    mem[0]  = 32'h008000EF;  // jal  x1, +8            ; jump to mem[2]
    mem[1]  = 32'h00100093;  // addi x1, x0, 1         ; MUST be flushed

    mem[2]  = 32'h00A00113;  // addi x2, x0, 10
    mem[3]  = 32'h01400193;  // addi x3, x0, 20
    mem[4]  = 32'h00310233;  // add  x4, x2, x3        ; x4 = 30
    mem[5]  = 32'h004082B3;  // add  x5, x1, x4        ; uses JAL link

    mem[6]  = 32'h00028067;  // jalr x0, 0(x5)         ; jump via register
    mem[7]  = 32'h00200213;  // addi x4, x0, 2         ; MUST be flushed
    mem[8]  = 32'h00300293;  // addi x5, x0, 3
    */
    
   /*
    // -------- PROGRAM 4 : LOAD → BRANCH → ALU --------

mem[0] = 32'h01000093;   // addi x1, x0, 16
mem[1] = 32'h00500113;   // addi x2, x0, 5
mem[2] = 32'h0020A023;   // sw   x2, 0(x1)

mem[3] = 32'h0000A183;   // lw   x3, 0(x1)
mem[4] = 32'h00318463;   // beq  x3, x3, +8        ; taken
mem[5] = 32'h00100213;   // addi x4, x0, 1         ; must flush
mem[6] = 32'h00200293;   // addi x5, x0, 2         ; branch target
mem[7] = 32'h00528333;   // add  x6, x5, x5
    */
    
   /*
    // -------- PROGRAM 7 : STORE-LOAD SAME ADDRESS --------

mem[0] = 32'h02000093;   // addi x1, x0, 32
mem[1] = 32'h00A00113;   // addi x2, x0, 10
mem[2] = 32'h0020A023;   // sw   x2, 0(x1)
mem[3] = 32'h0000A183;   // lw   x3, 0(x1)
mem[4] = 32'h003184B3;   // add  x9, x3, x3

 */   
    

    // -------- PROGRAM 8 : LOAD / STORE ALL TYPES --------

//mem[0]  = 32'h04000093;   // addi x1, x0, 64        ; base address = 0x40

//mem[1]  = 32'h0FF00113;   // addi x2, x0, 255       ; 0xFF (for byte sign test)
//mem[2]  = 32'h08000193;   // addi x3, x0, 128       ; 0x80 (sign bit set)

//mem[3]  = 32'h12345237;   // lui  x4, 0x12345
//mem[4]  = 32'h67820213;   // addi x4, x4, 0x678     ; x4 = 0x12345678
//mem[5]  = 32'h00208023;   // sb   x2, 0(x1)         ; MEM[0x40] = 0xFF
//mem[6]  = 32'h00309123;   // sh   x3, 2(x1)         ; MEM[0x42] = 0x0080
//mem[7]  = 32'h0040A223;   // sw   x4, 4(x1)         ; MEM[0x44] = 0x12345678
//mem[8]  = 32'h00008283;   // lb   x5, 0(x1)         ; sign-extend 0xFF → 0xFFFFFFFF
//mem[9]  = 32'h0000C303;   // lbu  x6, 0(x1)         ; zero-extend 0xFF → 0x000000FF
//mem[10] = 32'h00209383;   // lh   x7, 2(x1)         ; sign-extend 0x0080 → 128
//mem[11] = 32'h0020D403;   // lhu  x8, 2(x1)         ; zero-extend → 128
//mem[12] = 32'h0040A483;   // lw   x9, 4(x1)         ; x9 = 0x12345678
//mem[13] = 32'h006283B3;   // add  x7, x5, x6        ; -1 + 255 = 254
//mem[14] = 32'h00840433;   // add  x8, x8, x8        ; 128 * 2 = 256
//mem[15] = 32'h009484B3;   // add  x9, x9, x9        ; double word


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

  //mem[0]=32'h00402303;
    //mem[0] = 32'hFFC4A303;
    //mem[1] = 32'h00832383;
    // mem[0] = 32'h0064A423;
    // mem[1] = 32'h00B62423;
   // mem[0] = 32'h0062E233;
    // mem[1] = 32'h00B62423;

//Bubble sort

mem[0]  = 32'h00000093;  // addi x1, x0, 0

mem[1]  = 32'h00900313;  // addi x6, x0, 9
mem[2]  = 32'h0060A023;  // sw   x6, 0(x1)

mem[3]  = 32'h00300313;  // addi x6, x0, 3
mem[4]  = 32'h0060A223;  // sw   x6, 4(x1)

mem[5]  = 32'h00700313;  // addi x6, x0, 7
mem[6]  = 32'h0060A423;  // sw   x6, 8(x1)

mem[7]  = 32'h00100313;  // addi x6, x0, 1
mem[8]  = 32'h0060A623;  // sw   x6, 12(x1)

mem[9]  = 32'h00500313;  // addi x6, x0, 5
mem[10] = 32'h0060A823;  // sw   x6, 16(x1)

mem[11] = 32'h00500113;  // addi x2, x0, 5
mem[12] = 32'h00000193;  // addi x3, x0, 0

// outer loop

mem[13] = 32'h00000213;  // addi x4, x0, 0
mem[14] = 32'hFFF10413;  // addi x8, x2, -1
mem[15] = 32'h403404B3;//408404B3;//408184B3;  // sub  x9, x8, x3

// inner loop

mem[16] = 32'h02925463;//bge x4, x9, +40  =  02925463//00924263;  // bge  x4, x9, next_outer
mem[17] = 32'h00221293;  // slli x5, x4, 2
mem[18] = 32'h001282B3;  // add  x5, x5, x1

mem[19] = 32'h0002A303;  // lw   x6, 0(x5)
mem[20] = 32'h0042A383;  // lw   x7, 4(x5)

mem[21] = 32'h00734663;  // ble  x6, x7, no_swap

mem[22] = 32'h0072A023;  // sw   x7, 0(x5)
mem[23] = 32'h0062A223;  // sw   x6, 4(x5)

mem[24] = 32'h00120213;  // addi x4, x4, 1
mem[25] = 32'hFDDFF06F;  // jal  x0, inner

// next_outer

mem[26] = 32'h00118193;  // addi x3, x3, 1
mem[27] = 32'hFFF10413;  // addi x8, x2, -1
mem[28] = 32'h0081D463;//0081C663;  // bge  x3, x8, done
mem[29] = 32'hFC1FF06F;  // jal  x0, outer

// done

mem[30] = 32'h0000A503;  // lw x10, 0(x1)
mem[31] = 32'h0040A583;  // lw x11, 4(x1)
mem[32] = 32'h0080A603;  // lw x12, 8(x1)
mem[33] = 32'h00C0A683;  // lw x13, 12(x1)
mem[34] = 32'h0100A703;  // lw x14, 16(x1)

mem[35] = 32'h0000006F;  // jal x0, 0 (infinite loop)


  end

endmodule
