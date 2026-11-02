// =============================================================================
// RISCFORGE 1TOPS - RISC-V Core (RV32IM, 5-stage)
// =============================================================================
// All paths are relative to the run directory ips/RTL_SOC/sim/.
// Pulled in by ../run.f. Swap for core_stub.f to run the stub-core benches.
// =============================================================================

// Leaf / combinational blocks
../../riscv_core/rtl/PC.v
../../riscv_core/rtl/PC_Adder.v
../../riscv_core/rtl/Mux2.v
../../riscv_core/rtl/Mux_3_by_1.v
../../riscv_core/rtl/ALU.v
../../riscv_core/rtl/ALU_Decoder.v
../../riscv_core/rtl/Main_Decoder.v
../../riscv_core/rtl/Control_Unit_Top.v
../../riscv_core/rtl/Sign_Extend.v
../../riscv_core/rtl/Register_File.v
../../riscv_core/rtl/JB_unit.v
../../riscv_core/rtl/opcode_check.v

// M-extension (multiply / divide)
../../riscv_core/rtl/booth_enc.v
../../riscv_core/rtl/csa.v
../../riscv_core/rtl/pp_gen.v
../../riscv_core/rtl/rv32m_mul.v
../../riscv_core/rtl/rv32m_div.v
../../riscv_core/rtl/rv32m_unit.v

// CSR / trap / hazard control
../../riscv_core/rtl/csr_regfile.v
../../riscv_core/rtl/wb_trap_mret_commit_controller.v
../../riscv_core/rtl/hazard_unit.v

// Memory-side helpers (instantiated inside the pipeline stages)
../../riscv_core/rtl/imem_controller.v
../../riscv_core/rtl/ls_unit.v

// Pipeline stages
../../riscv_core/rtl/fetch_cycle.v
../../riscv_core/rtl/decode_cycle.v
../../riscv_core/rtl/execute_cycle.v
../../riscv_core/rtl/memory_cycle.v
../../riscv_core/rtl/writeback_cycle.v

// Core top
../../riscv_core/rtl/top.v

// Data-memory router (DSRAM direct / MMIO over AXI-Lite)
../../riscv_core/rtl/hybrid_mem_interface.sv
