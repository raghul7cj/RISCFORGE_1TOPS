import os
import re
import shutil
import subprocess
import shlex
import logging
import random
import string
from string import Template
import sys
import signal

import riscof.utils as utils
import riscof.constants as constants
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()


def _normalize_isa_string(isa_str):
    isa = isa_str.strip()
    if not isa:
        return isa
    isa = isa.replace("RV", "rv").replace("rv32g", "rv32imafd").replace("rv64g", "rv64imafd")
    isa = re.sub(r'^(rv(?:32|64)[a-z]+)(z.*)$', r'\1_\2', isa)
    return isa.lower()


def _extract_march_from_test(test_path):
    try:
        with open(test_path, "r", encoding="utf-8") as test_file:
            for line in test_file:
                match = re.search(r'#\s*MARCH:\s*([A-Za-z0-9_]+)', line)
                if match:
                    return _normalize_isa_string(match.group(1))
    except OSError:
        return None
    return None

class riscforge(pluginTemplate):
    __model__ = "riscforge"
    __version__ = "1.0.0"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        config = kwargs.get('config')
        if config is None:
            print("Please enter input file paths in configuration.")
            raise SystemExit(1)

        self.dut_exe = os.path.join(config['PATH'] if 'PATH' in config else "","riscforge")
        self.num_jobs = str(config['jobs'] if 'jobs' in config else 1)
        self.pluginpath = os.path.abspath(config['pluginpath'])
        self.isa_spec = os.path.abspath(config['ispec'])
        self.platform_spec = os.path.abspath(config['pspec'])

        if 'target_run' in config and config['target_run']=='0':
            self.target_run = False
        else:
            self.target_run = True

    def initialise(self, suite, work_dir, archtest_env):
        self.work_dir = work_dir
        self.suite_dir = suite
        self.compile_cmd = 'riscv{1}-unknown-elf-gcc -march={0} \
         -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -g\
         -T "' + os.path.join(self.pluginpath, 'env', 'link.ld') + '"\
         -I "' + os.path.join(self.pluginpath, 'env') + '"\
         -I "' + archtest_env + '" "{2}" -o "{3}" {4}'

    def build(self, isa_yaml, platform_yaml):
        ispec = utils.load_yaml(isa_yaml)['hart0']
        self.xlen = ('64' if 64 in ispec['supported_xlen'] else '32')
        self.default_isa = _normalize_isa_string(ispec["ISA"])
        self.isa = 'rv' + self.xlen
        if "I" in ispec["ISA"]:
            self.isa += 'i'
        if "M" in ispec["ISA"]:
            self.isa += 'm'
        if "C" in ispec["ISA"]:
            self.isa += 'c'
        self.compile_cmd = self.compile_cmd + ' -mabi=' + ('lp64 ' if 64 in ispec['supported_xlen'] else 'ilp32 ')

        # Compile the RTL core once using iverilog
        # pluginpath = .../rtl/verification/riscof/riscforge
        # Go up 3 levels: riscforge -> riscof -> verification -> rtl
        rtl_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(self.pluginpath))), "rv32im_zicsr_5stage_exc_nointr")
        os.makedirs(self.work_dir, exist_ok=True)
        self.sim_bin = os.path.join(self.work_dir, "riscof_sim")
        
        files = [
            "axi_pkg.sv", "hybrid_mem_interface.sv",
            "riscforge_soc_subsystem_tb.sv", "tb_riscof.v",
            "top.v", "decode_cycle.v", "execute_cycle.v",
            "fetch_cycle.v", "memory_cycle.v", "writeback_cycle.v",
            "ALU.v", "ALU_Decoder.v", "Control_Unit_Top.v", "Data_Memory.v",
            "Instruction_Memory.v", "JB_unit.v", "Main_Decoder.v", "Mux2.v",
            "Mux_3_by_1.v", "PC.v", "PC_Adder.v", "Register_File.v",
            "Sign_Extend.v", "booth_enc.v", "csa.v", "hazard_unit.v",
            "ls_unit.v", "opcode_check.v", "pp_gen.v", "rv32m_div.v",
            "rv32m_mul.v", "rv32m_unit.v", "csr_regfile.v",
            "wb_trap_mret_commit_controller.v", "imem_controller.v"
        ]
        files_abs = [os.path.join(rtl_dir, f) for f in files]
        compile_rtl_cmd = f'iverilog -g2012 -o "{self.sim_bin}" ' + " ".join([f'"{f}"' for f in files_abs])
        
        logger.info(f"Compiling RTL via Iverilog: {compile_rtl_cmd}")
        utils.shellCommand(compile_rtl_cmd).run()

    def _get_test_isa(self, testentry, test):
        if 'isa' in testentry and testentry['isa']:
            return _normalize_isa_string(testentry['isa'])

        march = _extract_march_from_test(test)
        if march:
            logger.warning(f"ISA missing in RISCOF entry for {test}; using MARCH={march}")
            return march

        logger.warning(f"ISA missing in RISCOF entry for {test}; falling back to spec ISA {self.default_isa}")
        return self.default_isa

    def runTests(self, testList, cgf_file=None):
        for testname in testList:
            logger.debug('Running Test: {0} on DUT'.format(testname))
            testentry = testList[testname]
            test = testentry['test_path']
            test_dir = testentry['work_dir']
            elf = 'my.elf'
            sig_file = os.path.join(test_dir, self.name[:-1] + ".signature")
            # Strip '=True' from boolean macros to avoid redefinition conflict with arch_test.h
            clean_macros = [m.split('=')[0] if m.endswith('=True') else m for m in testentry['macros']]
            clean_macros = [m for m in clean_macros if m != 'TEST_CASE_1']
            compile_macros = (' -D' + " -D".join(clean_macros)) if clean_macros else ''
            marchstr = self._get_test_isa(testentry, test)
            
            # 1. Compile test assembly to ELF
            cmd = self.compile_cmd.format(marchstr, self.xlen, test, elf, compile_macros)
            logger.debug('Compiling test: ' + test)
            utils.shellCommand(cmd).run(cwd=test_dir)
            
            if self.target_run:
                # 2. Extract begin_signature, end_signature, and tohost from ELF using nm
                elf_abs = os.path.join(test_dir, elf)
                nm_cmd = f'riscv32-unknown-elf-nm "{elf_abs}"'
                
                process = subprocess.Popen(shlex.split(nm_cmd), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                stdout, stderr = process.communicate()
                
                begin_sig = 0
                end_sig = 0
                tohost_addr = 0
                
                for line in stdout.decode('utf-8').splitlines():
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
                
                logger.debug(f"Extracted symbols: begin_sig={begin_sig:x}, end_sig={end_sig:x}, tohost={tohost_addr:x}")
                
                # 3. Convert ELF to imem.hex and dmem.hex using elf_to_hex.py
                elf_to_hex_py = os.path.join(self.pluginpath, "elf_to_hex.py")
                split_cmd = f'python3 "{elf_to_hex_py}" "{elf_abs}" imem.hex dmem.hex'
                utils.shellCommand(split_cmd).run(cwd=test_dir)
                
                # 4. Create placeholder signature BEFORE running simulation
                #    If vvp times out (stuck in zero-delay loop), the file still exists
                #    so RISCOF can proceed to the next test with a failing mismatch.
                placeholder = "00000000\n"
                os.makedirs(os.path.dirname(sig_file), exist_ok=True)
                with open(sig_file, 'w') as f:
                    f.write(placeholder)

                # 5. Run the Icarus Verilog simulation with vvp (with timeout)
                sim_cmd = (f'vvp "{self.sim_bin}"'
                           f' +begin_sig={begin_sig:x}'
                           f' +end_sig={end_sig:x}'
                           f' +tohost_addr={tohost_addr:x}'
                            f' +max_cycles=50000'
                           f' "+sig_file={sig_file}"')
                logger.info('Executing simulation: ' + sim_cmd)
                timeout_sec = 60
                try:
                    proc = subprocess.run(
                        shlex.split(sim_cmd),
                        cwd=test_dir,
                        timeout=timeout_sec,
                        capture_output=True,
                        text=True
                    )
                    if proc.returncode != 0:
                        logger.warning(f'Simulation exited with code {proc.returncode} for {testname}')
                    if proc.stdout:
                        logger.debug('vvp stdout: ' + proc.stdout[-2000:])
                    if proc.stderr:
                        logger.debug('vvp stderr: ' + proc.stderr[-2000:])
                except subprocess.TimeoutExpired:
                    logger.warning(f'Simulation TIMEOUT after {timeout_sec}s for {testname} — killing vvp')
                    # Ensure signature file exists (placeholder may have been overwritten partially)
                    if not os.path.exists(sig_file) or os.path.getsize(sig_file) == 0:
                        with open(sig_file, 'w') as f:
                            f.write(placeholder)
                            logger.warning(f'Wrote fallback dummy signature for {testname} after timeout')
                except Exception as e:
                    logger.error(f'Simulation failed for {testname}: {e}')
