import os
import sys
import subprocess
import shutil

# Directories
RISCOF_DIR = os.path.dirname(os.path.abspath(__file__))
RTL_DIR = os.path.abspath(os.path.join(RISCOF_DIR, "..", "..", "rv32im_zicsr_5stage_exc_nointr"))
WORK_DIR = os.path.join(RISCOF_DIR, "riscof_work")
DEBUG_DIR = os.path.join(RISCOF_DIR, "debug_run")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 run_debug_sim.py <test_name>")
        print("Example: python3 run_debug_sim.py ebreak.S")
        sys.exit(1)

    test_arg = sys.argv[1]
    test_name = test_arg if test_arg.endswith(".S") else test_arg + ".S"
    
    test_dut_dir = os.path.join(WORK_DIR, "src", test_name, "dut")
    
    if not os.path.exists(test_dut_dir):
        print(f"Error: Compiled test output not found at: {test_dut_dir}")
        print("Please run RISCOF once first to compile the tests.")
        sys.exit(1)

    # 1. Extract symbols using riscv32-unknown-elf-nm
    elf_path = os.path.join(test_dut_dir, "my.elf")
    print(f"Extracting symbols from {elf_path}...")
    try:
        nm_proc = subprocess.run(
            ["riscv32-unknown-elf-nm", elf_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True
        )
        stdout = nm_proc.stdout.decode("utf-8")
    except Exception as e:
        print(f"Failed to run riscv32-unknown-elf-nm: {e}")
        print("Make sure riscv32-unknown-elf-gcc/nm is in your PATH in WSL.")
        sys.exit(1)

    begin_sig = 0
    end_sig = 0
    tohost_addr = 0

    for line in stdout.splitlines():
        parts = line.split()
        if len(parts) >= 3:
            addr = int(parts[0], 16)
            sym = parts[2]
            if sym == "begin_signature":
                begin_sig = addr
            elif sym == "end_signature":
                end_sig = addr
            elif sym == "tohost":
                tohost_addr = addr

    print(f"Extracted parameters: begin_sig=0x{begin_sig:x}, end_sig=0x{end_sig:x}, tohost=0x{tohost_addr:x}")

    # Create temporary debug run directory
    os.makedirs(DEBUG_DIR, exist_ok=True)
    
    # 2. Copy imem.hex and dmem.hex to debug_run/
    shutil.copy2(os.path.join(test_dut_dir, "imem.hex"), os.path.join(DEBUG_DIR, "imem.hex"))
    shutil.copy2(os.path.join(test_dut_dir, "dmem.hex"), os.path.join(DEBUG_DIR, "dmem.hex"))
    print("Copied imem.hex and dmem.hex to debug_run/")

    # 3. Compile RTL using iverilog
    rtl_files = [
        "tb_riscof.v", "top.v", "decode_cycle.v", "execute_cycle.v", 
        "fetch_cycle.v", "memory_cycle.v", "writeback_cycle.v", 
        "ALU.v", "ALU_Decoder.v", "Control_Unit_Top.v", "Data_Memory.v", 
        "Instruction_Memory.v", "JB_unit.v", "Main_Decoder.v", 
        "Mux2.v", "Mux_3_by_1.v", "PC.v", "PC_Adder.v", 
        "Register_File.v", "Sign_Extend.v", "booth_enc.v", "csa.v", 
        "hazard_unit.v", "ls_unit.v", "opcode_check.v", "pp_gen.v", 
        "rv32m_div.v", "rv32m_mul.v", "rv32m_unit.v", 
        "csr_regfile.v", "wb_trap_mret_commit_controller.v"
    ]
    
    rtl_paths = [os.path.join(RTL_DIR, f) for f in rtl_files]
    sim_out = os.path.join(DEBUG_DIR, "sim_debug")

    print("Compiling RTL with iverilog...")
    iverilog_cmd = ["iverilog", "-g2012", "-o", sim_out] + rtl_paths
    try:
        subprocess.run(iverilog_cmd, check=True)
        print("RTL Compiled successfully.")
    except subprocess.CalledProcessError as e:
        print(f"Iverilog compilation failed: {e}")
        sys.exit(1)

    # 4. Run the simulation
    sig_out = os.path.join(DEBUG_DIR, "signature.txt")
    vvp_cmd = [
        "vvp", sim_out,
        f"+begin_sig={begin_sig:x}",
        f"+end_sig={end_sig:x}",
        f"+tohost_addr={tohost_addr:x}",
        f"+sig_file={sig_out}"
    ]
    print(f"Running simulation with command: {' '.join(vvp_cmd)}")
    try:
        subprocess.run(vvp_cmd, cwd=DEBUG_DIR, check=True)
        print(f"Simulation completed. Signature saved to: {sig_out}")
        print(f"Waveform dumped to: {os.path.join(DEBUG_DIR, 'sim_trace.vcd')}")
    except subprocess.CalledProcessError as e:
        print(f"Simulation failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
