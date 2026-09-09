# =============================================================================
# RISCFORGE 1TOPS — Run I2C0 & SoC Verification on Remote Synopsys Server
# =============================================================================

$ServerHost = "172.16.33.48"
$ServerUser = "iiita"
$ServerPass = "1tops@riscforge"
$HostKey    = "SHA256:6Ic19gNmU0iu/HXVZ0w/ZCYnqeb07bzr65ZezwB+3PM"
$RemoteDir  = "/home/iiita/Documents/CJ/1tops/ips"

Write-Host "==============================================================="
Write-Host "   RISCFORGE 1TOPS — I2C0 & AT24C02 Remote VCS Runner          "
Write-Host "==============================================================="

# 1. Compile bare-metal firmware
Write-Host "[1/4] Compiling bare-metal C application via WSL..."
wsl bash -c "cd '/mnt/c/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/datapath_verification/i2c0' && make clean && make"

# 2. Sync files to remote server
Write-Host "[2/4] Syncing files to Synopsys server ($ServerHost)..."
& "C:\Program Files\PuTTY\pscp.exe" -batch -hostkey $HostKey -pw $ServerPass -r "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\i2c_slave_at24c02" ${ServerUser}@${ServerHost}:${RemoteDir}/
& "C:\Program Files\PuTTY\pscp.exe" -batch -hostkey $HostKey -pw $ServerPass -r "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\datapath_verification\i2c0" ${ServerUser}@${ServerHost}:${RemoteDir}/datapath_verification/
& "C:\Program Files\PuTTY\pscp.exe" -batch -hostkey $HostKey -pw $ServerPass "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\RTL_SOC\soc_i2c_tb.f" ${ServerUser}@${ServerHost}:${RemoteDir}/RTL_SOC/soc_i2c_tb.f

# 3. Execute VCS simulation
Write-Host "[3/4] Compiling and running simulation with Synopsys VCS..."
$cmd = "cd $RemoteDir/RTL_SOC && export SNPSLMD_LICENSE_FILE=27020@14.139.1.126 && /home/iiita/Synopsys/Installed_tools/vcs/U-2023.03/bin/vcs -sverilog -timescale=1ns/1ps -full64 +define+SYNTHESIS -f soc_i2c_tb.f -o simv_i2c -l vcs_i2c.log && ./simv_i2c"

& "C:\Program Files\PuTTY\plink.exe" -ssh -batch -hostkey $HostKey -pw $ServerPass ${ServerUser}@${ServerHost} $cmd

Write-Host "[4/4] Simulation finished."
