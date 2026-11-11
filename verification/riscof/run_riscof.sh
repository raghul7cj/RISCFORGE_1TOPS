#!/usr/bin/env bash
export PATH=$HOME/riscv/bin:$PATH
source $HOME/riscof_env/bin/activate
cd "/home/raghul7cj/RISCFORGE_1TOPS/rtl/verification/riscof"

SUITE="../riscv-arch-test/riscv-test-suite/"
ENV="../riscv-arch-test/riscv-test-suite/env"

for arg in "$@"; do
    case "$arg" in
        --suite=*)
            SUITE="${arg#*=}"
            ;;
        --env=*)
            ENV="${arg#*=}"
            ;;
    esac
done

# If first arg is 'run', auto-setup work directory first
if [ "$1" = "run" ]; then
    echo "[run_riscof] Preparing environment..."
    riscof validateyaml --config=config.ini
    riscof testlist  --config=config.ini --suite=$SUITE --env=$ENV
fi

# Automatically create parent work directories for pre-defined test lists
python3 -c "
import yaml, os, sys
tf = None
for i, arg in enumerate(sys.argv[1:]):
    if arg.startswith('--testfile='):
        tf = arg.split('=')[1]
    elif arg == '--testfile' and i+1 < len(sys.argv):
        tf = sys.argv[i+1]
if tf and os.path.exists(tf):
    with open(tf) as f:
        data = yaml.safe_load(f)
        if data:
            for k, v in data.items():
                if isinstance(v, dict) and 'work_dir' in v:
                    os.makedirs(v['work_dir'], exist_ok=True)
" "$@"

riscof "$@"
