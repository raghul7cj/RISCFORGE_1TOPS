// =============================================================================
// RISCFORGE 1TOPS — NEW DUT filelist
// Uses the real SoC top-level module instead of the TB wrapper.
// =============================================================================

-sv
-timescale 1ns/1ps
-access +rwc

// Top module for the real DUT
-top riscforge_soc_subsystem

// Include paths
+incdir+../
+incdir+./

// Package / common RTL
../axi_pkg.sv

// SoC SRAM / bridge modules
./axi_lite_sram_if.sv
./axi_lite_xbar.sv
./sram_mux.sv
./sram_sp.sv
./imem_sram_wrapper.sv

// Core + memory infrastructure
../Instruction_Memory.v
../Data_Memory.v
../hybrid_mem_interface.sv
../ls_unit.v
../imem_controller.v
../top.v
../fetch_cycle.v
../decode_cycle.v
../execute_cycle.v
../memory_cycle.v
../writeback_cycle.v
../ALU.v
../ALU_Decoder.v
../Control_Unit_Top.v
../Main_Decoder.v
../JB_unit.v
../Mux2.v
../Mux_3_by_1.v
../PC.v
../PC_Adder.v
../Register_File.v
../Sign_Extend.v
../booth_enc.v
../csa.v
../pp_gen.v
../rv32m_mul.v
../rv32m_div.v
../rv32m_unit.v
../irq_gateway.v
../irq_arbiter.v
../csr_regfile.v
../wb_trap_mret_commit_controller.v
../hazard_unit.v
../opcode_check.v

// Real SoC DUT top
./riscforge_soc_subsystem.sv
