"""WSL diagnostic: path-only TB overlay plus passive SRAM/stack observations.

Production sources are untouched. The ROM's unchanged relative default reads
an identical staged image; only unsupported nested defparam syntax is removed
from a temporary TB copy. All checks and SRAM capacities remain intact.
"""
import datetime
import difflib
import hashlib
import json
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
BASE = Path(__file__).resolve().parent
OUT = BASE / ("portable_" + datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
RUN = OUT / "run"
RUN.mkdir(parents=True)
IMAGE = ROOT / "ips/benchmarks/docs/evidence/coremark_report_fix/coremark_20261111T111230Z_dc575342"
TB = ROOT / "ips/benchmarks/tb/soc_benchmark_tb.sv"
records = []


def call(command, label, limit=300, cwd=RUN):
    start = time.monotonic()
    with (RUN / (label + ".log")).open("w") as log:
        try:
            result = subprocess.run([str(x) for x in command], cwd=cwd, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=limit)
            status = result.returncode
        except subprocess.TimeoutExpired:
            status = "wall_timeout"
    records.append({"label": label, "argv": list(map(str, command)), "cwd": str(cwd),
                    "wall_limit_seconds": limit, "wall_seconds": time.monotonic() - start,
                    "return_code": status})
    (RUN / "commands.json").write_text(json.dumps(records, indent=2) + "\n")
    print(label, status, flush=True)
    return status


assert call(["python3", ROOT / "ips/benchmarks/tools/generate_filelists.py", "--root", ROOT,
             "--output-dir", RUN], "filelists", 30) == 0
for name in ["program.elf", "imem.hex", "dmem.hex", "build.json"]:
    shutil.copy2(IMAGE / name, RUN / name)
# boot_rom.sv default is ../mem_files/riscforge_bootrom.hex relative to cwd.
rom = OUT / "mem_files/riscforge_bootrom.hex"
rom.parent.mkdir()
rom_source = ROOT / "ips/benchmarks/runs/coremark_report_fix/coremark_20261111T111230Z_dc575342/riscforge_bootrom.hex"
recorded_hashes = json.loads((IMAGE / "source_hashes.json").read_text())["sha256"]
rom_hash = next(value for path, value in recorded_hashes.items() if path.endswith("/riscforge_bootrom.hex"))
assert hashlib.sha256(rom_source.read_bytes()).hexdigest() == rom_hash
shutil.copy2(rom_source, rom)
hashes = {name: hashlib.sha256((RUN / name).read_bytes()).hexdigest()
          for name in ["program.elf", "imem.hex", "dmem.hex"]}
hashes["boot_rom"] = hashlib.sha256(rom.read_bytes()).hexdigest()
assert hashes["boot_rom"] == rom_hash
(RUN / "image_hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")

original = TB.read_text()
directive = "  defparam dut.i_boot_rom.HEX_FILE = `BENCH_BOOTROM_HEX_FILE;"
assert original.count(directive) == 1
text = original.replace(directive, "  // Diagnostic portability overlay: identical ROM staged at its default path.")
probe = r'''
  // Passive observers: never force signals, drive memory, or change verdicts.
  bit probe_started=0;
  logic [31:0] probe_min_sp=32'h28000, probe_max_sp=0;
  logic [31:0] probe_data_min=32'hffffffff, probe_data_max=0;
  integer probe_sp_outside=0, probe_data_outside=0, probe_samples=0;
  integer probe_lane;
  logic [31:0] probe_byte_address;
  always @(negedge clk_i) if(dut.core_rst_n) begin
    if(dut.i_riscv_core.Decode.rf.Register[2] == 32'h28000) probe_started=1;
    if(probe_started) begin
      if(dut.i_riscv_core.Decode.rf.Register[2] < probe_min_sp)
        probe_min_sp=dut.i_riscv_core.Decode.rf.Register[2];
      if(dut.i_riscv_core.Decode.rf.Register[2] > probe_max_sp)
        probe_max_sp=dut.i_riscv_core.Decode.rf.Register[2];
      if(dut.i_riscv_core.Decode.rf.Register[2] < 32'h21100 ||
         dut.i_riscv_core.Decode.rf.Register[2] > 32'h28000) probe_sp_outside++;
    end
  end
  always @(posedge clk_i) if(dut.core_rst_n &&
      dut.i_riscv_core.lsu_mem_req && !dut.i_riscv_core.lsu_mem_stall) begin
    probe_samples++;
    for(probe_lane=0;probe_lane<4;probe_lane++)
      if(dut.i_riscv_core.lsu_mem_be[probe_lane]) begin
        probe_byte_address=(dut.i_riscv_core.lsu_mem_addr & 32'hfffffffc)+probe_lane;
        if(probe_byte_address<probe_data_min) probe_data_min=probe_byte_address;
        if(probe_byte_address>probe_data_max) probe_data_max=probe_byte_address;
        if(probe_byte_address<32'h20000 || probe_byte_address>=32'h28000) probe_data_outside++;
      end
  end
  task automatic write_sram_probe;
    integer probe_fd;
    begin
      probe_fd=$fopen("sram_probe.json","w");
      $fdisplay(probe_fd,"{");
      $fdisplay(probe_fd,"  \"sp_tracking_started\": %0d,",probe_started);
      $fdisplay(probe_fd,"  \"min_sp\": \"0x%08x\",",probe_min_sp);
      $fdisplay(probe_fd,"  \"max_sp\": \"0x%08x\",",probe_max_sp);
      $fdisplay(probe_fd,"  \"sp_outside_static_free_range_samples\": %0d,",probe_sp_outside);
      $fdisplay(probe_fd,"  \"observed_req_not_stalled_samples\": %0d,",probe_samples);
      $fdisplay(probe_fd,"  \"data_byte_min\": \"0x%08x\",",probe_data_min);
      $fdisplay(probe_fd,"  \"data_byte_max\": \"0x%08x\",",probe_data_max);
      $fdisplay(probe_fd,"  \"data_byte_outside_dsram_samples\": %0d",probe_data_outside);
      $fdisplay(probe_fd,"}");
      $fclose(probe_fd);
    end
  endtask
'''
text = text.replace("  task automatic write_result_json", probe + "\n  task automatic write_result_json", 1)
text = text.replace("        result_written = 1'b1;", "        write_sram_probe();\n        result_written = 1'b1;", 1)
overlay = RUN / "soc_benchmark_tb.sv"
overlay.write_text(text)
(RUN / "tb_overlay.patch").write_text("".join(difflib.unified_diff(original.splitlines(True), text.splitlines(True),
                                      fromfile=str(TB), tofile=str(overlay))))
manifest = RUN / "soc_benchmark_vcs_xcelium.f"
before = manifest.read_text()
lines = before.splitlines()
matches = [i for i, line in enumerate(lines)
           if line.strip().endswith("soc_benchmark_tb.sv") and (RUN / line.strip()).resolve() == TB]
assert len(matches) == 1, matches
lines[matches[0]] = overlay.name
manifest.write_text("\n".join(lines) + "\n")
(RUN / "overlay_identity.json").write_text(json.dumps({
    "production_tb": str(TB), "production_sha256": hashlib.sha256(TB.read_bytes()).hexdigest(),
    "overlay_sha256": hashlib.sha256(overlay.read_bytes()).hexdigest(),
    "changes": ["ROM path selection syntax only; identical image at unchanged default path",
                "Passive architectural SP and req-with-not-stall byte-address observations"],
    "production_rtl_or_tb_changed": False, "limits": "Verilator 2-state/guard semantics; one short run only"}, indent=2) + "\n")
# Verilator 5.020's generated Makefile rejects spaces in CURDIR. Build only
# generated C++ in /tmp, with space-free aliases to the unchanged source files.
work = Path(tempfile.mkdtemp(prefix="rf_sram_"))
execute = work / "run"
execute.mkdir()
alias = work / "source"
alias.symlink_to(ROOT, target_is_directory=True)
def short_path(path):
    return str(alias / path.resolve().relative_to(ROOT))
compile_lines = []
for line in manifest.read_text().splitlines():
    if line.startswith("+incdir+"):
        compile_lines.append("+incdir+" + short_path(RUN / line[len("+incdir+"):]))
    elif line.strip() and not line.startswith(("//", "#", "+", "-")):
        compile_lines.append(short_path(RUN / line.strip()))
    else:
        compile_lines.append(line)
(execute / manifest.name).write_text("\n".join(compile_lines) + "\n")
for name in ["imem.hex", "dmem.hex"]:
    shutil.copy2(RUN / name, execute / name)
(work / "mem_files").mkdir()
shutil.copy2(rom, work / "mem_files/riscforge_bootrom.hex")
(RUN / "space_free_build.json").write_text(json.dumps({"work": str(work), "alias": str(alias),
    "target": str(ROOT), "filelist": str(execute / manifest.name)}, indent=2) + "\n")
rc = call(["verilator", "--binary", "--timing", "--assert", "-DXSIM", "-Wno-fatal",
           "--top-module", "soc_benchmark_tb", "-j", "4", "--Mdir", "obj_dir",
           "-f", manifest.name], "verilator_compile", cwd=execute)
if rc == 0:
    call([execute / "obj_dir/Vsoc_benchmark_tb", "+IMEM_HEX=imem.hex", "+DMEM_HEX=dmem.hex",
          "+RESULT_JSON=result.json", "+TIMEOUT_CYCLES=2000000", "+BENCHMARK_ID=3"], "verilator_run", cwd=execute)
    for name in ["result.json", "sram_probe.json"]:
        if (execute / name).is_file():
            shutil.copy2(execute / name, RUN / name)
print("Evidence:", RUN, flush=True)
