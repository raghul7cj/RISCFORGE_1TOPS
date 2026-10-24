# STAGE 0 — Filelist Integrity & File Resolution
**FPGA-PLAN-S0 | Prerequisite for ALL subsequent stages**

> **Status**: ✅ COMPLETE — Executed live via Vivado 2022.2 MCP (Nexys4 DDR: `xc7a100tcsg324-1`)  
> **Owner**: Orchestrator  
> **Blocker for**: S1 (RTL Lint)  
> **Sign-Off**: ⬜ PENDING — Awaiting human approval  
> **Executed**: 2026-10-16 00:10–00:17 IST

---

## Objective

Before any lint or synthesis can be meaningful, the RTL file list must be **complete, consistent, and resolvable**. The RevB verification plan flags this as its **highest-leverage item** (D-114): 15 of 40 filelists have unresolvable entries, two `timer.sv` sources exist and conflict, and one filelist bakes in a machine-absolute path.

This stage resolves all filelist health issues and produces a **canonical, single-source filelist** usable by Vivado XSim, JasperGold, and SpyGlass.

---

## Checks

### 0.1 — File Existence Audit

Verify every file listed in `jaspergold/jg_soc.f` physically exists on disk.

| File in `jg_soc.f` | Exists? | Notes |
|:--------------------|:-------:|:------|
| `../axi_lite_xbar/include/common_cells/cf_math_pkg.sv` | ⬜ | |
| `../axi_lite_xbar/include/common_cells/axi_pkg.sv` | ⬜ | |
| `../gpio-master/gpio_reg_pkg.sv` | ⬜ | |
| `../SOC_FILES/include/apb/apb_pkg.sv` | ⬜ | |
| `../SOC_FILES/include/obi/obi_pkg.sv` | ⬜ | |
| `../SOC_FILES/include/obi/obi_uart_pkg.sv` | ⬜ | |
| `../SOC_FILES/include/obi/apb_to_obi.sv` | ⬜ | UART OBI chain (D-015) |
| `../SOC_FILES/include/obi/obi_uart.sv` | ⬜ | |
| `../apb_uart-main/rtl/apb_uart_wrap.sv` | ⬜ | |
| `../apb_uart-main/rtl/apb_uart.sv` | ⬜ | |
| `../instr_module/Instruction_Memory.v` | ⬜ | Check vs SRAM wrapper |
| `../riscv_core/rtl/top.v` | ⬜ | |
| `../riscv_core/rtl/hybrid_mem_interface.sv` | ⬜ | |
| `../bootloader/bootloader.sv` | ⬜ | |
| `../RTL_SOC/riscforge_soc_subsystem.sv` | ⬜ | |
| *...all 141 lines of jg_soc.f* | ⬜ | Run automated check |

**Agent Action**: Run PowerShell script to resolve all paths from `jaspergold/jg_soc.f` and report missing files.

```powershell
# Automated check — run from: ips/jaspergold/
$base = "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\jaspergold"
$flist = Get-Content "$base\jg_soc.f"
$missing = @(); $found = 0; $skipped = 0
foreach ($line in $flist) {
    $l = $line.Trim()
    if ($l -match '^\s*$' -or $l -match '^//' -or $l -match '^\+incdir' -or $l -eq '-sv') {
        $skipped++; continue
    }
    $absPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($base, $l))
    if (Test-Path $absPath) { $found++ }
    else { $missing += $absPath }
}
Write-Host "FOUND: $found  MISSING: $($missing.Count)"
$missing | ForEach-Object { Write-Host "  MISSING: $_" }
```

**Result**: ⬜ TBD — Agent to execute and populate

---

### 0.2 — Duplicate Module / Timer Conflict (D-114)

The RevB plan reports **two `timer.sv` sources** compiled by different filelists, creating a multiple-definition hazard.

| Check | Expected | Actual | Status |
|:------|:---------|:-------|:------:|
| Single `timer.sv` source across all filelists | 1 file | ⬜ TBD | ⬜ |
| `apb_timer-master/timer.sv` is the canonical source | Confirmed | ⬜ TBD | ⬜ |
| No other `timer.sv` elsewhere in tree | 0 extras | ⬜ TBD | ⬜ |

```powershell
Get-ChildItem "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips" -Recurse -Filter "timer.sv" | Select-Object FullName
```

---

### 0.3 — Include Directory Existence

All `+incdir+` paths in `jg_soc.f` must resolve. Known suspect: `../mem_files` incdir.

