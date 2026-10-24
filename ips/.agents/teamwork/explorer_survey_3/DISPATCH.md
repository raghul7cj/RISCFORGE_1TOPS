## 2026-10-01T21:00:09Z
You are explorer_survey_3.
Working directory: c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\explorer_survey_3
Read your task in DISPATCH.md in your working directory.
MANDATORY: Read ORIGINAL_REQUEST.md at c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\ORIGINAL_REQUEST.md.
Also inspect c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\AGENTS.md for the fast routing map.
Survey the verification environment, build scripts, simulator flows, and regression infrastructure.
Investigate:
1. Dual simulator build flows: remote Synopsys VCS / Cadence Xcelium flow (run_vcs.sh, soc_verification.f) vs local Windows AMD Vivado XSim flow (run_regression.ps1, soc_verification.prj).
2. Existing testbenches in Verification/ (tb1_interrupts.sv, run_tb1.ps1), RTL_SOC/ (soc_imem_boot_tb.sv, soc_regtest_tb.sv, etc.), datapath_verification/.
3. Checkers, scoreboards, and first-fatal blame engine requirements (structured 1-page markdown diagnostic failure report naming layer, check ID, and last 10 instructions).
4. The 7 proof stages across bare-metal C proof suites and vacuous pass prevention methodology.
Deliver your full findings in handoff.md in your working directory, update progress.md, and send a completion message back.
