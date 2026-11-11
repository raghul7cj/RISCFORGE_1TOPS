@echo off
setlocal enabledelayedexpansion
title RISC-V Compliance Runner

echo ===================================================
echo             RISC-V Compliance Runner              
echo ===================================================
echo.

:: Step 1: Choose recopy options to WSL
echo Choose files to copy to WSL:
echo [1] Copy Core RTL only (rv32im_zicsr_5stage_exc_nointr)
echo [2] Copy Verification suite only (verification)
echo [3] Copy BOTH (Core RTL + Verification)
echo [4] Clean and copy WHOLE rtl directory (traditional)
echo [5] Skip copying
echo.
set /p RECOPY_OPT="Enter option (1-5): "

if "%RECOPY_OPT%"=="1" (
    echo Copying Core RTL to WSL...
    wsl rm -rf /home/raghul7cj/RISCFORGE_1TOPS/rtl/rv32im_zicsr_5stage_exc_nointr
    wsl mkdir -p /home/raghul7cj/RISCFORGE_1TOPS/rtl
    wsl cp -r "/mnt/c/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/rv32im_zicsr_5stage_exc_nointr" /home/raghul7cj/RISCFORGE_1TOPS/rtl/
    echo Core RTL copied successfully!
) else if "%RECOPY_OPT%"=="2" (
    echo Copying Verification suite to WSL...
    wsl rm -rf /home/raghul7cj/RISCFORGE_1TOPS/rtl/verification
    wsl mkdir -p /home/raghul7cj/RISCFORGE_1TOPS/rtl
    wsl cp -r "/mnt/c/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/verification" /home/raghul7cj/RISCFORGE_1TOPS/rtl/
    echo Verification suite copied successfully!
) else if "%RECOPY_OPT%"=="3" (
    echo Copying BOTH Core RTL and Verification suite to WSL...
    wsl rm -rf /home/raghul7cj/RISCFORGE_1TOPS/rtl/rv32im_zicsr_5stage_exc_nointr
    wsl rm -rf /home/raghul7cj/RISCFORGE_1TOPS/rtl/verification
    wsl mkdir -p /home/raghul7cj/RISCFORGE_1TOPS/rtl
    wsl cp -r "/mnt/c/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/rv32im_zicsr_5stage_exc_nointr" /home/raghul7cj/RISCFORGE_1TOPS/rtl/
    wsl cp -r "/mnt/c/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/verification" /home/raghul7cj/RISCFORGE_1TOPS/rtl/
    echo Core RTL and Verification copied successfully!
) else if "%RECOPY_OPT%"=="4" (
    echo Cleaning and recopying WHOLE RTL directory to WSL...
    wsl rm -rf /home/raghul7cj/RISCFORGE_1TOPS
    wsl mkdir -p /home/raghul7cj/RISCFORGE_1TOPS
    wsl cp -r "/mnt/c/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl" /home/raghul7cj/RISCFORGE_1TOPS/
    echo Whole RTL directory copied successfully!
) else (
    echo Skipping copy step.
)
echo.

:: Step 2: Ask for test selection
echo Choose test execution option:
echo [1] Run single test (add-01.S)
echo [2] Run RV32I compliance suite
echo [3] Run RV32M compliance suite
echo [4] Run Privilege / Zicsr Exception suite
echo [5] Run Zicsr compliance suite
echo [6] Run full compliance suite
echo.
set /p TEST_OPT="Enter option (1-6): "
echo.

:: Run selected tests in WSL
if exist "riscof_work" rmdir /s /q "riscof_work"
wsl bash -c "cd /home/raghul7cj/RISCFORGE_1TOPS/rtl/verification/riscof && rm -rf riscof_work"

if "%TEST_OPT%"=="1" (
    echo Running single test...
    wsl bash -c "cd /home/raghul7cj/RISCFORGE_1TOPS/rtl/verification/riscof && ./run_riscof.sh run --config=config.ini --suite=../riscv-arch-test/riscv-test-suite/ --env=../riscv-arch-test/riscv-test-suite/env --testfile=test_list_single.yaml --no-browser"
) else if "%TEST_OPT%"=="2" (
    echo Running RV32I suite...
    wsl bash -c "cd /home/raghul7cj/RISCFORGE_1TOPS/rtl/verification/riscof && ./run_riscof.sh run --config=config.ini --suite=../riscv-arch-test/riscv-test-suite/rv32i_m/I --env=../riscv-arch-test/riscv-test-suite/env --no-browser"
) else if "%TEST_OPT%"=="3" (
    echo Running RV32M suite...
    wsl bash -c "cd /home/raghul7cj/RISCFORGE_1TOPS/rtl/verification/riscof && ./run_riscof.sh run --config=config.ini --suite=../riscv-arch-test/riscv-test-suite/rv32i_m/M --env=../riscv-arch-test/riscv-test-suite/env --no-browser"
) else if "%TEST_OPT%"=="4" (
    echo Running Privilege / Zicsr Exception suite...
    wsl bash -c "cd /home/raghul7cj/RISCFORGE_1TOPS/rtl/verification/riscof && ./run_riscof.sh run --config=config.ini --suite=../riscv-arch-test/riscv-test-suite/rv32i_m/privilege --env=../riscv-arch-test/riscv-test-suite/env --no-browser"
) else if "%TEST_OPT%"=="5" (
    echo Running Zicsr suite...
    wsl bash -c "cd /home/raghul7cj/RISCFORGE_1TOPS/rtl/verification/riscof && ./run_riscof.sh run --config=config.ini --suite=../riscv-arch-test/riscv-test-suite/rv32i_m/Zicsr --env=../riscv-arch-test/riscv-test-suite/env --no-browser"
) else (
    echo Running full test suite...
    wsl bash -c "cd /home/raghul7cj/RISCFORGE_1TOPS/rtl/verification/riscof && ./run_riscof.sh run --config=config.ini --suite=../riscv-arch-test/riscv-test-suite/ --env=../riscv-arch-test/riscv-test-suite/env --no-browser"
)

echo.
echo ===================================================
echo Done!
echo ===================================================
pause
