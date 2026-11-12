#!/bin/bash

# Arguments passed from riscof_riscof_rtl.py
SIG_FILE=$1
ELF_FILE=$2

# Create hex file from elf
riscv64-unknown-elf-objcopy -O verilog --verilog-data-width=4 "$ELF_FILE" memfile.mem

# Get begin_signature, end_signature, and tohost addresses (in hex)
BEGIN_SIG=$(riscv64-unknown-elf-nm "$ELF_FILE" | grep -w "begin_signature" | awk '{print $1}')
END_SIG=$(riscv64-unknown-elf-nm "$ELF_FILE" | grep -w "end_signature" | awk '{print $1}')
TOHOST=$(riscv64-unknown-elf-nm "$ELF_FILE" | grep -w "tohost" | awk '{print $1}')

# Compile Verilog
PLUGIN_PATH=/home/pocharam/riscof/riscof_rtl
iverilog -o sim.vvp \
  "$PLUGIN_PATH/RISC_top.v" \
  "$PLUGIN_PATH/rv32_core.v" \
  "$PLUGIN_PATH/alu.v" \
  "$PLUGIN_PATH/control_unit.v" \
  "$PLUGIN_PATH/data_memory.v" \
  "$PLUGIN_PATH/instruction_memory.v" \
  "$PLUGIN_PATH/ls_unit.v" \
  "$PLUGIN_PATH/main_decoder.v" \
  "$PLUGIN_PATH/opcode_check.v" \
  "$PLUGIN_PATH/pc_adder.v" \
  "$PLUGIN_PATH/program_counter.v" \
  "$PLUGIN_PATH/register_file.v" \
  "$PLUGIN_PATH/seven_seg_controller.v" \
  "$PLUGIN_PATH/sign_extend.v" \
  "$PLUGIN_PATH/tb_riscof.v"

# Check if compile succeeded
if [ $? -ne 0 ]; then
    echo "Verilog compilation failed."
    exit 1
fi

# Run Verilog simulation and pass the computed addresses
vvp sim.vvp +begin_sig="$BEGIN_SIG" +end_sig="$END_SIG" +sig_file="$SIG_FILE" +tohost_addr="$TOHOST"
