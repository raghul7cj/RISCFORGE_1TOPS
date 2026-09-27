---
name: virtuoso-rf-lna-optimizer
description: >-
  Use this skill for automated simulation, parametric tuning, and schematic generation of RF CMOS Low Noise Amplifiers (LNAs) in Cadence Virtuoso and Spectre using the UMC 180nm RF PDK. Covers remote EDA server automation, batch Spectre S-parameter simulation, resonance tuning rules, and Cadence SKILL (.il) scripting for schematic and ADE L state management.
---

# Cadence Virtuoso RF CMOS LNA Optimizer & Automation Runbook

This skill encapsulates the complete workflow for designing, tuning, simulating, and automating RF Low Noise Amplifiers (LNAs) in Cadence Virtuoso and Spectre on the remote EDA server using the UMC 0.18µm RF CMOS PDK.

---

## 1. Remote Server & EDA Tool Environment

* **Remote Host IP:** `172.16.33.51`
* **Username / Credentials:** `iiita` / `vishal6776`
* **EDA Tool Suite:** Cadence IC618 (Virtuoso) & SPECTRE211
* **Cadence CSH Environment Setup:**
  ```csh
  source /home/install/cshrc
  setenv LM_LICENSE_FILE 5280@14.139.1.126
  setenv CDS_LIC_FILE 5280@14.139.1.126
  ```
* **Project Working Directory:** `/home/iiita/Documents/RaghulCJAnalog/`
* **Target Library:** `vkv`

### Foundry Model Paths (UMC 180nm RF):
* **NMOS Transistors (`N_18_MM`):** `/home/iiita/Documents/RaghulCJAnalog/UMC180/Models/Spectre/mm180_reg18_v124.lib.scs` (`section=tt`)
* **Spiral Inductors (`L_SLCR20K_RF`):** `/home/iiita/Documents/RaghulCJAnalog/UMC180/Models/Spectre/l_slcr20k_rf_v2d3.lib.scs` (`section=typ`)
* **MIM Capacitors (`MIMCAPS_MM`):** `/home/iiita/Documents/RaghulCJAnalog/UMC180/Models/Spectre/mm180_mimcap_v101.lib.scs` (`section=mimcaps_typ`)
* **Resistors:** `/home/iiita/Documents/RaghulCJAnalog/UMC180/Models/Spectre/mm180_res_v141.lib.scs` (`section=res_typ`)

---

## 2. RF LNA Architecture (Inductive Source-Degenerated Cascode)

* **Input Stage ($M_0$):** Common-source RF NMOS with gate bias $V_0$ through choke resistor $R_0 = 5\,\text{k}\Omega$.
* **Source Degeneration ($L_2$):** Generates real $50\,\Omega$ input impedance:
  $$Z_{in} \approx s(L_3 + L_2) + \frac{1}{s C_{gs}} + \left(\frac{g_m}{C_{gs}}\right) L_2$$
  Setting $\omega_T L_2 = 50\,\Omega$ matches input to source without adding thermal noise.
* **Gate Tuning Inductor ($L_3$):** Resonates out $C_{gs} + C_{ex}$ at the center frequency $\omega_0$.
* **Cascode Stage ($M_1$):** Eliminates Miller effect on $C_{gd0}$, boosts reverse isolation ($S_{12} < -30\,\text{dB}$), improves output impedance.
* **Output Tank ($L_0 \parallel C_6$):** Tunes the drain load impedance to resonate at $\omega_0$:
  $$f_0 = \frac{1}{2\pi \sqrt{L_0 (C_6 + C_{ds1} + C_{ext})}}$$
* **Output Match ($C_3$):** Series DC blocking capacitor transformed into capacitive impedance divider for $50\,\Omega$ load.

---

## 3. Component Tuning & Frequency Steering Rules

When moving or locking center frequencies (e.g. 2.4 GHz, 4.5 GHz, 5.0 GHz) or fixing frequency offset errors:

