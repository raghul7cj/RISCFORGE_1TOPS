`timescale 1ns/1ps
module tb_legality;
  reg [6:0] Op,funct7;
  reg [4:0] rs1=7,rs2=3,rd=5;
  reg [2:0] funct3;
  wire illegal_instr;
  Control_Unit_Top dut(.Op(Op),.funct7(funct7),.rs1(rs1),.rs2(rs2),.rd(rd),
    .funct3(funct3),.funct7_30(funct7[5]),.illegal_instr(illegal_instr));
  integer op,f3,f7,checked=0;
  reg legal;
  initial begin
    for(op=0;op<128;op=op+1)
      for(f3=0;f3<8;f3=f3+1)
        for(f7=0;f7<128;f7=f7+1) begin
          Op=op;funct3=f3;funct7=f7;
          legal=0;
          case(op)
            'h37,'h17,'h6f: legal=1;
            'h67: legal=(f3==0);
            'h63: legal=(f3==0||f3==1||f3>=4);
            'h03: legal=(f3==0||f3==1||f3==2||f3==4||f3==5);
            'h23: legal=(f3<=2);
            'h13: begin
              if(f3==1) legal=(f7==0);
              else if(f3==5) legal=(f7==0||f7==32);
              else legal=1;
            end
            'h33: begin
              case(f7)
                0,1: legal=1;
                32: legal=(f3==0||f3==5);
                default: legal=0;
              endcase
            end
            'h0f: legal=(f3==0||f3==1); // preserves existing FENCE/FENCE.I policy
            'h73: legal=(f3==1||f3==2||f3==3||f3>=5);
          endcase
          #1;
          if(illegal_instr !== !legal)
            $fatal(1,"legality mismatch op=%h f3=%h f7=%h",Op,funct3,funct7);
          checked=checked+1;
        end
    // Exact system encodings are checked separately from the nonzero-field sweep.
    Op='h73;rs1=0;rs2=0;rd=0;funct3=0;funct7=0; #1;
    if(illegal_instr) $fatal(1,"ECALL rejected");
    rs2=1; #1; if(illegal_instr) $fatal(1,"EBREAK rejected");
    rs2=2;funct7=7'h18; #1; if(illegal_instr) $fatal(1,"MRET rejected");
    rs2=5;funct7=7'h08; #1; if(illegal_instr) $fatal(1,"WFI rejected");
    $display("PASS legality field combinations=%0d plus exact SYSTEM guards",checked);
    $finish;
  end
endmodule
