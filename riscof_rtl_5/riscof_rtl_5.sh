#!/bin/bash

# Arguments passed from riscof_riscof_rtl_5.py
SIG_FILE=$1
ELF_FILE=$2

# Create hex file from elf
riscv32-unknown-elf-objcopy -O verilog --verilog-data-width=4 --only-section=.text.init --only-section=.text "$ELF_FILE" imem.hex

riscv32-unknown-elf-objcopy -O verilog --verilog-data-width=4 --remove-section=.text.init --remove-section=.text --change-addresses=-0x1000 "$ELF_FILE" dmem.hex

# Get begin_signature, end_signature, and tohost addresses (in hex)
BEGIN_SIG=$(riscv32-unknown-elf-nm "$ELF_FILE" | grep -w "begin_signature" | awk '{print $1}')
END_SIG=$(riscv32-unknown-elf-nm "$ELF_FILE" | grep -w "end_signature" | awk '{print $1}')
TOHOST=$(riscv32-unknown-elf-nm "$ELF_FILE" | grep -w "tohost" | awk '{print $1}')

# Compile Verilog
PLUGIN_PATH=/home/pocharam/riscof/riscof_rtl_5
iverilog -o sim.vvp \
  "$PLUGIN_PATH/top.v" \
  "$PLUGIN_PATH/fetch_cycle.v" \
  "$PLUGIN_PATH/decode_cycle.v" \
  "$PLUGIN_PATH/execute_cycle.v" \
  "$PLUGIN_PATH/memory_cycle.v" \
  "$PLUGIN_PATH/writeback_cycle.v" \
  "$PLUGIN_PATH/ALU.v" \
  "$PLUGIN_PATH/ALU_Decoder.v" \
  "$PLUGIN_PATH/Control_Unit_Top.v" \
  "$PLUGIN_PATH/Data_Memory.v" \
  "$PLUGIN_PATH/Instruction_Memory.v" \
  "$PLUGIN_PATH/JB_unit.v" \
  "$PLUGIN_PATH/Main_Decoder.v" \
  "$PLUGIN_PATH/Mux2.v" \
  "$PLUGIN_PATH/Mux_3_by_1.v" \
  "$PLUGIN_PATH/PC.v" \
  "$PLUGIN_PATH/PC_Adder.v" \
  "$PLUGIN_PATH/Register_File.v" \
  "$PLUGIN_PATH/Sign_Extend.v" \
  "$PLUGIN_PATH/booth_enc.v" \
  "$PLUGIN_PATH/csa.v" \
  "$PLUGIN_PATH/hazard_unit.v" \
  "$PLUGIN_PATH/ls_unit.v" \
  "$PLUGIN_PATH/opcode_check.v" \
  "$PLUGIN_PATH/pp_gen.v" \
  "$PLUGIN_PATH/rv32m_div.v" \
  "$PLUGIN_PATH/rv32m_mul.v" \
  "$PLUGIN_PATH/rv32m_unit.v" \
  "$PLUGIN_PATH/tb_riscof.v"

# Check if compile succeeded
if [ $? -ne 0 ]; then
    echo "Verilog compilation failed."
    exit 1
fi

# Run Verilog simulation and pass the computed addresses
vvp sim.vvp +begin_sig="$BEGIN_SIG" +end_sig="$END_SIG" +sig_file="$SIG_FILE" +tohost_addr="$TOHOST"
