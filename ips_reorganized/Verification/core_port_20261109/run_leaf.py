from pathlib import Path
import argparse,subprocess
S=Path(__file__).resolve().parent
p=argparse.ArgumentParser()
p.add_argument('--rtl-root',type=Path,default=S.parents[1]/'riscv_core/rtl')
p.add_argument('--output-dir',type=Path,default=S/'build')
a=p.parse_args()
a.output_dir.mkdir(parents=True,exist_ok=True)
files=sorted(a.rtl_root.resolve().glob('*.v'))
for top,source in [('tb_legality','tb_legality.sv'),('tb_mdu_owner','tb_mdu_owner.sv')]:
    exe=a.output_dir/(top+'.vvp')
    cmd=['iverilog','-g2012','-s',top,'-o',str(exe),*[str(x) for x in files],str(S/source)]
    r=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (a.output_dir/(top+'_compile.log')).write_text(r.stdout)
    if r.returncode: raise SystemExit(r.returncode)
    r=subprocess.run(['vvp',str(exe)],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (a.output_dir/(top+'.log')).write_text(r.stdout)
    print(r.stdout)
    if r.returncode: raise SystemExit(r.returncode)
