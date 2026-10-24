// =============================================================================
// RISCFORGE Core Interrupt Verification Filelist (tb1_interrupts.f)
// =============================================================================
// Self-contained filelist for Synopsys VCS and Verdi.
// =============================================================================

-sverilog
+v2k
-timescale=1ns/1ps

// Include paths
+incdir+../riscv_core/rtl
+incdir+../instr_module
+incdir+../axi_lite_xbar/include/common_cells

// Top testbench
-top core_interrupt_tb

// =============================================================================
// Section 1: Packages & Types
// =============================================================================
../axi_lite_xbar/include/common_cells/axi_pkg.sv

// =============================================================================
// Section 2: Core Leaf Modules & Combinational Blocks
// =============================================================================
../riscv_core/rtl/PC.v
../riscv_core/rtl/PC_Adder.v
../riscv_core/rtl/Mux2.v
../riscv_core/rtl/Mux_3_by_1.v
../riscv_core/rtl/ALU.v
../riscv_core/rtl/ALU_Decoder.v
../riscv_core/rtl/Main_Decoder.v
../riscv_core/rtl/Control_Unit_Top.v
../riscv_core/rtl/Sign_Extend.v
../riscv_core/rtl/Register_File.v
../riscv_core/rtl/JB_unit.v
../riscv_core/rtl/opcode_check.v

// =============================================================================
// Section 3: M-Extension (Multiply / Divide)
// =============================================================================
../riscv_core/rtl/booth_enc.v
../riscv_core/rtl/csa.v
../riscv_core/rtl/pp_gen.v
../riscv_core/rtl/rv32m_mul.v
../riscv_core/rtl/rv32m_div.v
../riscv_core/rtl/rv32m_unit.v

// =============================================================================
// Section 4: CSR, Trap, and Hazard Controllers
// =============================================================================
../riscv_core/rtl/irq_gateway.v
../riscv_core/rtl/irq_arbiter.v
../riscv_core/rtl/csr_regfile.v
../riscv_core/rtl/wb_trap_mret_commit_controller.v
../riscv_core/rtl/hazard_unit.v

// =============================================================================
// Section 5: Memory Control Helpers & Pipeline Stages
// =============================================================================
../riscv_core/rtl/imem_controller.v
../riscv_core/rtl/ls_unit.v
../riscv_core/rtl/fetch_cycle.v
../riscv_core/rtl/decode_cycle.v
../riscv_core/rtl/execute_cycle.v
../riscv_core/rtl/memory_cycle.v
../riscv_core/rtl/writeback_cycle.v

// =============================================================================
// Section 6: Core Top & Memory Infrastructure
// =============================================================================
../riscv_core/rtl/top.v
../riscv_core/rtl/hybrid_mem_interface.sv
../instr_module/Instruction_Memory.v
../instr_module/Data_Memory.v

// =============================================================================
// Section 7: Testbench Top
// =============================================================================
tb1_interrupts.sv