| Problem / Symptom | Parameter to Tweak | Physical Mechanism | Direction of Change |
| :--- | :--- | :--- | :--- |
| **Peak frequency is too high** (e.g. at 4.75 GHz instead of 4.5 GHz) | **$C_6$ (Output Tank Cap)** | Increases tank capacitance, lowering $f_0 = \frac{1}{2\pi\sqrt{LC}}$ | **Increase $w$ and $l$** (e.g. $10.5\mu\text{m} \to 14.7\mu\text{m}$) |
| **Peak frequency is too low** | **$C_6$ (Output Tank Cap)** | Decreases tank capacitance, raising $f_0$ | **Decrease $w$ and $l$** |
| **$S_{11}$ notch is off-frequency** | **$L_3$ (Gate Inductor)** | Cancels gate reactance at $\omega_0$ | Increase $d$ to lower input freq, decrease $d$ to raise |
| **$S_{11}$ depth insufficient** ($> -10\,\text{dB}$) | **$L_2$ (Source Inductor)** | Adjusts real part $\omega_T L_2 \approx 50\,\Omega$ | Adjust diameter $d$ ($50\mu\text{m} - 60\mu\text{m}$) |
| **Output return loss $S_{22}$ degraded** | **$C_3$ (Output Cap)** | Adjusts load coupling into $50\,\Omega$ | Tune $w, l$ ($14\mu\text{m} - 16\mu\text{m}$) |
| **Gain ($S_{21}$) too low** | **$V_0$ (Gate Bias)** | Increases $V_{GS} - V_{th}$, boosting $g_m$ | Increase $V_0$ (e.g. $0.90\text{V} \to 0.95\text{V}$) |

---

## 4. Automated Batch Spectre Simulation (Zero GUI Overhead)

Run simulations via SSH headless Spectre to sweep parameters and extract exact PSF S-parameters in seconds:

```python
import subprocess, os, re, math

env = os.environ.copy()
env['LM_LICENSE_FILE'] = '5280@14.139.1.126'
env['CDS_LIC_FILE'] = '5280@14.139.1.126'

# 1. Run Spectre directly
cmd = [
    "/home/install/SPECTRE211/bin/spectre", "-64",
    "input.scs", "-format", "psfascii", "-raw", "../psf"
]
subprocess.run(cmd, cwd=netlist_dir, env=env)

# 2. Parse PSF ASCII S-parameter file
with open("../psf/sp.sp") as f:
    text = f.read()

# Pattern for multi-port S-parameters
pattern = re.compile(
    r'"freq"\s+([0-9.eE+-]+)\s+"s11"\s+\(([0-9.eE+-]+)\s+([0-9.eE+-]+)\)'
    r'\s+"s21"\s+\(([0-9.eE+-]+)\s+([0-9.eE+-]+)\)'
    r'\s+"s12"\s+\(([0-9.eE+-]+)\s+([0-9.eE+-]+)\)'
    r'\s+"s22"\s+\(([0-9.eE+-]+)\s+([0-9.eE+-]+)\)'
)
# S21 (dB) = 20 * log10(sqrt(re^2 + im^2))
```

---

## 5. Cadence SKILL (.il) Scripting Automation

### A. Creating & Updating Schematic Cellviews:
To programmatically generate or update schematics with true OpenAccess wires, labels, pins, and instances:
```lisp
cv = dbOpenCellViewByType("vkv" "LNA_4_5GHz" "schematic" "schematic" "a")
; Update parameter on an instance
foreach(inst cv~>instances
  when(inst~>name == "C6"
    inst~>w = "14.7u"
    inst~>l = "14.7u"
  )
)
schCheck(cv)
dbSave(cv)
dbClose(cv)
```

### B. ADE L Saved State Generation:
ADE L reads states from two locations:
1. **Directory State:** `/home/iiita/.artist_states/<lib>/<cell>/spectre/<statename>/`
2. **Cellview State:** OpenAccess view `<cell>/spectre_state1`

Copying existing valid state templates into the cell's state directory instantly enables `Session -> Load State` inside Virtuoso GUI.
