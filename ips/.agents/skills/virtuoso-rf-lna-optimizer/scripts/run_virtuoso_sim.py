import subprocess, os, re, math

env = os.environ.copy()
env['LM_LICENSE_FILE'] = '5280@14.139.1.126'
env['CDS_LIC_FILE'] = '5280@14.139.1.126'

netlist_content = """// Generated for: spectre
// Design library name: vkv
// Design cell name: LNA_4_5GHz
// Design view name: schematic
simulator lang=spectre
global 0
include "/home/iiita/Documents/RaghulCJAnalog/UMC180/Models/Spectre/mm180_reg18_v124.lib.scs" section=tt
include "/home/iiita/Documents/RaghulCJAnalog/UMC180/Models/Spectre/l_slcr20k_rf_v2d3.lib.scs" section=typ
include "/home/iiita/Documents/RaghulCJAnalog/UMC180/Models/Spectre/mm180_mimcap_v101.lib.scs" section=mimcaps_typ
include "/home/iiita/Documents/RaghulCJAnalog/UMC180/Models/Spectre/mm180_res_v141.lib.scs" section=res_typ

PORT1 (net10 0) port r=50 num=2 type=sine
PORT0 (net1 0) port r=50 num=1 type=sine freq=4.5G
C3 (net8 net10) mimcaps_mm w=15.0u l=15.0u m=1
C6 (net9 net8) mimcaps_mm w=14.7u l=14.7u m=1
C7 (net1 net2) mimcaps_mm w=35u l=35u m=1
R0 (net2 net3) resistor r=5k
V1 (net9 0) vsource dc=1.8 type=dc
V0 (net3 0) vsource dc=0.95 type=dc
L0 (net9 net8 0) l_slcr20k_rf d=100u w=6u n=3.5
L1 (net7 net6 0) l_slcr20k_rf d=80u w=6u n=1.5
L2 (net5 0 0) l_slcr20k_rf d=57u w=6u n=1.5
L3 (net2 net4 0) l_slcr20k_rf d=180u w=6u n=3.5
M1 (net8 net9 net7 0) n_18_mm w=10u l=180n nf=1 mis_flag=1 ad=2.224e-13 as=2.224e-13 pd=2.0u ps=2.0u m=(1)*(16) mf=(1)*(16)
M0 (net6 net4 net5 0) n_18_mm w=10u l=180n nf=1 mis_flag=1 ad=2.224e-13 as=2.224e-13 pd=2.0u ps=2.0u m=(1)*(16) mf=(1)*(16)

simulatorOptions options reltol=1e-3 vabstol=1e-6 iabstol=1e-12 temp=27 tnom=27 checklimitdest=psf 
sp sp ports=[PORT0 PORT1] start=3.5G stop=5.5G step=5M donoise=yes oprobe=PORT1 iprobe=PORT0 annotate=status 
saveOptions options save=allpub
"""

scs_path = "/home/iiita/simulation/LNA_4_5GHz/spectre/schematic/netlist/input.scs"
with open(scs_path, "w") as f:
    f.write(netlist_content)

run_dir = "/home/iiita/simulation/LNA_4_5GHz/spectre/schematic/netlist"
cmd = ["/home/install/SPECTRE211/bin/spectre", "-64", "input.scs", "-format", "psfascii", "-raw", "../psf"]
p = subprocess.run(cmd, cwd=run_dir, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
print("Spectre Return Code:", p.returncode)

psf_sp = "/home/iiita/simulation/LNA_4_5GHz/spectre/schematic/psf/sp.sp"
with open(psf_sp) as f:
    text = f.read()

sp_pattern = re.compile(r'"freq"\s+([0-9.eE+-]+)\s+"s11"\s+\(([0-9.eE+-]+)\s+([0-9.eE+-]+)\)\s+"s21"\s+\(([0-9.eE+-]+)\s+([0-9.eE+-]+)\)\s+"s12"\s+\(([0-9.eE+-]+)\s+([0-9.eE+-]+)\)\s+"s22"\s+\(([0-9.eE+-]+)\s+([0-9.eE+-]+)\)')
matches = sp_pattern.findall(text)

freqs = [float(m[0])/1e9 for m in matches]
s21s = [20*math.log10(abs(complex(float(m[3]), float(m[4])))) for m in matches]
s11s = [20*math.log10(abs(complex(float(m[1]), float(m[2])))) for m in matches]
s22s = [20*math.log10(abs(complex(float(m[7]), float(m[8])))) for m in matches]
s12s = [20*math.log10(abs(complex(float(m[5]), float(m[6])))) for m in matches]

max_i = max(range(len(s21s)), key=lambda i: s21s[i])
i_45 = min(range(len(freqs)), key=lambda i: abs(freqs[i] - 4.500))

print("\n" + "="*65)
print(f"VIRTUOSO ACTUAL SIMULATION RUN SUMMARY:")
print(f"Directory: /home/iiita/simulation/LNA_4_5GHz/spectre/schematic/psf")
print(f"PEAK GAIN (S21):  {s21s[max_i]:.3f} dB @ {freqs[max_i]:.3f} GHz")
print(f"AT EXACT 4.50 GHz:")
print(f"  - Gain (S21):             {s21s[i_45]:.3f} dB")
print(f"  - Input Return Loss (S11): {s11s[i_45]:.3f} dB")
print(f"  - Output Return Loss (S22):{s22s[i_45]:.3f} dB")
print(f"  - Reverse Isolation (S12):{s12s[i_45]:.3f} dB")
print("="*65)
