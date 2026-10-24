---
name: opencode-swarm
description: Launch OpenCode web server with HTTP/HTTPS proxy configuration and run parallel agent swarms with dynamic free-tier model discovery.
---

# OpenCode Swarm Orchestration & Server Skill

This skill guides launching and orchestrating OpenCode local web server (`http://127.0.0.1:4096`) and running high-throughput parallel swarms using OpenCode's dynamically discovered free-tier models.

---

## 1. Launching OpenCode with Proxy Configuration

Before starting OpenCode, configure the mandatory proxy environment variables:

```powershell
$env:HTTP_PROXY  = 'http://iec2023047:pass@172.31.2.4:8080'
$env:HTTPS_PROXY = 'http://iec2023047:pass@172.31.2.4:8080'
$env:all_proxy   = 'http://iec2023047:pass@172.31.2.4:8080'
$env:ALL_PROXY   = 'http://iec2023047:pass@172.31.2.4:8080'

# Launch OpenCode Web Server
opencode web
```

---

## 2. Dynamic Free-Tier Model Discovery

Because available free models fluctuate on the OpenCode server, **always query active free models dynamically** at launch or before dispatch:

```powershell
$provData = Invoke-RestMethod -Uri "http://127.0.0.1:4096/provider"
$conn = $provData.connected
foreach ($p in $provData.all) {
    if ($conn -contains $p.id) {
        foreach ($prop in $p.models.PSObject.Properties) {
            $m = $prop.Value
            if (($m.id -like "*-free") -or ($m.cost.input -eq 0 -and $m.cost.output -eq 0)) {
                Write-Host "Active Free Model: $($m.name) [ID: $($m.id)] (Provider: $($p.id))"
            }
        }
    }
}
```

---

## 3. Running a Swarm of OpenCode Agents

### Swarm Execution Script (Auto-detects active free models):
```powershell
& "C:\Users\cj\.gemini\config\skills\opencode-swarm\scripts\run_opencode_swarm.ps1"
```

