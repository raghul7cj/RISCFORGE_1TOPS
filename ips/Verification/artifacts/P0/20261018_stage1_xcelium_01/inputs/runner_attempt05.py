#!/usr/bin/env python3
"""Run the frozen stage1 snapshot with Xcelium; retain every command and log."""
import os, sys, json, hashlib, subprocess, pathlib, datetime, re
base = pathlib.Path(__file__).resolve().parent
src = base / 'snapshot'
out = base / 'results'
for name in ('logs','inputs','checks','work','mem_files'):
    (out/name).mkdir(parents=True, exist_ok=True)
os.environ.update(LM_LICENSE_FILE='5280@14.139.1.126', CDS_LIC_FILE='5280@14.139.1.126', CDS_AUTO_64BIT='ALL')
os.environ['PATH']='/home/install/XCELIUM2409/tools/bin:/home/install/XCELIUM2409/bin:'+os.environ['PATH']
commands=[]
def run(args, log, cwd=src, timeout=240):
    commands.append({'argv':[str(x) for x in args], 'cwd':str(cwd),'log':log,'timeout_seconds':timeout})
    (out/'commands.json').write_text(json.dumps(commands,indent=2))
    with (out/'logs'/log).open('w') as f:
        try:
            p=subprocess.run([str(x) for x in args],cwd=str(cwd),stdout=f,stderr=subprocess.STDOUT,timeout=timeout)
            rc=p.returncode
        except subprocess.TimeoutExpired:
            f.write('\nHOST_TIMEOUT\n'); rc=124
    commands[-1]['exit_code']=rc
    (out/'commands.json').write_text(json.dumps(commands,indent=2))
    return rc
status={'scenario':'stage1_hello','boot_mode':'WARM','seed':1,'verdict':'INCOMPLETE','started_utc':datetime.datetime.utcnow().isoformat()+'Z','environment':{k:os.environ[k] for k in ('LM_LICENSE_FILE','CDS_LIC_FILE','CDS_AUTO_64BIT')}}
def save():
    status['finished_utc']=datetime.datetime.utcnow().isoformat()+'Z'
    (out/'manifest.json').write_text(json.dumps(status,indent=2))
def stop(reason):
    status['reason']=reason; save(); print(reason); sys.exit(0)
(out/'checks'/'artifact_write_test.txt').write_text('P0 artifact write/read test\n')
assert (out/'checks'/'artifact_write_test.txt').read_text()=='P0 artifact write/read test\n'
run(['hostname'],'host.log')
if run(['xrun','-version'],'tool_version.log'): stop('Xcelium unavailable')
status['tool_version']=(out/'logs'/'tool_version.log').read_text().strip()
gcc='riscv64-unknown-elf-gcc'
if run([gcc,'--version'],'compiler_version.log'): stop('Compiler unavailable')
if run(['python3','Verification/infrastructure/gen_filelists.py','--emit','--print-cmd'],'filelist_preflight.log'): stop('Filelist preflight failed')
f=src/'Verification/infrastructure/soc_verification.esi.f'
original=f.read_text()
(out/'inputs'/'generated_original.f').write_text(original)
# FSDB is a Verdi PLI integration; this run uses no waveform dumping.
effective='\n'.join(x for x in original.splitlines() if x.strip()!='+define+FSDB' and not x.lstrip().startswith('$$define '))+'\n'
fl=out/'inputs'/'xcelium.f'; fl.write_text(effective)
(out/'checks'/'filelist_difference.txt').write_text('Removed +define+FSDB (no Verdi PLI) and invalid $$define top metadata (top supplied with -top). Source/include order unchanged.\n')
status['filelist_sha256']=hashlib.sha256(effective.encode()).hexdigest()
# Stock boot-ROM content from boot_rom.sv; fill complete 16-word ROM.
(out/'mem_files'/'riscforge_bootrom.hex').write_text('00028137\n7fd0f06f\n'+'00000013\n'*14)
bsp='Verification/tests/bsp'; drv='Verification/tests/drivers'
elf=out/'inputs'/'stage1.elf'
args=[gcc,'-march=rv32im_zicsr','-mabi=ilp32','-mcmodel=medlow','-mno-relax','-O2','-g','-ffreestanding','-nostdlib','-I'+bsp,'-I'+drv,'-T',bsp+'/link.ld',bsp+'/crt0.s',bsp+'/trap_handler.s',bsp+'/isr_dispatch.c',bsp+'/proof_activity.c']
args += [drv+'/'+n+'_driver.c' for n in ('uart','timer','gpio','i2c','spi')]
args += ['Verification/tests/suites/stage1_hello/main.c','-o',str(elf)]
if run(args,'firmware_build.log'): stop('Firmware build failed')
imem=out/'inputs'/'stage1_imem.hex'; dmem=out/'inputs'/'stage1_dmem.hex'
if run(['python3','Verification/regression/elf_to_hex_clean.py',elf,imem,dmem],'image_conversion.log'): stop('Image conversion failed')
run(['riscv64-unknown-elf-objdump','-d',elf],'firmware_disassembly.log')
for p in (elf,imem,dmem,out/'mem_files'/'riscforge_bootrom.hex'):
    status.setdefault('input_hashes',{})[p.name]=hashlib.sha256(p.read_bytes()).hexdigest()
lib=out/'work'/'xcelium.d'
args=['xrun','-64bit','-sv','-timescale','1ns/1ps','-access','+rwc','-f',fl,'-top','soc_tb_top','-elaborate','-xmlibdirname',lib,'-l',out/'logs'/'elaborate_tool.log']
if run(args,'elaborate_console.log',out/'work'): stop('Compilation/elaboration failed')
args=['xrun','-64bit','-R','-xmlibdirname',lib,'-svseed','1','+BOOT_MODE=WARM','+IMEM_HEX='+str(imem),'+DMEM_HEX='+str(dmem),'+TIMEOUT=1000000','-l',out/'logs'/'simulation_tool.log']
status['plusargs']=[x for x in args if str(x).startswith('+')]
rc=run(args,'simulation_console.log',out/'work',240)
sim=(out/'logs'/'simulation_console.log').read_text(errors='replace')
status['simulator_exit_code']=rc
status['verdict']='PASS' if rc==0 and '[MAILBOX PASS]' in sim and not re.search(r'\[FATAL|\[MAILBOX FAIL\]|VACUITY VIOLATION|\*E,|\*F,',sim) else 'FAIL'
status['scope']='Stage1 execution verdict only; canonical module inventory comparison and explicit attestation write counting not implemented, so full P0 closure is not claimed.'
status['reason']='See simulation logs and counter extracts.'
(out/'counters.txt').write_text('\n'.join(x for x in sim.splitlines() if re.search(r'retired|AXI=|APB=|attestation|axi writes|apb transfers|minstret|TIMEOUT|MAILBOX|FATAL',x,re.I))+'\n')
save(); print(json.dumps(status,indent=2))