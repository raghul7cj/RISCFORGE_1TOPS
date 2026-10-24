// =============================================================================
//  step4_sim.f : compile list for the Step 4 self-proof  (Vivado xvlog)
// =============================================================================
//  The checker package plus its self-proof testbench.  The real
//  axi_lite_to_apb is NOT in this list: its APB ports are unpacked arrays of a
//  parameter type, and xsim will not elaborate that port connection (see the
//  note at the DUT instantiation in step4_smoke_tb.sv).  step4_apb_bridge_model
//  stands in for it, with every decision line-cited to the RTL it copies.
//
//  For the SoC-level regression the checkers are bound to the real fabric and
//  the real bridge is compiled from the SoC file list -- that runs under
//  Xcelium or VCS, which both handle the array ports.  See step4_bind.svh.
//
//    xvlog -sv -i . -f step4_sim.f
//    xelab step4_smoke_tb -s step4_sim
//    xsim step4_sim -runall
//
//  ORDER IS SIGNIFICANT: xsim does not make SystemVerilog packages visible
//  across files in one invocation.
// =============================================================================

// ---- packages -------------------------------------------------------------
step4_pkg.sv
step4_disasm.sv

// ---- reporter: the interface holds state, the module holds the logic -------
step4_hub.sv
step4_reporter.sv

// ---- checkers --------------------------------------------------------------
step4_axi_sva.sv
step4_apb_sva.sv
step4_path_scoreboard.sv
step4_fault_inject.sv

// ---- tests ----------------------------------------------------------------
//  step4_disasm_tb pins down the failure-report disassembler.  Run it on its
//  own first:
//      xelab step4_disasm_tb -s dec_tb && xsim dec_tb -runall
step4_disasm_tb.sv
step4_smoke_tb.sv