"""Build directed RV32 images and run unmodified base vs candidate core.

This is development verification, not an ISS campaign or a board qualification.
"""
from pathlib import Path
import subprocess, json, struct, hashlib, sys, argparse
SCRIPT=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument('--rtl-root',type=Path)
parser.add_argument('--baseline-rtl',type=Path)
parser.add_argument('--output-dir',type=Path)
args=parser.parse_args()
snapshot=(SCRIPT/'candidate/ips_reorganized/riscv_core/rtl').is_dir()
RTL=(args.rtl_root or (SCRIPT/'candidate/ips_reorganized/riscv_core/rtl' if snapshot else SCRIPT.parents[1]/'riscv_core/rtl')).resolve()
BASE_RTL=args.baseline_rtl or (SCRIPT/'base/ips_reorganized/riscv_core/rtl' if snapshot else None)
ROOT=(args.output_dir or (SCRIPT if snapshot else SCRIPT/'build')).resolve()
ROOT.mkdir(parents=True,exist_ok=True)
def run(args, log):
    p=subprocess.run(args,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (ROOT/'logs').mkdir(exist_ok=True)
    (ROOT/'logs'/log).write_text(p.stdout,encoding='utf-8')
    return p.returncode,p.stdout

common=''' .option norvc
.section .text
.globl _start
_start:
  li s0,0x80001000
'''
finish='''
pass:
  li t0,1
  sw t0,256(s0)
1: j 1b
fail:
  li t0,2
  sw t0,256(s0)
2: j 2b
'''
programs={
'mdu': common+'''
  li t0,9
  li t1,7
  mul t2,t0,t1
  li t3,63
  bne t2,t3,fail
  addi t4,t2,1
  li t3,64
  bne t4,t3,fail
  li t0,-123
  li t1,10
  div t2,t0,t1
  li t3,-12
  bne t2,t3,fail
  rem t2,t0,t1
  li t3,-3
  bne t2,t3,fail
  li t0,-1
  li t1,2
  mulh t2,t0,t1
  li t3,-1
  bne t2,t3,fail
  mulhu t2,t0,t0
  li t3,-2
  bne t2,t3,fail
  mulhsu t2,t0,t0
  bne t2,t0,fail
  divu t2,t0,t1
  li t3,0x7fffffff
  bne t2,t3,fail
  remu t2,t0,t1
  li t3,1
  bne t2,t3,fail
  div t2,t0,zero
  bne t2,t0,fail
  rem t2,t0,zero
  bne t2,t0,fail
  li t0,0x80000000
  li t1,-1
  div t2,t0,t1
  bne t2,t0,fail
  j pass
'''+finish,
'load_mdu':common+'''
  li t0,0x1357
  sw t0,0(s0)
  li t0,7
  li t1,9
  li s1,0x55
  lw s1,0(s0)
  mul s2,t0,t1
  li t3,0x1357
  bne s1,t3,fail
  li t3,63
  bne s2,t3,fail
  lw s3,0(s0)
  lw s4,0(s0)
  add s5,s3,s4
  li t3,0x26ae
  bne s5,t3,fail
  j pass
'''+finish,
'redirect_wait':common+'''
  li t0,77
  sw t0,0(s0)
  lw s1,0(s0)
  jal s2,target
after_call:
  j fail
target:
  la t0,after_call
  bne s2,t0,fail
  li t0,77
  bne s1,t0,fail
  j pass
'''+finish,
'illegal':common+'''
  la t0,handler
  csrw mtvec,t0
  li a3,9
  li s1,0
  li s2,0
  .word 0x460446b3
after_bad:
  li t0,9
  bne a3,t0,fail
  li t0,1
  bne s1,t0,fail
  bne s2,zero,fail
  j pass
handler:
  csrr t0,mcause
  li t1,2
  bne t0,t1,fail
  csrr t0,mepc
  la t1,after_bad
  addi t1,t1,-4
  bne t0,t1,fail
  csrr t0,mtval
  li t1,0x460446b3
  bne t0,t1,fail
  addi s1,s1,1
  la t0,after_bad
  csrw mepc,t0
  mret
'''+finish,
'fetch_fault':common+'''
  la t0,handler
  csrw mtvec,t0
  li s1,0
  li t0,0x90000000
  jalr zero,t0,0
after_fault:
  li t0,1
  bne s1,t0,fail
  j pass
handler:
  csrr t0,mcause
  li t1,1
  bne t0,t1,fail
  csrr t0,mepc
  li t1,0x90000000
  bne t0,t1,fail
  csrr t0,mtval
  bne t0,t1,fail
  addi s1,s1,1
  la t0,after_fault
  csrw mepc,t0
  mret
'''+finish,
'trap_mdu':common+'''
  la t0,handler
  csrw mtvec,t0
  li t0,0x12345678
  li t1,3
  li s1,55
  li s2,0
  ecall
  div s1,t0,t1
after_trap:
  .rept 60
  nop
  .endr
  li t0,55
  bne s1,t0,fail
  li t0,1
  bne s2,t0,fail
  j pass
handler:
  csrr t0,mcause
  li t1,11
  bne t0,t1,fail
  addi s2,s2,1
  la t0,after_trap
  csrw mepc,t0
  mret
'''+finish,
'mepc':common+'''
  li t0,0x80000003
  csrw mepc,t0
  csrr t1,mepc
  li t0,0x80000000
  bne t0,t1,fail
  j pass
'''+finish,
}

def main():
    (ROOT/'programs').mkdir(exist_ok=True)
    result={}
    for name,src in programs.items():
        p=ROOT/'programs'/name
        p.with_suffix('.S').write_text(src,encoding='utf-8')
        cmd=['riscv64-unknown-elf-gcc','-march=rv32im_zicsr','-mabi=ilp32','-nostdlib','-nostartfiles','-Wl,-Ttext=0x80000000','-Wl,--no-relax','-o',str(p.with_suffix('.elf')),str(p.with_suffix('.S'))]
        rc,out=run(cmd,name+'_build.log'); assert rc==0,out
        rc,out=run(['riscv64-unknown-elf-objcopy','-O','binary','-j','.text',str(p.with_suffix('.elf')),str(p.with_suffix('.bin'))],name+'_objcopy.log'); assert rc==0,out
        binary=p.with_suffix('.bin').read_bytes()
        assert len(binary)%4==0
        p.with_suffix('.hex').write_text('\n'.join(f'{x[0]:08x}' for x in struct.iter_unpack('<I',binary))+'\n',encoding='ascii')
    variants=([('base',BASE_RTL)] if BASE_RTL else [])+[('candidate',RTL)]
    for variant,rtl in variants:
        files=sorted(Path(rtl).resolve().glob('*.v'))
        cmd=['iverilog','-g2012','-s','tb_core_port','-o',str(ROOT/(variant+'.vvp'))]
        if variant=='candidate': cmd+=['-DCANDIDATE']
        cmd+=[str(p) for p in files]+[str(SCRIPT/'tb_core_port.sv')]
        rc,out=run(cmd,variant+'_compile.log')
        if rc: print(out); return 1
        for name in programs:
            for wait in ([0,1,4] if name in ['mdu','load_mdu','redirect_wait'] else [2]):
                rc,out=run(['vvp',str(ROOT/(variant+'.vvp')),'+HEX='+str(ROOT/'programs'/(name+'.hex')),'+WAIT='+str(wait)],f'{variant}_{name}_w{wait}.log')
                key=f'{variant}/{name}/wait{wait}'
                result[key]={'exit_code':rc,'pass':rc==0 and 'PASS cycles=' in out,'tail':out.splitlines()[-3:]}
                print(key, 'PASS' if result[key]['pass'] else 'FAIL', flush=True)
    (ROOT/'results.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    return 0 if all(v['pass'] for k,v in result.items() if k.startswith('candidate/')) else 1
if __name__=='__main__': sys.exit(main())
