@echo off
rem ===========================================================================
rem RISCFORGE 1TOPS - program the Nexys 4 DDR flash and boot from it
rem   program.bat                flash out\nexys4ddr_pong.mcs and reboot
rem   program.bat flash <fw>     flash out\nexys4ddr_<fw>.mcs
rem   program.bat jtag           load out\nexys4ddr_top.bit over JTAG only
rem Programming uses JTAG, so a terminal open on the board's COM port is fine.
rem Vivado's logs go to work\.
rem ===========================================================================
setlocal
set "HERE=%~dp0"
where vivado >nul 2>&1 || set "PATH=F:\Xilinx\Vivado\2023.2\bin;%PATH%"
if not exist "%HERE%work" mkdir "%HERE%work"
pushd "%HERE%work"
if "%~1"=="" (
    call vivado -mode batch -log vivado_program.log -journal vivado_program.jou -source "%HERE%program.tcl"
) else (
    call vivado -mode batch -log vivado_program.log -journal vivado_program.jou -source "%HERE%program.tcl" -tclargs %*
)
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%