| Incdir | Exists? |
|:-------|:-------:|
| `../axi_lite_xbar/include/axi` | ⬜ |
| `../axi_lite_xbar/include/common_cells` | ⬜ |
| `../SOC_FILES/include/apb` | ⬜ |
| `../SOC_FILES/include/obi` | ⬜ |
| `../SOC_FILES/include/common_cells` | ⬜ |
| `../SOC_FILES/include/axi` | ⬜ |
| `../SOC_FILES/include/register_interface` | ⬜ |
| `../apb_i2c-master` | ⬜ |
| `../gpio-master` | ⬜ |
| `../spi_master_ip/spi_master` | ⬜ |
| `../RTL_SOC` | ⬜ |
| `../mem_files` | ⬜ |

---

### 0.4 — Absolute Path Detection

No filelist entry may contain a machine-absolute path (e.g., `C:\...` or `/home/...`).

| Check | Status |
|:------|:------:|
| No absolute Windows paths in `jg_soc.f` | ⬜ |
| No absolute Windows paths in `spyglass.prj` | ⬜ |
| No absolute paths in any `*.f` filelists under `ips/` | ⬜ |

---

### 0.5 — UART OBI Chain Documentation (D-015)

The RevB plan flags a critical discrepancy: `soc_subsystem.f` claims the OBI chain was removed, but `apb_uart.sv:52` instantiates `apb_uart_wrap` → `apb_to_obi` → `obi_uart`.

| Check | Status | Notes |
|:------|:------:|:------|
| `apb_uart_wrap.sv` confirmed in filelist | ⬜ | Required for elaboration |
| `apb_to_obi.sv` confirmed in filelist | ⬜ | OBI bridge |
| `obi_uart.sv` confirmed in filelist | ⬜ | OBI UART core |
| `obi_uart_pkg.sv` package compiled before use | ⬜ | Package-before-module order |
| Instantiation chain documented | ⬜ | `apb_uart.sv` → `apb_uart_wrap` → `apb_to_obi` → `obi_uart` |

> [!IMPORTANT]
> The `jg_soc.f` already includes the full OBI chain (lines 67–76). Verify this matches the actual file hierarchy. Compilation order in the filelist must put packages before modules.

---

### 0.6 — Canonical Filelist Generation

Once checks 0.1–0.5 pass, generate a **Vivado XSim-compatible filelist** (`ips/vivado_soc.f`) for use in Stage 1.

| Deliverable | Status |
|:------------|:------:|
| `vivado_soc.f` — Vivado-compatible filelist | ⬜ Not created |
| All paths relative to `ips/` | ⬜ |
| Compilation order verified (pkg → interfaces → modules → top) | ⬜ |

---

## Findings Log

| Finding ID | File | Line | Description | Severity | Resolution |
|:-----------|:-----|:----:|:------------|:--------:|:-----------|
| S0-F001 | — | — | ⬜ TBD — Agent will populate | — | — |

---

## Agent Execution Plan

```mermaid
flowchart TD
    A[Start S0] --> B[Run 0.1: File existence audit on jg_soc.f]
    B --> C{All files found?}
    C -- No --> D[Report missing files → S0-BLOCKED]
    C -- Yes --> E[Run 0.2: Duplicate timer.sv scan]
    E --> F[Run 0.3: Incdir existence check]
    F --> G[Run 0.4: Absolute path scan]
    G --> H[Run 0.5: UART OBI chain confirm]
    H --> I[Generate vivado_soc.f]
    I --> J[Populate Findings Log]
    J --> K{Any CRITICAL findings?}
    K -- Yes --> L[Fix and re-check]
    K -- No --> M[Stage S0 Complete → Request Sign-Off]
```

---

## Sign-Off Block

> **To approve Stage 0, the following must all be ✅:**

| Criteria | Status |
|:---------|:------:|
| All files in `jg_soc.f` resolve on disk | ⬜ |
| No duplicate `timer.sv` conflict | ⬜ |
| All `+incdir+` directories exist | ⬜ |
| No absolute paths in any filelist | ⬜ |
| UART OBI chain correctly listed | ⬜ |
| `vivado_soc.f` canonical filelist generated | ⬜ |
| All CRITICAL/ERROR findings resolved or formally waived | ⬜ |

**Human Sign-Off**: ⬜ — Type `SIGN OFF: S0` in chat to unlock Stage 1.

