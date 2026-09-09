# =============================================================================
# RISCFORGE 1TOPS — Run SPI Master Verification on Remote Server
# =============================================================================

$Server     = "172.16.33.51"
$User       = "iiita"
$Pass       = "vishal6776"
$HostKey    = "SHA256:cqJWRoLmPRrAi2x4x+JG1xNtIw4Yjro8LNKzFzScxBU"
$RemotePath = "/home/iiita/Documents/raghulcj/SPI0_verif"
$LocalIps   = "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips"

Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host " [1/3] Syncing files to Remote Server ($Server)..." -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Cyan

# Create remote directory
& "C:\Program Files\PuTTY\plink.exe" -ssh -batch -hostkey $HostKey -pw $Pass ${User}@${Server} "mkdir -p $RemotePath"

# Sync IPS to remote
& "C:\Program Files\PuTTY\pscp.exe" -batch -hostkey $HostKey -pw $Pass -r "$LocalIps\*" ${User}@${Server}:${RemotePath}/

Write-Host "`n===============================================================" -ForegroundColor Cyan
Write-Host " [2/3] Compiling C test and running Xcelium simulation..." -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Cyan

$RemoteCmd = "cd $RemotePath/datapath_verification/spi0 && " +
             "export PATH=/home/iiita/riscv_tools/bin:`$PATH && " +
             "export LM_LICENSE_FILE=5280@14.139.1.126 CDS_LIC_FILE=5280@14.139.1.126 && " +
             "make clean && make all && " +
             "/home/install/XCELIUM2209/bin/xrun -f tb_spi0.f -l xrun.log"

& "C:\Program Files\PuTTY\plink.exe" -ssh -batch -hostkey $HostKey -pw $Pass ${User}@${Server} "$RemoteCmd"

Write-Host "`n===============================================================" -ForegroundColor Cyan
Write-Host " [3/3] Fetching simulation log..." -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Cyan

& "C:\Program Files\PuTTY\pscp.exe" -batch -hostkey $HostKey -pw $Pass ${User}@${Server}:${RemotePath}/datapath_verification/spi0/xrun.log .\xrun.log

if (Test-Path ".\xrun.log") {
    Get-Content ".\xrun.log" | Select-String -Pattern "RISCFORGE|SIMULATION|SPI|PASSED|FAILED|TEST" -Context 1,1
}

