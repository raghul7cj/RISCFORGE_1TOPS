// =============================================================================
`include "step4_cfg.svh"
//  step4_disasm.sv : minimal RV32IM_Zicsr decoder
// =============================================================================
//  Used by the failure reporter to annotate the last retired instructions in the
//  one-page diagnostic.  Step 1 already produces a PC map from the ELF; when that
//  file is present the reporter prefers it (function name + source line).  This
//  decoder is the fallback, and is also what runs during a hard hang, where the
//  last words in the fetch pipeline are all the TB still has.
//
//  Decodes: RV32I base + M extension + Zicsr (CSR / ECALL / EBREAK / MRET / WFI)
//  plus FENCE.  Anything else renders as .word 0x........ -- deliberately, so an
//  unrecognised encoding is visible rather than silently mis-decoded.
// =============================================================================

package step4_disasm_pkg;

  //  Sign-extend the low w BITS of v to 32 bits.
  //
  //  The width is in bits, not bytes, because the widths that actually matter
  //  here are 12 and 21 -- RISC-V's I/S/B and J immediates.  A byte-granular
  //  version cannot express 12 bits, and leaving those immediates unsigned is
  //  how "addi x6, x0, -1" ends up rendered as "4095" in a failure report.
  function automatic logic [31:0] sxb(input logic [31:0] v, input int w);
    logic [31:0] top, keep;
    if (w >= 32) return v;              // already 32 bits wide
    if (w <= 0)  return 32'h0000_0000;
    top  = 32'h1 << (w - 1);            // the sign bit of the field
    keep = top - 1'b1;                  // the w value bits
    return (v & keep) | ({32{v[w-1]}} & ~keep);
  endfunction

  function automatic string xreg(input logic [4:0] r);
    return $sformatf("x%-0d", r);
  endfunction

  function automatic string csr_name(input logic [11:0] c);
    case (c)
      12'h300: return "mstatus";
      12'h304: return "mie";
      12'h305: return "mtvec";
      12'h340: return "mscratch";
      12'h341: return "mepc";
      12'h342: return "mcause";
      12'h343: return "mtval";
      12'h344: return "mip";
      12'h341: return "mepc";
      12'h3A0: return "pmpcfg0";
      12'h3B0: return "pmpaddr0";
      12'hB00: return "mcycle";
      12'hB02: return "minstret";
      12'hC00: return "cycle";
      12'hC01: return "time";
      12'hC02: return "instret";
      default : return $sformatf("0x%03h", c);
    endcase
  endfunction

  //  Returns the disassembly of one 32-bit instruction, no leading "0x".
  function automatic string disasm(input logic [31:0] i);
    logic [6:0]  op;
    logic [4:0]  rd, rs1, rs2, f3, f7;
    logic [11:0] csr;
    //  Copies of the bit fields the immediate encoders need.
    //
    //  Taken as part-selects of the ARGUMENT once, here.  Reading them again
    //  inside a case arm is not safe: xsim returns the wrong bits for
    //  i[30:21] and i[31:25] on a function input, which silently corrupted the
    //  JAL offset and the shift-immediate funct7 in this decoder.
    logic [30:21] f_j10_1;
    logic [19:12] f_j19_12;
    logic [31:20] f_i31_20;
    logic [31:25] f_f31_25;
    logic [11:7]  f_s4_0;
    logic        f_j20, f_j11, f_b11;
    logic        f_bit30;        //  inst[30]: add/sub, srl/sra in RV32
    logic [30:25] f_b10_5;
    logic [11:8]  f_b4_1;
    logic [31:0] imm;
    int          si;

    op  = i[6:0];
    rd  = i[11:7];
    f3  = i[14:12];
    rs1 = i[19:15];
    rs2 = i[24:20];
    f7  = i[31:25];
    si  = $signed(i[31:20]);

    f_j10_1  = i[30:21];
    f_j19_12 = i[19:12];
    f_i31_20 = i[31:20];
    f_f31_25 = i[31:25];
    f_s4_0   = i[11:7];
    f_j20    = i[31];
    f_j11    = i[20];
    f_b11    = i[7];
    f_b10_5  = i[30:25];
    f_b4_1   = i[11:8];
    f_bit30  = i[30];

    case (op)

      // ---------------- LUI / AUIPC ----------------
      7'b0110111: return $sformatf("lui     %s, 0x%05x", xreg(rd), i[31:12]);
      7'b0010111: return $sformatf("auipc   %s, 0x%05x", xreg(rd), i[31:12]);

      // ---------------- JAL / JALR ----------------
      7'b1101111: begin
        //  imm[20]=inst[31], imm[19:12]=inst[19:12], imm[11]=inst[20],
        //  imm[10:1]=inst[30:21], imm[0] is not encoded.  Assembled by hand
        //  rather than by sign-extending a concatenation: the sign-fill width
        //  is easy to get wrong by one and a 31-bit result silently shifts every
        //  JAL target down by one.
        imm = sxb({f_j20, f_j19_12, f_j11, f_j10_1, 1'b0}, 21);
        return $sformatf("jal     %s, %0d   # 0x%08x",
                         xreg(rd), $signed(imm), $unsigned(imm));
      end
      7'b1100111: begin
        imm = sxb({20'b0, f_i31_20}, 12);   // I-type, like LOAD
        return $sformatf("jalr    %s, %0d(%s)", xreg(rd), $signed(imm), xreg(rs1));
      end

      // ---------------- BRANCH ----------------
      7'b1100011: begin
        //  B-type immediate: {imm[12], imm[10:5], imm[4:1], imm[11]}.  Bit 0
        //  of the immediate is ALWAYS zero -- it is not encoded.  Getting this
        //  wrong shifts every branch target by one, which in a failure report
        //  sends the reader to the wrong instruction.
        //  imm[12]=inst[31], imm[11]=inst[7], imm[10:5]=inst[30:25],
        //  imm[4:1]=inst[11:8], imm[0] is not encoded.
        imm = sxb({i[31], f_b11, f_b10_5, f_b4_1, 1'b0}, 13);
        case (f3)
          3'b000: return $sformatf("beq     %s, %s, %0d", xreg(rs1), xreg(rs2), $signed(imm));
          3'b001: return $sformatf("bne     %s, %s, %0d", xreg(rs1), xreg(rs2), $signed(imm));
          3'b100: return $sformatf("blt     %s, %s, %0d", xreg(rs1), xreg(rs2), $signed(imm));
          3'b101: return $sformatf("bge     %s, %s, %0d", xreg(rs1), xreg(rs2), $signed(imm));
          3'b110: return $sformatf("bltu    %s, %s, %0d", xreg(rs1), xreg(rs2), $signed(imm));
          3'b111: return $sformatf("bgeu    %s, %s, %0d", xreg(rs1), xreg(rs2), $signed(imm));
          default: return $sformatf(".word   0x%08x  # bad branch f3=%0d", i, f3);
        endcase
      end

      // ---------------- LOAD ----------------
      //  I-type immediate: the whole imm[11:0] lives in inst[31:20].
      //  Using inst[31:25] here (the S-type field) silently drops the low
      //  five bits, so every load offset comes out five too small.
      7'b0000011: begin
        imm = sxb({20'b0, f_i31_20}, 12);
        case (f3)
          3'b000: return $sformatf("lb      %s, %0d(%s)", xreg(rd), $signed(imm), xreg(rs1));
          3'b001: return $sformatf("lh      %s, %0d(%s)", xreg(rd), $signed(imm), xreg(rs1));
          3'b010: return $sformatf("lw      %s, %0d(%s)", xreg(rd), $signed(imm), xreg(rs1));
          3'b100: return $sformatf("lbu     %s, %0d(%s)", xreg(rd), $signed(imm), xreg(rs1));
          3'b101: return $sformatf("lhu     %s, %0d(%s)", xreg(rd), $signed(imm), xreg(rs1));
          default: return $sformatf(".word   0x%08x  # bad load f3=%0d", i, f3);
        endcase
      end

      // ---------------- STORE ----------------
      7'b0100011: begin
        imm = sxb({20'b0, f_f31_25, f_s4_0}, 12);
        case (f3)
          3'b000: return $sformatf("sb      %s, %0d(%s)", xreg(rs2), $signed(imm), xreg(rs1));
          3'b001: return $sformatf("sh      %s, %0d(%s)", xreg(rs2), $signed(imm), xreg(rs1));
          3'b010: return $sformatf("sw      %s, %0d(%s)", xreg(rs2), $signed(imm), xreg(rs1));
          default: return $sformatf(".word   0x%08x  # bad store f3=%0d", i, f3);
        endcase
      end

      // ---------------- OP-IMM (incl. M-ext immediate forms) ----------------
      7'b0010011: begin
        imm = sxb({20'b0, f_i31_20}, 12);
        case (f3)
          3'b000: return $sformatf("addi    %s, %s, %0d",   xreg(rd), xreg(rs1), $signed(imm));
          3'b010: return $sformatf("slti    %s, %s, %0d",   xreg(rd), xreg(rs1), $signed(imm));
          3'b011: return $sformatf("sltiu   %s, %s, %0d",   xreg(rd), xreg(rs1), $signed(imm));
          3'b100: return $sformatf("xori    %s, %s, 0x%03x", xreg(rd), xreg(rs1), imm[11:0]);
          3'b110: return $sformatf("ori     %s, %s, 0x%03x", xreg(rd), xreg(rs1), imm[11:0]);
          3'b111: return $sformatf("andi    %s, %s, 0x%03x", xreg(rd), xreg(rs1), imm[11:0]);
          3'b001: begin
            if (f7 == 7'b0000001) return $sformatf("mul     %s, %s, %0d", xreg(rd), xreg(rs1), $signed(imm));
            if (f7 == 7'b0000000) return $sformatf("slli    %s, %s, %0d",   xreg(rd), xreg(rs1), rs2);
            return $sformatf(".word   0x%08x", i);
          end
          3'b101: begin
            //  RV32: inst[30] alone picks arithmetic over logical shift.
            if (f_bit30)    return $sformatf("srai    %s, %s, %0d", xreg(rd), xreg(rs1), rs2);
            else            return $sformatf("srli    %s, %s, %0d", xreg(rd), xreg(rs1), rs2);
            if (f7 == 7'b0000001) return $sformatf("%s %s, %s, %0d",
                                     (f3 == 3'b101) ? "mulhsu" : "mulhu",
                                     xreg(rd), xreg(rs1), $signed(imm));
            return $sformatf(".word   0x%08x", i);
          end
          default: return $sformatf(".word   0x%08x", i);
        endcase
      end

      // ---------------- OP (incl. M extension) ----------------
      7'b0110011: begin
        if (f7 == 7'b0000001) begin
          case (f3)
            3'b000: return $sformatf("mul     %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2));
            3'b001: return $sformatf("mulh    %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2));
            3'b010: return $sformatf("mulhsu  %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2));
            3'b011: return $sformatf("mulhu   %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2));
            3'b100: return $sformatf("div     %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2));
            3'b101: return $sformatf("divu    %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2));
            3'b110: return $sformatf("rem     %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2));
            3'b111: return $sformatf("remu    %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2));
            default: return $sformatf(".word   0x%08x", i);
          endcase
        end
        if (f7 == 7'b0000000) begin
          case (f3)
            3'b000: return (f_bit30 ? $sformatf("sub     %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2))
                                  : $sformatf("add     %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2)));
            3'b001: return $sformatf("sll     %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2));
            3'b010: return $sformatf("slt     %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2));
            3'b011: return $sformatf("sltu    %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2));
            3'b100: return $sformatf("xor     %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2));
            3'b101: return (f_bit30 ? $sformatf("sra     %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2))
                                  : $sformatf("srl     %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2)));
            3'b110: return $sformatf("or      %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2));
            3'b111: return $sformatf("and     %s, %s, %s", xreg(rd), xreg(rs1), xreg(rs2));
            default: return $sformatf(".word   0x%08x", i);
          endcase
        end
        return $sformatf(".word   0x%08x", i);
      end

      // ---------------- MISC-MEM ----------------
      7'b0001111: return (i[31:25] == 7'b0000000 && i[14:12] == 3'b000)
                      ? "fence" : $sformatf(".word   0x%08x  # misc-mem", i);

      // ---------------- SYSTEM / Zicsr ----------------
      7'b1110011: begin
        if (f3 == 3'b000) begin
          case (i[31:20])
            12'h000: return "ecall";
            12'h001: return "ebreak";
            12'h302: return "mret";
            12'h105: return "wfi";
            default: return $sformatf(".word   0x%08x  # system imm=0x%03x", i, i[31:20]);
          endcase
        end
        csr = i[31:20];
        case (f3)
          3'b001: return $sformatf("csrrw   %s, %s, %s",  xreg(rd), csr_name(csr), xreg(rs1));
          3'b010: return $sformatf("csrrs   %s, %s, %s",  xreg(rd), csr_name(csr), xreg(rs1));
          3'b011: return $sformatf("csrrc   %s, %s, %s",  xreg(rd), csr_name(csr), xreg(rs1));
          3'b101: return $sformatf("csrrwi  %s, %s, %0d", xreg(rd), csr_name(csr), rs1);
          3'b110: return $sformatf("csrrsi  %s, %s, %0d", xreg(rd), csr_name(csr), rs1);
          3'b111: return $sformatf("csrrci  %s, %s, %0d", xreg(rd), csr_name(csr), rs1);
          default: return $sformatf(".word   0x%08x", i);
        endcase
      end

      default: return $sformatf(".word   0x%08x", i);
    endcase
  endfunction

endpackage : step4_disasm_pkg