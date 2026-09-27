$ServerHost = '172.16.33.51'
$User       = 'iiita'
$Pass       = 'vishal6776'
$HostKey    = 'SHA256:cqJWRoLmPRrAi2x4x+JG1xNtIw4Yjro8LNKzFzScxBU'
$RemoteDir  = '/home/iiita/Documents/raghulcj/ips/jaspergold'

$Plink = 'C:\Program Files\PuTTY\plink.exe'
$Pscp  = 'C:\Program Files\PuTTY\pscp.exe'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==============================================================="
Write-Host "  RISCFORGE 1TOPS -- CADENCE JASPERGOLD SUPERLINT LAUNCHER     "
Write-Host "==============================================================="

Write-Host "[1/4] Preparing remote work directory..."
& $Plink -ssh -batch -hostkey $HostKey -pw $Pass "${User}@${ServerHost}" "mkdir -p $RemoteDir/reports"

Write-Host "[2/4] Uploading JasperGold scripts..."
& $Pscp -batch -hostkey $HostKey -pw $Pass "$ScriptDir\lint.tcl" "$ScriptDir\run_jaspergold.sh" "$ScriptDir\jg_soc.f" "${User}@${ServerHost}:${RemoteDir}/"

Write-Host "[3/4] Executing JasperGold on Cadence Server ($ServerHost)..."
& $Plink -ssh -batch -hostkey $HostKey -pw $Pass "${User}@${ServerHost}" "bash -lc 'chmod +x $RemoteDir/run_jaspergold.sh && $RemoteDir/run_jaspergold.sh'"

Write-Host "[4/4] Fetching JasperGold reports back to local repository..."
& $Pscp -batch -hostkey $HostKey -pw $Pass -r "${User}@${ServerHost}:${RemoteDir}/reports" "$ScriptDir"
& $Pscp -batch -hostkey $HostKey -pw $Pass "${User}@${ServerHost}:${RemoteDir}/jg_run.log" "$ScriptDir"

Write-Host "==============================================================="
Write-Host "  JasperGold Execution Complete!                               "
Write-Host "==============================================================="

