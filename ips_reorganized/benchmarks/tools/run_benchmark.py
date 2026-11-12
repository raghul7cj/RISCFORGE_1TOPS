#!/usr/bin/env python3
"""Build and run a reproducible full-SoC benchmark campaign."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any

from generate_filelists import FilelistError, generate_filelists
from analyze_results import analyze_file


ROOT = Path(__file__).resolve().parents[3]
CONTRACT_PATH = ROOT / "ips/benchmarks/contract.json"
MODELED_CLOCK_HZ = 100_000_000
MEMORY_RANGES = ((0x0001_0000, 0x0001_8000, "ISRAM"), (0x0002_0000, 0x0002_8000, "DSRAM"))
BENCHMARK_SOURCE_INVENTORY = {
    "coremark": {
        "ports": ("ports/coremark/core_portme.c", "ports/coremark/core_portme.h"),
        "upstream_files_compiled": tuple("vendor/upstream/coremark/" + name for name in
                                         ("core_list_join.c", "core_matrix.c", "core_state.c", "core_util.c")),
    },
    "dhrystone": {
        "ports": tuple("ports/dhrystone/" + name for name in
                       ("dhrystone_port.c", "util.h", "alloca.h", "stdio.h", "string.h")),
        "upstream_files_compiled": ("vendor/upstream/dhrystone/benchmarks/dhrystone/dhrystone.c",),
    },
}
PORTED_SOURCE_OUTPUTS = {
    "coremark": {"coremark_main_ported": "ported/core_main.c"},
    "dhrystone": {"dhrystone_main_ported": "ported/dhrystone/dhrystone_main.c",
                  "dhrystone_header_ported": "ported/dhrystone/dhrystone.h"},
}


class PreflightError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _find_values(node: Any, keys: set[str]) -> list[Any]:
    found: list[Any] = []
    if isinstance(node, dict):
        for key, value in node.items():
            normalized = str(key).replace("-", "_").lower()
            if normalized in keys:
                found.append(value)
            found.extend(_find_values(value, keys))
    elif isinstance(node, list):
        for value in node:
            found.extend(_find_values(value, keys))
    return found


def _as_int_candidates(values: list[Any]) -> list[int]:
    result: list[int] = []
    for value in values:
        if isinstance(value, bool):
            continue
        try:
            result.append(int(value, 0) if isinstance(value, str) else int(value))
        except (TypeError, ValueError):
            continue
    return result


def _read_hex_words(path: Path, label: str) -> dict[int, int]:
    if not path.is_file():
        raise PreflightError(f"missing {label} image: {path}")
    addresses: dict[int, int] = {}
    address = 0
    for line_number, raw in enumerate(path.read_text(encoding="ascii", errors="strict").splitlines(), 1):
        line = raw.split("//", 1)[0].split("#", 1)[0].strip().replace("_", "")
        if not line:
            continue
        if line.startswith("@") and re.fullmatch(r"@[0-9a-fA-F]+", line):
            address = int(line[1:], 16)
            if address >= 8192:
                raise PreflightError(f"{label} address at line {line_number} is outside 8192-word SRAM")
            continue
        if not re.fullmatch(r"[0-9a-fA-F]{1,8}", line):
            raise PreflightError(f"{label} image has unsupported hex at line {line_number}: {line!r}")
        if address >= 8192:
            raise PreflightError(f"{label} word at line {line_number} is outside 8192-word SRAM")
        if address in addresses:
            raise PreflightError(f"{label} repeats word address {address:#x} at line {line_number}")
        addresses[address] = int(line, 16)
        address += 1
    if not addresses:
        raise PreflightError(f"{label} image is empty: {path}")
    return addresses


def _validate_hex_image(path: Path, label: str) -> int:
    return len(_read_hex_words(path, label))


def inspect_elf(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise PreflightError(f"missing program ELF: {path}")
    data = path.read_bytes()
    if len(data) < 52 or data[:4] != b"\x7fELF":
        raise PreflightError("program.elf is not a complete ELF image")
    if data[4] != 1 or data[5] != 1:
        raise PreflightError("program.elf must be ELF32 little-endian")
    header = struct.unpack_from("<HHIIIIIHHHHHH", data, 16)
    machine = header[1]
    entry = header[3]
    flags = header[6]
    phoff = header[4]
    phentsize = header[8]
    phnum = header[9]
    if machine != 243:
        raise PreflightError(f"program.elf e_machine is {machine}; expected RISC-V (243)")
    if entry != 0x0001_0000:
        raise PreflightError("program.elf entry must match the BootROM destination 0x00010000")
    if flags & 0x7:
        raise PreflightError("program.elf advertises compressed instructions or a floating-point ABI")
    if phentsize < 32 or phoff + phentsize * phnum > len(data):
        raise PreflightError("program.elf has an invalid program-header table")
    segments: list[dict[str, Any]] = []
    for index in range(phnum):
        values = struct.unpack_from("<IIIIIIII", data, phoff + index * phentsize)
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = values
        if p_type != 1 or p_memsz == 0:
            continue
        if p_filesz > p_memsz:
            raise PreflightError(f"program.elf PT_LOAD[{index}] file size exceeds memory size")
        address = p_paddr if p_paddr else p_vaddr
        end = address + p_memsz
        if p_offset + p_filesz > len(data):
            raise PreflightError(f"program.elf PT_LOAD[{index}] extends past EOF")
        mapped = next((name for start, limit, name in MEMORY_RANGES if start <= address and end <= limit), None)
        if mapped is None:
            raise PreflightError(
                f"program.elf PT_LOAD[{index}] [{address:#010x}, {end:#010x}) is outside ISRAM/DSRAM"
            )
        segments.append({
            "index": index,
            "address_start": f"0x{address:08x}",
            "address_end_exclusive": f"0x{end:08x}",
            "file_bytes": p_filesz,
            "memory_bytes": p_memsz,
            "memory": mapped,
            "flags": p_flags,
        })
    if not segments:
        raise PreflightError("program.elf contains no nonempty PT_LOAD segments")
    return {"elf_class": 32, "machine": "RISC-V", "load_segments": segments}


def verify_images_match_elf(elf_path: Path, imem_path: Path, dmem_path: Path) -> None:
    """Compare actual preload contents with ELF load bytes and zero-fill areas."""
    images = {
        "ISRAM": bytearray(32768),
        "DSRAM": bytearray(32768),
    }
    for name, path in (("ISRAM", imem_path), ("DSRAM", dmem_path)):
        for address, value in _read_hex_words(path, name).items():
            struct.pack_into("<I", images[name], address * 4, value)
    if any(images["DSRAM"][:256]):
        raise PreflightError("the reserved result block must be empty before firmware starts")

    data = elf_path.read_bytes()
    header = struct.unpack_from("<HHIIIIIHHHHHH", data, 16)
    phoff, phentsize, phnum = header[4], header[8], header[9]
    covered = {name: bytearray(32768) for name in images}
    for index in range(phnum):
        segment = struct.unpack_from("<IIIIIIII", data, phoff + index * phentsize)
        kind, file_offset, virtual, physical, file_size, memory_size, _, _ = segment
        if kind != 1 or memory_size == 0:
            continue
        address = physical if physical else virtual
        region = next((item for item in MEMORY_RANGES
                       if item[0] <= address and address + memory_size <= item[1]), None)
        if region is None:
            raise PreflightError("ELF segment escaped SRAM during image comparison")
        origin, _, name = region
        start = address - origin
        end = start + memory_size
        if any(covered[name][start:end]):
            raise PreflightError("overlapping ELF load segments are not supported")
        covered[name][start:end] = b"\x01" * memory_size
        expected = data[file_offset:file_offset + file_size] + bytes(memory_size - file_size)
        if images[name][start:end] != expected:
            raise PreflightError(f"{name} hex contents do not match program.elf PT_LOAD[{index}]")

    # The builder and the TB both initialize unloaded SRAM bytes to zero.
    # Neither a full nor a sparse image may hide extra code/data outside ELF.
    for name, image in images.items():
        for offset in range(0, len(image), 4):
            if any(covered[name][offset:offset + 4]):
                continue
            value = struct.unpack_from("<I", image, offset)[0]
            if value != 0:
                raise PreflightError(f"{name} image contains data outside the ELF at word {offset // 4:#x}")


def validate_build_provenance(build: dict, firmware_dir: Path,
                              benchmark_root: Path | None = None) -> dict[str, int]:
    """Check a completed build's declared source and output fingerprints."""
    if build.get("build_status") != "complete":
        raise PreflightError("build.json must describe a completed build")
    if build.get("benchmark") not in ("smoke", "counter_probe", "coremark", "dhrystone"):
        raise PreflightError("completed build.json must identify its benchmark at the top level")
    benchmark_root = (benchmark_root or (ROOT / "ips/benchmarks")).resolve()
    sources = build.get("source_hashes")
    groups = ("firmware", "ports", "upstream_files_compiled", "build_tools")
    if not isinstance(sources, dict) or not all(isinstance(sources.get(group), dict) for group in groups):
        raise PreflightError("build.json source_hashes groups are missing or malformed")
    for group, required in BENCHMARK_SOURCE_INVENTORY.get(build["benchmark"], {}).items():
        missing = set(required) - sources[group].keys()
        if missing:
            raise PreflightError(f"missing required {build['benchmark']} {group} source hashes: " + ", ".join(sorted(missing)))
    entries = {}
    for group in groups:
        for relative, expected in sources[group].items():
            if relative in entries and entries[relative] != expected:
                raise PreflightError("conflicting source hashes in build.json")
            entries[relative] = expected
    entries["firmware/linker.ld"] = sources.get("linker_script")
    entries["vendor/sources.lock.json"] = sources.get("source_lock")
    required_sources = {"firmware/benchmark.h", "firmware/start.S", "firmware/runtime.c",
                        "tools/build_firmware.py", "tools/fetch_sources.py"}
    if build.get("benchmark") in ("smoke", "counter_probe"):
        required_sources.add(f"firmware/{build['benchmark']}.c")
    if not required_sources.issubset(entries):
        raise PreflightError("build.json omits required firmware/tool source hashes")

    def check_recorded_files(base, records, label):
        for relative, expected in records.items():
            if not isinstance(relative, str) or not isinstance(expected, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", expected):
                raise PreflightError(f"malformed {label} SHA-256 record")
            path = (base / relative).resolve()
            if Path(relative).is_absolute() or not path.is_relative_to(base.resolve()):
                raise PreflightError(f"{label} path escapes its source/output directory")
            if not path.is_file() or sha256(path) != expected.lower():
                raise PreflightError(f"{label} SHA-256 mismatch: {relative}; rebuild against this source checkout")

    check_recorded_files(benchmark_root, entries, "source")
    lock = json.loads((benchmark_root / "vendor/sources.lock.json").read_text(encoding="utf-8"))
    if build.get("source_pins") != lock:
        raise PreflightError("build.json source pins do not match the checked source lock")
    outputs = build.get("output_hashes")
    if not isinstance(outputs, dict) or not {"program.elf", "imem.hex", "dmem.hex"}.issubset(outputs):
        raise PreflightError("build.json must record ELF and SRAM output hashes; rebuild the firmware")
    check_recorded_files(firmware_dir.resolve(), outputs, "output")
    ported = sources.get("ported_build_copies")
    if not isinstance(ported, dict):
        raise PreflightError("build.json ported source hashes are malformed")
    for name, output_path in PORTED_SOURCE_OUTPUTS.get(build["benchmark"], {}).items():
        if name not in ported or output_path not in outputs or ported[name] != outputs[output_path]:
            raise PreflightError(f"missing or inconsistent benchmark ported source: {output_path}")
    ported_output_hashes = {value for name, value in outputs.items() if name.startswith("ported/")}
    if any(not isinstance(value, str) or value not in ported_output_hashes for value in ported.values()):
        raise PreflightError("ported source hashes do not match the staged build-local source copies")
    return {"source_files_verified": len(entries), "output_files_verified": len(outputs)}


def validate_firmware(firmware_dir: Path, benchmark: str, benchmark_id: int, compile_only: bool) -> dict[str, Any]:
    firmware_dir = firmware_dir.resolve()
    build_path = firmware_dir / "build.json"
    imem_path = firmware_dir / "imem.hex"
    dmem_path = firmware_dir / "dmem.hex"
    if not imem_path.is_file() or not dmem_path.is_file():
        raise PreflightError("firmware-dir must contain imem.hex and dmem.hex")
    imem_words = _validate_hex_image(imem_path, "IMEM")
    dmem_words = _validate_hex_image(dmem_path, "DMEM")
    if not build_path.is_file():
        raise PreflightError("firmware-dir must contain build.json")
    build = json.loads(build_path.read_text(encoding="utf-8"))
    if not isinstance(build, dict):
        raise PreflightError("build.json must contain a JSON object")

    benchmark_values = _find_values(build, {"benchmark", "benchmark_name"})
    benchmark_names: list[str] = []
    for value in benchmark_values:
        if isinstance(value, dict):
            name = value.get("name") or value.get("benchmark_name")
            if name is not None:
                benchmark_names.append(str(name).lower())
        elif isinstance(value, str):
            benchmark_names.append(value.lower())
    id_raw_values = _find_values(build, {"benchmark_id"})
    iteration_raw_values = _find_values(build, {"iterations", "iteration_count"})
    # Accommodate the compact nested shape {"benchmark": {"name", "id", ...}}.
    for node in _walk_dicts(build):
        nested = node.get("benchmark")
        if isinstance(nested, dict):
            if "id" in nested:
                id_raw_values.append(nested["id"])
            if "benchmark_id" in nested:
                id_raw_values.append(nested["benchmark_id"])
            if "iterations" in nested:
                iteration_raw_values.append(nested["iterations"])
            if "iteration_count" in nested:
                iteration_raw_values.append(nested["iteration_count"])
    id_values = _as_int_candidates(id_raw_values)
    iteration_values = _as_int_candidates(iteration_raw_values)
    arch_values = _find_values(build, {"arch", "architecture", "march", "isa"})
    arch_strings = [str(value).lower() for value in arch_values if isinstance(value, (str, int))]

    if not compile_only:
        provenance = validate_build_provenance(build, firmware_dir)
        if not benchmark_names or any(name != benchmark for name in benchmark_names):
            raise PreflightError(f"build.json must supply benchmark={benchmark!r}")
        if not id_values or any(value != benchmark_id for value in id_values):
            raise PreflightError(f"build.json must supply numeric benchmark id {benchmark_id}")
        if not iteration_values or any(value <= 0 for value in iteration_values) or len(set(iteration_values)) != 1:
            raise PreflightError("build.json must supply a positive numeric iteration count")
        elf_info = inspect_elf(firmware_dir / "program.elf")
        verify_images_match_elf(firmware_dir / "program.elf", imem_path, dmem_path)
        if not arch_strings or any(value not in ("rv32im_zicsr", "rv32i_zicsr") for value in arch_strings):
            raise PreflightError("build.json must identify rv32im_zicsr or rv32i_zicsr")
    else:
        provenance = {"compile_only_fixture": True}
        elf_path = firmware_dir / "program.elf"
        elf_info = inspect_elf(elf_path) if elf_path.exists() else {"compile_only_fixture": True}

    return {
        "firmware_dir": str(firmware_dir),
        "build_json": build,
        "build_json_sha256": sha256(build_path),
        "program_elf_sha256": sha256(firmware_dir / "program.elf") if (firmware_dir / "program.elf").is_file() else None,
        "imem_sha256": sha256(imem_path),
        "dmem_sha256": sha256(dmem_path),
        "imem_word_count": imem_words,
        "dmem_word_count": dmem_words,
        "elf_validation": elf_info,
        "declared_architectures": arch_strings,
        "declared_iteration_counts": iteration_values,
        "provenance_verification": provenance,
    }


def _walk_dicts(node: Any):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _walk_dicts(value)
    elif isinstance(node, list):
        for value in node:
            yield from _walk_dicts(value)


def verify_source_snapshot(record: dict, root: Path = ROOT) -> dict[str, int]:
    """Detect changes between source fingerprinting and tool consumption."""
    records = [(root / relative, expected) for relative, expected in record["sha256"].items()]
    output = Path(record["filelist_path_base"])
    records.extend((output / name, expected) for name, expected in record["generated_sha256"].items())
    changed = [str(path) for path, expected in records if not path.is_file() or sha256(path) != expected]
    if changed:
        raise PreflightError("compile inputs changed after fingerprinting: " + ", ".join(changed))
    return {"source_and_generated_files_rechecked": len(records)}


def _find_tool(tool_bin: Path | None, candidates: list[str]) -> Path:
    if tool_bin is not None:
        base = tool_bin.resolve()
        if base.is_file():
            if base.name.lower() in {name.lower() for name in candidates}:
                return base
            raise PreflightError(f"--tool-bin file must name one of: {', '.join(candidates)}")
        for candidate in candidates:
            path = base / candidate
            if path.is_file():
                return path
        raise PreflightError(f"none of {', '.join(candidates)} exists under --tool-bin {base}")
    for candidate in candidates:
        resolved = shutil.which(candidate)
        if resolved:
            return Path(resolved)
    raise PreflightError(f"simulator executable not found: {', '.join(candidates)}")


def _run_command(
    executable: Path,
    args: list[str],
    cwd: Path,
    log_path: Path,
    timeout_seconds: float,
    metadata: dict[str, Any],
) -> int:
    argv = [str(executable), *map(str, args)]
    is_batch = executable.suffix.lower() in {".bat", ".cmd"}
    if os.name == "nt" and is_batch:
        command: Any = subprocess.list2cmdline(argv)
        shell = True
    else:
        command = argv
        shell = False
    started = time.monotonic()
    entry = {"command": argv, "cwd": str(cwd), "log": str(log_path), "timeout_seconds": timeout_seconds}
    metadata.setdefault("commands", []).append(entry)
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        log.write("COMMAND: " + subprocess.list2cmdline(argv) + "\n")
        log.flush()
        popen_args: dict[str, Any] = {
            "cwd": str(cwd),
            "stdout": log,
            "stderr": subprocess.STDOUT,
            "shell": shell,
        }
        if os.name == "nt":
            popen_args["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
        else:
            popen_args["start_new_session"] = True
        proc = subprocess.Popen(command, **popen_args)
        try:
            return_code = proc.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            entry["timed_out"] = True
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True, check=False)
            else:
                import signal
                os.killpg(proc.pid, signal.SIGKILL)
            return_code = proc.wait(timeout=30)
            entry["duration_seconds"] = round(time.monotonic() - started, 3)
            entry["return_code"] = return_code
            raise TimeoutError(f"hard wall timeout expired for {executable.name}; see {log_path}")
    entry["duration_seconds"] = round(time.monotonic() - started, 3)
    entry["return_code"] = return_code
    return return_code


def _write_xsim_options(path: Path, plusargs: list[str]) -> None:
    """Keep NAME=value operands out of the Windows batch launcher's parser."""
    path.write_text(
        "".join(f'-testplusarg "{value.removeprefix("+")}"\n' for value in plusargs),
        encoding="utf-8",
    )


def check_simulation_log(path: Path) -> dict[str, bool]:
    """Require the TB's console verdict as well as its structured result."""
    text = path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""
    return {
        "pass_marker_seen": bool(re.search(r"(?m)^BENCH_TB_PASS(?:\s|$)", text)),
        "fail_marker_seen": bool(re.search(r"(?m)^BENCH_TB_FAIL(?:\s|$)", text)),
        "fatal_message_seen": bool(re.search(r"(?m)^\s*(?:Fatal:|FATAL:|\*F,)", text)),
    }


def _touch_metadata(path: Path, metadata: dict[str, Any]) -> None:
    path.write_text(json.dumps(metadata, indent=2, default=str) + "\n", encoding="utf-8")


def _record_tool_version(metadata: dict[str, Any], *logs: Path) -> None:
    version_patterns = (
        re.compile(r"Vivado Simulator v[^\r\n]+"),
        re.compile(r"(?i)(?:Synopsys\s+)?VCS\s+(?:Version|version)[^\r\n]*"),
        re.compile(r"(?i)(?:Cadence\s+)?Xcelium[^\r\n]*version[^\r\n]*"),
        re.compile(r"(?i)xrun[^\r\n]*version[^\r\n]*"),
    )
    for log_path in logs:
        if not log_path.is_file():
            continue
        text = log_path.read_text(encoding="utf-8", errors="replace")
        for pattern in version_patterns:
            match = pattern.search(text)
            if match:
                metadata["simulator_version"] = match.group(0).strip()
                return
    metadata["simulator_version"] = "not reported in captured tool logs"


def run(args: argparse.Namespace) -> int:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    benchmark = args.benchmark
    benchmark_id = int(contract["benchmarks"][benchmark])
    output_root = args.output_dir.resolve()
    run_id = f"{benchmark}_{dt.datetime.now(dt.timezone.utc):%Y%m%dT%H%M%SZ}_{uuid.uuid4().hex[:8]}"
    run_dir = output_root / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    metadata_path = run_dir / "run_metadata.json"
    metadata: dict[str, Any] = {
        "run_id": run_id,
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "benchmark": benchmark,
        "benchmark_id": benchmark_id,
        "simulator": args.simulator,
        "timeout_cycles": args.timeout_cycles,
        "modeled_clock_hz": MODELED_CLOCK_HZ,
        "clock_period_ns": 10,
        "compile_only": args.compile_only,
        "waves": args.waves,
        "wall_timeout_seconds": args.wall_timeout_seconds,
        "run_directory": str(run_dir),
        "commands": [],
        "functional_result_valid": False,
        "published_score_eligible": False,
        "state": "preflight",
    }
    _touch_metadata(metadata_path, metadata)

    try:
        metadata["original_firmware_directory"] = str(args.firmware_dir.resolve())
        copied_firmware_files = []
        for filename in ("imem.hex", "dmem.hex", "program.elf", "program.map", "program.dis", "build.json"):
            source = Path(args.firmware_dir).resolve() / filename
            if source.is_file():
                shutil.copy2(source, run_dir / filename)
                copied_firmware_files.append(filename)
        ported_source = args.firmware_dir.resolve() / "ported"
        if ported_source.is_dir():
            shutil.copytree(ported_source, run_dir / "ported")
            copied_firmware_files.extend(path.relative_to(run_dir).as_posix()
                                         for path in (run_dir / "ported").rglob("*") if path.is_file())
        shutil.copy2(ROOT / "ips/mem_files/riscforge_bootrom.hex", run_dir / "riscforge_bootrom.hex")
        # Preflight the staged snapshot that the simulator will actually load.
        firmware = validate_firmware(run_dir, benchmark, benchmark_id, args.compile_only)
        metadata["firmware"] = firmware
        metadata["copied_run_inputs"] = {
            name: sha256(run_dir / name) for name in (*copied_firmware_files, "riscforge_bootrom.hex")
        }
        metadata["state"] = "filelist_generation"
        _touch_metadata(metadata_path, metadata)
        generated = generate_filelists(ROOT, run_dir, bootrom_path=run_dir / "riscforge_bootrom.hex")
        metadata["source_manifest"] = generated
        metadata["state"] = "compiling"
        _touch_metadata(metadata_path, metadata)

        if args.simulator == "xsim":
            xvlog = _find_tool(args.tool_bin, ["xvlog.bat", "xvlog.exe"])
            xelab = _find_tool(args.tool_bin, ["xelab.bat", "xelab.exe"])
            xsim = _find_tool(args.tool_bin, ["xsim.bat", "xsim.exe"])
            metadata["tools"] = {"xvlog": str(xvlog), "xelab": str(xelab), "xsim": str(xsim)}
            _touch_metadata(metadata_path, metadata)
            compile_rc = _run_command(xvlog, ["--sv", "-f", "soc_benchmark_xsim.f"], run_dir,
                                      run_dir / "xvlog.log", args.wall_timeout_seconds, metadata)
            _touch_metadata(metadata_path, metadata)
            if compile_rc != 0:
                raise RuntimeError(f"XSim compile failed with exit code {compile_rc}")
            elaborate_rc = _run_command(
                xelab, ["-debug", "typical", "-timescale", "1ns/1ps", "-top", "soc_benchmark_tb",
                        "-snapshot", "soc_benchmark_snapshot"],
                run_dir, run_dir / "xelab.log", args.wall_timeout_seconds, metadata,
            )
            _touch_metadata(metadata_path, metadata)
            if elaborate_rc != 0:
                raise RuntimeError(f"XSim elaboration failed with exit code {elaborate_rc}")
            metadata["source_recheck_after_compile"] = verify_source_snapshot(generated)
            _record_tool_version(metadata, run_dir / "xelab.log", run_dir / "xvlog.log")
            if args.compile_only:
                metadata["state"] = "compile_only_complete"
                metadata["compile_only_note"] = "No target execution or benchmark performance was measured."
                _touch_metadata(metadata_path, metadata)
                print(f"Compile/elaboration complete; no simulation run. Artifacts: {run_dir}")
                return 0
            metadata["state"] = "simulating"
            plusargs = [
                "+IMEM_HEX=imem.hex",
                "+DMEM_HEX=dmem.hex",
                "+RESULT_JSON=result.json",
                f"+BENCHMARK_ID={benchmark_id}",
                f"+TIMEOUT_CYCLES={args.timeout_cycles}",
            ]
            if args.waves:
                plusargs.append("+WAVES")
            _write_xsim_options(run_dir / "xsim_options.txt", plusargs)
            sim_args = ["soc_benchmark_snapshot", "-R", "-f", "xsim_options.txt"]
            sim_rc = _run_command(xsim, sim_args, run_dir, run_dir / "simulation.log",
                                  args.wall_timeout_seconds, metadata)
        elif args.simulator == "vcs":
            vcs = _find_tool(args.tool_bin, ["vcs.exe", "vcs"])
            metadata["tools"] = {"vcs": str(vcs)}
            compile_args = ["-sverilog", "-full64", "-timescale=1ns/1ps", "-f",
                            "soc_benchmark_vcs_xcelium.f", "-top", "soc_benchmark_tb",
                            "-o", str(run_dir / "simv"), "-Mdir", str(run_dir / "csrc")]
            compile_rc = _run_command(vcs, compile_args, run_dir, run_dir / "compile.log",
                                      args.wall_timeout_seconds, metadata)
            _touch_metadata(metadata_path, metadata)
            if compile_rc != 0:
                raise RuntimeError(f"VCS compile/elaboration failed with exit code {compile_rc}")
            metadata["source_recheck_after_compile"] = verify_source_snapshot(generated)
            _record_tool_version(metadata, run_dir / "compile.log")
            if args.compile_only:
                metadata["state"] = "compile_only_complete"
                metadata["compile_only_note"] = "No target execution or benchmark performance was measured."
                _touch_metadata(metadata_path, metadata)
                print(f"Compile/elaboration complete; no simulation run. Artifacts: {run_dir}")
                return 0
            sim = run_dir / "simv"
            sim_args = ["+IMEM_HEX=imem.hex",
                        "+DMEM_HEX=dmem.hex",
                        "+RESULT_JSON=result.json", f"+BENCHMARK_ID={benchmark_id}",
                        f"+TIMEOUT_CYCLES={args.timeout_cycles}"]
            if args.waves:
                sim_args.append("+WAVES")
            metadata["state"] = "simulating"
            sim_rc = _run_command(sim, sim_args, run_dir, run_dir / "simulation.log",
                                  args.wall_timeout_seconds, metadata)
        else:
            xrun = _find_tool(args.tool_bin, ["xrun.bat", "xrun.exe", "xrun"])
            metadata["tools"] = {"xrun": str(xrun)}
            sim_args = ["-64bit", "-sv", "-timescale", "1ns/1ps", "-f", "soc_benchmark_vcs_xcelium.f",
                        "-top", "soc_benchmark_tb"]
            if args.compile_only:
                sim_args.append("-elaborate")
            else:
                sim_args.extend([
                    "+IMEM_HEX=imem.hex",
                    "+DMEM_HEX=dmem.hex",
                    "+RESULT_JSON=result.json", f"+BENCHMARK_ID={benchmark_id}",
                    f"+TIMEOUT_CYCLES={args.timeout_cycles}",
                ])
                if args.waves:
                    sim_args.append("+WAVES")
            metadata["state"] = "compiling" if args.compile_only else "simulating"
            sim_rc = _run_command(xrun, sim_args, run_dir, run_dir / "xrun.log",
                                  args.wall_timeout_seconds, metadata)
            metadata["source_recheck_after_xrun"] = verify_source_snapshot(generated)
            if args.compile_only:
                _record_tool_version(metadata, run_dir / "xrun.log")
                metadata["state"] = "compile_only_complete" if sim_rc == 0 else "failed"
                metadata["compile_only_note"] = "No target execution or benchmark performance was measured."
                _touch_metadata(metadata_path, metadata)
                if sim_rc != 0:
                    raise RuntimeError(f"Xcelium compile/elaboration failed with exit code {sim_rc}")
                print(f"Compile/elaboration complete; no simulation run. Artifacts: {run_dir}")
                return 0

        _touch_metadata(metadata_path, metadata)
        _record_tool_version(metadata, run_dir / "simulation.log", run_dir / "compile.log", run_dir / "xrun.log")
        analysis_path = run_dir / "analysis.json"
        if (run_dir / "result.json").is_file():
            analysis = analyze_file(run_dir / "result.json", CONTRACT_PATH, benchmark,
                                    firmware["declared_iteration_counts"][0] if firmware["declared_iteration_counts"] else None,
                                    run_dir / "build.json",
                                    args.qualification_record,
                                    run_dir / "source_hashes.json" if args.qualification_record else None)
        else:
            analysis = {
                "schema_version": 1,
                "valid": False,
                "failure_reasons": ["raw_result_missing_after_simulation"],
                "reason": "no_result_json_written",
                "published_score": None,
                "engineering_score_estimate": None,
            }
            (run_dir / "result.json").write_text(json.dumps({
                "schema_version": 1,
                "reason": "simulator_exit_without_raw_result",
                "testbench_marker": "BENCH_TB_FAIL" if sim_rc != 0 else None,
                "observed_clock_cycles": 0,
                "held_wb_cycles": 0,
                "raw_wb_valid_cycles": 0,
                "words": [],
            }, indent=2) + "\n", encoding="utf-8")
        simulation_log = run_dir / ("xrun.log" if args.simulator == "xcelium" else "simulation.log")
        log_verdict = check_simulation_log(simulation_log)
        metadata["simulation_log_verdict"] = log_verdict
        log_errors = []
        if not log_verdict["pass_marker_seen"]:
            log_errors.append("simulation_log_missing_pass_marker")
        if log_verdict["fail_marker_seen"] or log_verdict["fatal_message_seen"]:
            log_errors.append("simulation_log_contains_failure")
        if log_errors:
            analysis["valid"] = False
            analysis.setdefault("failure_reasons", []).extend(log_errors)
            analysis["engineering_score_estimate"] = None
        analysis_path.write_text(json.dumps(analysis, indent=2) + "\n", encoding="utf-8")
        metadata["analysis_valid"] = analysis.get("valid", False)
        metadata["analysis_failure_reasons"] = analysis.get("failure_reasons", [])
        metadata["simulator_exit_code"] = sim_rc
        metadata["state"] = "passed" if sim_rc == 0 and analysis.get("valid") else "failed"
        metadata["functional_result_valid"] = bool(sim_rc == 0 and analysis.get("valid"))
        metadata["published_score_eligible"] = False
        metadata["engineering_estimates_only"] = True
        _touch_metadata(metadata_path, metadata)
        print(f"{metadata['state'].upper()}: benchmark={benchmark}, run={run_id}")
        print(f"Artifacts: {run_dir}")
        if metadata["state"] != "passed":
            print("Failure reasons: " + ", ".join(metadata["analysis_failure_reasons"] or [f"simulator_exit_{sim_rc}"]))
            return 1
        return 0
    except TimeoutError as exc:
        metadata["state"] = "wall_timeout"
        metadata["failure_reason"] = str(exc)
        _touch_metadata(metadata_path, metadata)
        raw_path = run_dir / "result.json"
        if not raw_path.exists():
            raw_path.write_text(json.dumps({
                "schema_version": 1,
                "reason": "simulator_wall_timeout",
                "testbench_marker": "BENCH_TB_FAIL",
                "observed_clock_cycles": 0,
                "held_wb_cycles": 0,
                "raw_wb_valid_cycles": 0,
                "words": [],
            }, indent=2) + "\n", encoding="utf-8")
        print(f"WALL TIMEOUT: {exc}", file=sys.stderr)
        print(f"Artifacts: {run_dir}", file=sys.stderr)
        return 1
    except (PreflightError, FilelistError, OSError, ValueError, json.JSONDecodeError, RuntimeError) as exc:
        metadata["state"] = "failed"
        metadata["failure_reason"] = str(exc)
        _touch_metadata(metadata_path, metadata)
        print(f"run_benchmark: error: {exc}", file=sys.stderr)
        print(f"Artifacts: {run_dir}", file=sys.stderr)
        return 2


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark", required=True, choices=("smoke", "counter_probe", "coremark", "dhrystone"))
    parser.add_argument("--firmware-dir", type=Path, required=True,
                        help="directory containing program.elf, imem.hex, dmem.hex, and build.json")
    parser.add_argument("--simulator", choices=("xsim", "vcs", "xcelium"), required=True)
    parser.add_argument("--timeout-cycles", type=int, default=1_000_000)
    parser.add_argument("--wall-timeout-seconds", type=float, default=3600)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "ips/benchmarks/build/runs")
    parser.add_argument("--tool-bin", type=Path, help="simulator bin directory or executable")
    parser.add_argument("--waves", action="store_true", help="write optional VCD waveform output")
    parser.add_argument("--compile-only", action="store_true", help="compile and elaborate; never run target firmware")
    parser.add_argument("--qualification-record", type=Path,
                        help="explicit instruction-counter qualification record; binds the claim to pinned source hashes")
    args = parser.parse_args(argv)
    if args.timeout_cycles <= 0:
        parser.error("--timeout-cycles must be positive")
    if args.wall_timeout_seconds <= 0:
        parser.error("--wall-timeout-seconds must be positive")
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
