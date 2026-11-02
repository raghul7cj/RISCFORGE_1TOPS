@echo off
rem ===========================================================================
rem RISCFORGE 1TOPS - Nexys 4 DDR build: synth -> impl -> .bit -> .mcs
rem   build.bat              Pong (mem\pong, build it first with python build.py)
rem   build.bat <fw_dir>     other firmware, relative to ips\RTL_SOC\mem
rem Results go to out\ ; Vivado's logs, cache and checkpoints go to work\.
rem ===========================================================================
setlocal
set "HERE=%~dp0"
where vivado >nul 2>&1 || set "PATH=F:\Xilinx\Vivado\2023.2\bin;%PATH%"
if not exist "%HERE%work" mkdir "%HERE%work"
pushd "%HERE%work"
if "%~1"=="" (
    call vivado -mode batch -log vivado_build.log -journal vivado_build.jou -source "%HERE%build.tcl"
) else (
    call vivado -mode batch -log vivado_build.log -journal vivado_build.jou -source "%HERE%build.tcl" -tclargs %*
)
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%
