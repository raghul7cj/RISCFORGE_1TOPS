#!/usr/bin/env python3
import os
import sys

def main():
    # Base directory for riscof_work on WSL
    # We will assume this script is executed inside the WSL riscof directory:
    # /home/raghul7cj/RISCFORGE_1TOPS/rtl/verification/riscof
    riscof_work_dir = "./riscof_work/src"
    
    if not os.path.exists(riscof_work_dir):
        print(f"Error: Directory '{riscof_work_dir}' not found.")
        print("Please run this script from the RISCOF verification directory where 'riscof_work' is located.")
        sys.exit(1)
        
    print("======================================================================")
    print("               RISCOF SIGNATURE COMPARISON UTILITY                    ")
    print("======================================================================")
    
    failed_tests = 0
    passed_tests = 0
    total_tests = 0
    
    # Walk through the test directory structure
    for root, dirs, files in os.walk(riscof_work_dir):
        # We look for folders containing both dut/ and ref/ subdirectories
        if "dut" in dirs and "ref" in dirs:
            test_name = os.path.relpath(root, riscof_work_dir)
            total_tests += 1
            
            dut_sig_path = os.path.join(root, "dut", "DUT-riscforge.signature")
            ref_sig_path = os.path.join(root, "ref", "Reference-sail_c_simulator.signature")
            
            if not os.path.exists(dut_sig_path):
                print(f"[ERROR] {test_name}: DUT signature file missing ({dut_sig_path})")
                failed_tests += 1
                continue
            if not os.path.exists(ref_sig_path):
                print(f"[ERROR] {test_name}: Reference signature file missing ({ref_sig_path})")
                failed_tests += 1
                continue
                
            with open(dut_sig_path, "r") as f:
                dut_lines = [line.strip().lower() for line in f.read().splitlines() if line.strip()]
            with open(ref_sig_path, "r") as f:
                ref_lines = [line.strip().lower() for line in f.read().splitlines() if line.strip()]
                
            # Compare the contents
            mismatches = []
            max_lines = max(len(dut_lines), len(ref_lines))
            for idx in range(max_lines):
                dut_val = dut_lines[idx] if idx < len(dut_lines) else "<EOF>"
                ref_val = ref_lines[idx] if idx < len(ref_lines) else "<EOF>"
                
                if dut_val != ref_val:
                    mismatches.append((idx + 1, dut_val, ref_val))
                    
            if mismatches:
                failed_tests += 1
                print(f"\n[FAIL] {test_name}")
                print(f"       DUT Signature file: {os.path.relpath(dut_sig_path)}")
                print(f"       REF Signature file: {os.path.relpath(ref_sig_path)}")
                print("       Mismatches:")
                for line_num, dut_v, ref_v in mismatches:
                    print(f"         Line {line_num:3d} -> DUT: 0x{dut_v} | REF: 0x{ref_v}")
            else:
                passed_tests += 1
                print(f"[PASS] {test_name}")
                
    print("\n======================================================================")
    print("                            SUMMARY                                   ")
    print("======================================================================")
    print(f"  Total tests analyzed : {total_tests}")
    print(f"  Passed tests         : {passed_tests}")
    print(f"  Failed tests         : {failed_tests}")
    print("======================================================================")

if __name__ == "__main__":
    main()
