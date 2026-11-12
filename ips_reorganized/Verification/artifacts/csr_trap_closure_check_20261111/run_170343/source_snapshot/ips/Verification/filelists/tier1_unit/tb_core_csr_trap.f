// Invocation root: rtl/ips
// Top: tb_core_csr_trap
-sverilog
+v2k
-timescale=1ns/1ps
+incdir+riscv_core/rtl

Verification/infrastructure/tb/csr_trap/csr_trap_types_pkg.sv
Verification/infrastructure/tb/csr_trap/core_corner_if.sv
Verification/infrastructure/tb/csr_trap/csr_trap_env_pkg.sv
Verification/infrastructure/tb/csr_trap/core_corner_imem.sv
Verification/infrastructure/tb/csr_trap/core_corner_dmem.sv
Verification/infrastructure/checkers/core_csr_trap_probe.sv
Verification/infrastructure/checkers/core_csr_trap_assertions.sv

riscv_core/rtl/PC.v
riscv_core/rtl/PC_Adder.v
riscv_core/rtl/Mux2.v
riscv_core/rtl/Mux_3_by_1.v
riscv_core/rtl/ALU.v
riscv_core/rtl/ALU_Decoder.v
riscv_core/rtl/Main_Decoder.v
riscv_core/rtl/Control_Unit_Top.v
riscv_core/rtl/Sign_Extend.v
riscv_core/rtl/Register_File.v
riscv_core/rtl/JB_unit.v
riscv_core/rtl/opcode_check.v
riscv_core/rtl/booth_enc.v
riscv_core/rtl/csa.v
riscv_core/rtl/pp_gen.v
riscv_core/rtl/rv32m_mul.v
riscv_core/rtl/rv32m_div.v
riscv_core/rtl/rv32m_unit.v
riscv_core/rtl/irq_gateway.v
riscv_core/rtl/irq_arbiter.v
riscv_core/rtl/csr_regfile.v
riscv_core/rtl/wb_trap_mret_commit_controller.v
riscv_core/rtl/hazard_unit.v
riscv_core/rtl/imem_controller.v
riscv_core/rtl/ls_unit.v
riscv_core/rtl/fetch_cycle.v
riscv_core/rtl/decode_cycle.v
riscv_core/rtl/execute_cycle.v
riscv_core/rtl/memory_cycle.v
riscv_core/rtl/writeback_cycle.v
riscv_core/rtl/top.v

Verification/infrastructure/tb/tb_core_csr_trap.sv
-top tb_core_csr_trap
