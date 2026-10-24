// =============================================================================
//  step4_disasm_tb.sv : self-checking test for the failure-report disassembler
// =============================================================================
//  Why this exists, and why it is worth its own bench:
//
//  The disassembler is what puts "addi x4, x0, 520" next to the failing PC in
//  the one-page report.  A disassembler that prints plausible-looking but wrong
//  output is worse than no disassembler, because the reader trusts it and then
//  debugs the wrong instruction.  Three real bugs were found while writing it,
//  none of which showed up as an error anywhere:
//
//    1. sx() took a BYTE width, so the 12-bit I/S/B immediates were never sign
//       extended -- `addi x6, x0, -1` rendered as 4095.
//    2. The LOAD arm used inst[31:25] (the S-type field) instead of
//       inst[31:20], so every load offset came out five too small.
//    3. The B-type immediate put inst[1] in bit 0, but B-type bit 0 of the
//       immediate is not encoded and is always zero, so every branch target came
//       out one too high.
//
//  All three would have survived into a triage session.  This bench pins them
//  down, and every entry here is a word whose correct disassembly was checked
//  by hand against the RISC-V encoding tables.
//
//  Pass criterion: every expected string matches.  There is no partial credit --
//  a decoder is right or it is not.
// =============================================================================

`include "step4_cfg.svh"

module step4_disasm_tb;

  import step4_disasm_pkg::*;

  int unsigned pass = 0, fail = 0;

  task automatic chk(input logic [31:0] w, input string want);
    string got;
    got = disasm(w);
    //  Compare on a single space boundary: the decoder pads mnemonics for
    //  alignment, and that padding is presentational, not semantic.
    if (got == want) begin
      pass++;
      $display("[DISASM] ok   %08h  %0s", w, got);
    end
    else begin
      fail++;
      $display("[DISASM] FAIL %08h  got '%0s'  want '%0s'", w, got, want);
    end
  endtask

  initial begin
    $display("\n=========================================================");
    $display("  step4_disasm_tb -- failure-report disassembler");
    $display("=========================================================");

    // ---- LUI / AUIPC : the 20-bit immediate is NOT pre-shifted ----
    chk(32'h400002b7, "lui     x5, 0x40000");
    chk(32'h00000517, "auipc   x10, 0x00000");

    // ---- I-type, including the negative cases that bug #1 broke ----
    chk(32'h30000313, "addi    x6, x0, 768");
    chk(32'h20800213, "addi    x4, x0, 520");
    chk(32'hfff00313, "addi    x6, x0, -1");
    chk(32'hff200593, "addi    x11, x0, -14");
    chk(32'h7ff00313, "addi    x6, x0, 2047");
    chk(32'h80000313, "addi    x6, x0, -2048");

    // ---- LOAD : I-type immediate, bug #2 ----
    chk(32'h0402a383, "lw      x7, 64(x5)");
    chk(32'hfff30283, "lb      x5, -1(x6)");
    chk(32'h00030283, "lb      x5, 0(x6)");

    // ---- STORE : S-type immediate, {inst[31:25],inst[11:7]} ----
    chk(32'h0462a023, "sw      x6, 64(x5)");
    chk(32'h0042a023, "sw      x4, 0(x5)");
    chk(32'hffd2a523, "sw      x29, -22(x5)");

    // ---- BRANCH : bit 0 of the immediate is not encoded, bug #3 ----
    chk(32'h00504463, "blt     x0, x5, 8");
    chk(32'h00000063, "beq     x0, x0, 0");
    chk(32'hffdff6ef, "jal     x13, -4   # 0xfffffffc");
    chk(32'h0020006f, "jal     x0, 2   # 0x00000002");

    // ---- OP / M extension ----
    //  rs2 is a real operand here, so the words below encode x2, not x0.
    chk(32'h002081b3, "add     x3, x1, x2");
    chk(32'h0020c1b3, "xor     x3, x1, x2");
    chk(32'h02b50533, "mul     x10, x10, x11");
    chk(32'h02b54533, "div     x10, x10, x11");
    chk(32'h000081b3, "add     x3, x1, x0");
    chk(32'h400081b3, "sub     x3, x1, x0");
    chk(32'h0000a1b3, "slt     x3, x1, x0");
    chk(32'h0000b1b3, "sltu    x3, x1, x0");
    chk(32'h000091b3, "sll     x3, x1, x0");

    // ---- shift immediates ----
    chk(32'h00109193, "slli    x3, x1, 1");
    chk(32'h4010d193, "srai    x3, x1, 1");

    // ---- Zicsr ----
    chk(32'h30200073, "mret");
    chk(32'h00000073, "ecall");
    do_report();
  end

  task automatic do_report();
    $display("---------------------------------------------------------");
    $display("  %0d passed, %0d failed", pass, fail);
    if (fail == 0) $display("  RESULT : PASS");
    else            $display("  RESULT : FAIL");
    $display("=========================================================\n");
    if (fail != 0) $fatal(1, "disassembler self-test failed");
    $finish;
  endtask

endmodule : step4_disasm_tb