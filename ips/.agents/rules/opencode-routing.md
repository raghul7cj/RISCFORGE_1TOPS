---
description: OpenCode free-tier model routing and swarm delegation guidelines
trigger: model_decision
---

# OpenCode Local Server & Swarm Rule

- When instructed to run agent swarms, parallel research queries, or high-volume multi-agent tasks on free tier models, route requests to the local OpenCode server at `http://127.0.0.1:4096`.
- **Dynamic Free Model Discovery**: Free-tier models change over time. **Always query `GET http://127.0.0.1:4096/provider` dynamically** upon launch or before dispatching swarm tasks to identify currently available free models (e.g., models matching `*-free` or having 0 cost under connected providers), rather than relying on a hardcoded list.
- **Mandatory Proxy Configuration** (for launching `opencode web`):
  ```powershell
  $env:HTTP_PROXY  = 'http://iec2023047:pass@172.31.2.4:8080'
  $env:HTTPS_PROXY = 'http://iec2023047:pass@172.31.2.4:8080'
  $env:all_proxy   = 'http://iec2023047:pass@172.31.2.4:8080'
  $env:ALL_PROXY   = 'http://iec2023047:pass@172.31.2.4:8080'
  opencode web
  ```
- **Helper Scripts**:
  - Launch & check active free models: `C:\Users\cj\.gemini\config\skills\opencode-swarm\scripts\launch_opencode.ps1`
  - Dynamic Swarm runner: `C:\Users\cj\.gemini\config\skills\opencode-swarm\scripts\run_opencode_swarm.ps1`

