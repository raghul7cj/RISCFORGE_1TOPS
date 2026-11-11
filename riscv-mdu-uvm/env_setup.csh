#!/bin/tcsh
source /home/install/cshrc
if ( -f .venv/bin/activate.csh ) source .venv/bin/activate.csh
setenv RISCV_INSTALL "$HOME/riscv_tools"
setenv PATH "$RISCV_INSTALL/bin:$PATH"
setenv RISCV_TOOLCHAIN "$RISCV_INSTALL"
setenv RISCV_GCC "$RISCV_INSTALL/bin/riscv64-unknown-elf-gcc"
setenv RISCV_OBJCOPY "$RISCV_INSTALL/bin/riscv64-unknown-elf-objcopy"
setenv SPIKE_PATH "$RISCV_INSTALL/bin"
source /home/install/XCELIUM2409/env.csh
setenv PATH "/home/install/XCELIUM2409/tools/bin:$PATH"
rehash