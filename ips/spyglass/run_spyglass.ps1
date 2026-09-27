$ServerHost = '172.16.33.48'
$User       = 'iiita'
$Pass       = '1tops@riscforge'
$HostKey    = 'SHA256:6Ic19gNmU0iu/HXVZ0w/ZCYnqeb07bzr65ZezwB+3PM'
$RemoteDir  = '/home/iiita/Documents/CJ/1tops/ips/spyglass'

$Plink = 'C:\Program Files\PuTTY\plink.exe'
$Pscp  = 'C:\Program Files\PuTTY\pscp.exe'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==============================================================="
Write-Host "  RISCFORGE 1TOPS -- SYNOPSYS SPYGLASS LINT LAUNCHER           "
Write-Host "==============================================================="

Write-Host "[1/4] Preparing remote work directory..."
& $Plink -ssh -batch -hostkey $HostKey -pw $Pass "${User}@${ServerHost}" "mkdir -p $RemoteDir/reports"

Write-Host "[2/4] Uploading SpyGlass scripts..."
& $Pscp -batch -hostkey $HostKey -pw $Pass "$ScriptDir\run_spyglass.tcl" "$ScriptDir\run_spyglass.sh" "$ScriptDir\spyglass.prj" "${User}@${ServerHost}:${RemoteDir}/"

Write-Host "[3/4] Executing SpyGlass on Synopsys Server ($ServerHost)..."
& $Plink -ssh -batch -hostkey $HostKey -pw $Pass "${User}@${ServerHost}" "bash -lc 'chmod +x $RemoteDir/run_spyglass.sh && $RemoteDir/run_spyglass.sh'"

Write-Host "[4/4] Fetching SpyGlass reports back to local repository..."
& $Pscp -batch -hostkey $HostKey -pw $Pass -r "${User}@${ServerHost}:${RemoteDir}/reports" "$ScriptDir\"
& $Pscp -batch -hostkey $HostKey -pw $Pass "${User}@${ServerHost}:${RemoteDir}/spyglass_run.log" "$ScriptDir\"

Write-Host "==============================================================="
Write-Host "  SpyGlass Execution Complete!                                 "
Write-Host "==============================================================="

