import os
import shutil
import logging
import re

import riscof.utils as utils
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

class sail_cSim(pluginTemplate):
    __model__ = "sail_c_simulator"
    __version__ = "0.5.0"

    def __init__(self, *args, **kwargs):
        sclass = super().__init__(*args, **kwargs)

        config = kwargs.get('config')
        if config is None:
            logger.error("Config node for sail_cSim missing.")
            raise SystemExit(1)

        self.num_jobs = str(config['jobs'] if 'jobs' in config else 1)
        self.pluginpath = os.path.abspath(config['pluginpath'])
        self.make = config['make'] if 'make' in config else 'make'

        # Resolve the RISC-V toolchain bin directory.
        # Primary: ~/riscv/bin  (matches run_riscof.sh PATH export)
        self.riscv_bin = os.path.expanduser("~/riscv/bin")

        logger.debug("SAIL CSim plugin initialised.")
        for entry in config:
            logger.debug(entry + ' : ' + config[entry])
        return sclass

    def initialise(self, suite, work_dir, archtest_env):
        self.suite = suite
        self.work_dir = work_dir
        self.archtest_env = archtest_env

    def build(self, isa_yaml, platform_yaml):
        ispec = utils.load_yaml(isa_yaml)['hart0']
        self.xlen = ('64' if 64 in ispec['supported_xlen'] else '32')
        self.default_isa = _normalize_isa_string(ispec["ISA"])
        self.isa = 'rv' + self.xlen

        if "I" in ispec["ISA"]: self.isa += 'i'
        if "M" in ispec["ISA"]: self.isa += 'm'
        if "C" in ispec["ISA"]: self.isa += 'c'
        if "F" in ispec["ISA"]: self.isa += 'f'
        if "D" in ispec["ISA"]: self.isa += 'd'

        self.mabi = 'lp64' if 64 in ispec['supported_xlen'] else 'ilp32'

        # Full paths to tools — no PATH manipulation needed
        self.gcc     = os.path.join(self.riscv_bin, f"riscv{self.xlen}-unknown-elf-gcc")
        self.objdump = os.path.join(self.riscv_bin, f"riscv{self.xlen}-unknown-elf-objdump")
        self.spike   = os.path.join(self.riscv_bin, "spike")

        for tool, name in [(self.gcc, 'gcc'), (self.objdump, 'objdump'),
                           (self.spike, 'spike'), (self.make, 'make')]:
            if not os.path.isfile(tool) and shutil.which(tool) is None:
                logger.error(f"{name} not found at: {tool}")
                raise SystemExit(1)

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
        makefile_path = os.path.join(self.work_dir, "Makefile." + self.name[:-1])
        if os.path.exists(makefile_path):
            os.remove(makefile_path)

        make = utils.makeUtil(makefilePath=makefile_path)
        make.makeCommand = self.make + ' -j' + self.num_jobs

        link_ld  = os.path.join(self.pluginpath, 'env', 'link.ld')
        env_inc  = os.path.join(self.pluginpath, 'env')
        arch_inc = self.archtest_env

        for file in testList:
            testentry = testList[file]
            test      = testentry['test_path']
            test_dir  = testentry['work_dir']
            test_name = test.rsplit('/', 1)[1][:-2]
            elf       = 'ref.elf'
            sig_file  = os.path.join(test_dir, self.name[:-1] + ".signature")

            clean_macros = [m.split('=')[0] if m.endswith('=True') else m
                            for m in testentry['macros']]
            clean_macros = [m for m in clean_macros if m != 'TEST_CASE_1']
            macro_flags = (' -D' + ' -D'.join(clean_macros)) if clean_macros else ''
            marchstr = self._get_test_isa(testentry, test)

            # Build compile command using full path to gcc
            compile_cmd = (
                f'"{self.gcc}" -march={marchstr}'
                f' -static -mcmodel=medany -fvisibility=hidden'
                f' -nostdlib -nostartfiles -mabi={self.mabi}'
                f' -T "{link_ld}"'
                f' -I "{env_inc}"'
                f' -I "{arch_inc}"'
                f' "{test}" -o "{elf}"'
                f'{macro_flags}'
            )

            # Build disassembly command
            objdump_cmd = f'"{self.objdump}" -D "{elf}" > "{test_name}.disass"'

            # Build spike simulation command
            spike_cmd = (
                f'"{self.spike}" --isa={marchstr}'
                f' -m0x80000000:0x10000000'
                f' --pc=0x80000000'
                f' +signature="{sig_file}"'
                f' +signature-granularity=4'
                f' "{elf}" > "{test_name}.log" 2>&1'
            )

            # Compose the full recipe for this make target.
            # '@cd dir;' is the standard RISCOF pattern — the '@' silences
            # the echo in make, and all subsequent commands run in that dir.
            execute = (
                f'@cd "{test_dir}";'
                f'{compile_cmd};'
                f'{objdump_cmd};'
                f'{spike_cmd}'
            )

            make.add_target(execute)

        make.execute_all(self.work_dir)
