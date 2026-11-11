#!/usr/bin/env python3
"""Build one bare-metal RISCFORGE benchmark image from pinned sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shlex
import shutil
import struct
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIRMWARE = ROOT / "firmware"
PORTS = ROOT / "ports"
VENDOR = ROOT / "vendor"
CONTRACT_PATH = ROOT / "contract.json"
LOCK_PATH = VENDOR / "sources.lock.json"
BENCHMARKS = {
    "smoke": {"id": 1, "default_iterations": 1, "source": FIRMWARE / "smoke.c"},
    "counter_probe": {
        "id": 2,
        "default_iterations": 1,
        "source": FIRMWARE / "counter_probe.c",
    },
    "coremark": {"id": 3, "default_iterations": 1},
    "dhrystone": {"id": 4, "default_iterations": 10},
}
MEMORY = {
    "imem": {"origin": 0x00010000, "size": 32 * 1024},
    "dmem": {"origin": 0x00020000, "size": 32 * 1024},
    "result_reserved_bytes": 256,
    "stack_top": 0x00028000,
    "minimum_stack_margin_bytes": 4096,
}
RESULT_FIELDS = [
    "magic",
    "version",
    "status",
    "benchmark_id",
    "iterations",
    "validation_errors",
    "cycle_start_lo",
    "cycle_start_hi",
    "cycle_end_lo",
    "cycle_end_hi",
    "instret_start_lo",
    "instret_start_hi",
    "instret_end_lo",
    "instret_end_hi",
    "crc_list",
    "crc_matrix",
    "crc_state",
    "crc_final",
    "error_code",
    "trap_cause",
    "trap_epc",
    "trap_tval",
    "counter_checks",
    "console_word",
    "probe_expected",
    "probe_observed",
    "timing_phase",
    "result_flags",
    "clock_hz",
]


class BuildFailure(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise BuildFailure(f"expected one {label} patch anchor, found {count}")
    return text.replace(old, new, 1)


class BuildLog:
    def __init__(self, output_dir: Path):
        self.path = output_dir / "build.log"
        self.stream = self.path.open("w", encoding="utf-8", newline="\n")

    def write(self, text: str) -> None:
        self.stream.write(text)
        if text and not text.endswith("\n"):
            self.stream.write("\n")
        self.stream.flush()

    def run(self, command: list[str], cwd: Path, output_file: Path | None = None) -> str:
        self.write("$ " + shlex.join(command))
        try:
            process = subprocess.run(
                command,
                cwd=cwd,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
        except OSError as exc:
            self.write(f"command could not start: {exc}")
            raise BuildFailure(f"command could not start: {command[0]}: {exc}") from exc
        self.write(process.stdout)
        if process.returncode != 0:
            raise BuildFailure(
                f"command exited with status {process.returncode}: {command[0]}"
            )
        if output_file is not None:
            output_file.write_text(process.stdout, encoding="utf-8")
        return process.stdout

    def close(self) -> None:
        self.stream.close()


def tool_prefix(cc_arg: str) -> tuple[str, str]:
    if cc_arg.endswith("gcc"):
        gcc = cc_arg
        prefix = cc_arg[:-3]
    else:
        prefix = cc_arg
        gcc = prefix + "gcc"
    if shutil.which(gcc) is None and not Path(gcc).is_file():
        raise BuildFailure(f"compiler not found: {gcc}")
    return gcc, prefix


def patch_coremark_main(source: Path, destination: Path) -> None:
    text = source.read_text(encoding="utf-8")
    text = replace_once(
        text,
        '#include "coremark.h"\n',
        '#include "coremark.h"\n#include "benchmark.h"\n',
        "CoreMark result-hook include",
    )
    text = replace_once(
        text,
        "    portable_fini(&(results[0].port));\n",
        "    portable_fini(&(results[0].port));\n"
        "    benchmark_coremark_report((int32_t)total_errors,\n"
        "                              known_id >= 0 ? (int32_t)results[0].err : -1,\n"
        "                              (uint32_t)results[0].crclist,\n"
        "                              (uint32_t)results[0].crcmatrix,\n"
        "                              (uint32_t)results[0].crcstate,\n"
        "                              (uint32_t)results[0].crc);\n",
        "CoreMark total_errors/CRC hook",
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text, encoding="utf-8", newline="\n")


def patch_dhrystone_sources(
    upstream_header: Path,
    upstream_main: Path,
    destination_dir: Path,
    clock_hz: int,
    iterations: int,
) -> tuple[Path, Path]:
    header = upstream_header.read_text(encoding="utf-8")
    header = replace_once(
        header,
        "#define _DHRYSTONE_H\n",
        "#define _DHRYSTONE_H\n\n#include \"benchmark.h\"\n",
        "Dhrystone port declarations",
    )
    header = replace_once(header, "#define HZ 1000000", f"#define HZ {clock_hz}", "Dhrystone HZ")
    header = replace_once(
        header,
        '#define Too_Small_Time 1',
        '#define Too_Small_Time 0',
        "Dhrystone fixed-iteration timing threshold",
    )
    header = replace_once(
        header,
        '#define CLOCK_TYPE "rdcycle()"',
        '#define CLOCK_TYPE "RISCFORGE 64-bit mcycle snapshot"',
        "Dhrystone clock label",
    )
    header = replace_once(
        header,
        "#define Start_Timer() Begin_Time = read_csr(mcycle)\n"
        "#define Stop_Timer() End_Time = read_csr(mcycle)",
        "#define Start_Timer() do { Begin_Time = 0; benchmark_dhrystone_timer_start(); } while (0)\n"
        "#define Stop_Timer() do { End_Time = 1; benchmark_dhrystone_timer_stop(); } while (0)",
        "Dhrystone high-low-high timer port",
    )
    header, run_count = re.subn(
        r"#define NUMBER_OF_RUNS\s+500\s*/\* Default number of runs \*/",
        f"#define NUMBER_OF_RUNS\t\t{iterations} /* Default number of runs */",
        header,
    )
    if run_count != 1:
        raise BuildFailure(f"expected one Dhrystone run-count definition, found {run_count}")

    main = upstream_main.read_text(encoding="utf-8")
    main = replace_once(
        main,
        '#include "dhrystone.h"\n',
        '#include "dhrystone.h"\n#include "benchmark.h"\n',
        "Dhrystone result-hook include",
    )
    main = replace_once(
        main,
        "  /* Arguments */\n  Number_Of_Runs = NUMBER_OF_RUNS;",
        "  benchmark_init(BENCHMARK_DHRYSTONE, BENCHMARK_ITERATIONS,\n"
        "                 BENCHMARK_CLOCK_HZ);\n\n"
        "  /* Arguments */\n  Number_Of_Runs = NUMBER_OF_RUNS;",
        "Dhrystone result-block initialization",
    )
    metric_start = main.find("  Microseconds =")
    if metric_start < 0:
        raise BuildFailure("Dhrystone metrics patch anchor was not found")
    return_pos = main.find("  return 0;", metric_start)
    if return_pos < 0:
        raise BuildFailure("Dhrystone final return patch anchor was not found")
    main = (
        main[:metric_start]
        + "  benchmark_dhrystone_validate(Int_1_Loc, Int_2_Loc, Int_3_Loc,\n"
        + "                                Enum_Loc, Str_1_Loc, Str_2_Loc);\n"
        + main[return_pos:]
    )
    destination_dir.mkdir(parents=True, exist_ok=True)
    header_path = destination_dir / "dhrystone.h"
    main_path = destination_dir / "dhrystone_main.c"
    header_path.write_text(header, encoding="utf-8", newline="\n")
    main_path.write_text(main, encoding="utf-8", newline="\n")
    return header_path, main_path


def parse_elf_sections(path: Path) -> tuple[dict, list[dict]]:
    data = path.read_bytes()
    if len(data) < 52 or data[:4] != b"\x7fELF":
        raise BuildFailure(f"not a valid ELF file: {path}")
    if data[4] != 1 or data[5] != 1:
        raise BuildFailure("expected a 32-bit little-endian ELF")
    header = struct.unpack_from("<HHIIIIIHHHHHH", data, 16)
    (
        elf_type,
        machine,
        _version,
        entry,
        _program_offset,
        section_offset,
        flags,
        _header_size,
        _program_entry_size,
        _program_count,
        section_entry_size,
        section_count,
        string_index,
    ) = header
    if machine != 243:
        raise BuildFailure(f"expected RISC-V ELF machine 243, got {machine}")
    raw_sections = []
    for index in range(section_count):
        offset = section_offset + index * section_entry_size
        raw_sections.append(struct.unpack_from("<IIIIIIIIII", data, offset))
    string_header = raw_sections[string_index]
    strings = data[string_header[4] : string_header[4] + string_header[5]]

    def c_string(offset: int) -> str:
        end = strings.find(b"\0", offset)
        if end < 0:
            end = len(strings)
        return strings[offset:end].decode("ascii", errors="replace")

    sections = []
    for raw in raw_sections:
        name_offset, section_type, section_flags, address, offset, size, *_ = raw
        sections.append(
            {
                "name": c_string(name_offset),
                "type": section_type,
                "flags": section_flags,
                "address": address,
                "offset": offset,
                "size": size,
            }
        )
    return {
        "type": elf_type,
        "entry": entry,
        "flags": flags,
        "section_count": section_count,
    }, sections


def write_hex_images(elf_path: Path, imem_path: Path, dmem_path: Path) -> dict:
    data = elf_path.read_bytes()
    elf, sections = parse_elf_sections(elf_path)
    images = {
        "imem": bytearray(MEMORY["imem"]["size"]),
        "dmem": bytearray(MEMORY["dmem"]["size"]),
    }
    file_bytes = {"imem": 0, "dmem": 0}
    static_bytes = {"imem": 0, "dmem": 0, "noload": 0}
    alloc_sections = []
    for section in sections:
        if not (section["flags"] & 0x2) or section["size"] == 0:
            continue
        address = section["address"]
        size = section["size"]
        if MEMORY["imem"]["origin"] <= address < MEMORY["imem"]["origin"] + MEMORY["imem"]["size"]:
            region = "imem"
        elif MEMORY["dmem"]["origin"] <= address < MEMORY["dmem"]["origin"] + MEMORY["dmem"]["size"]:
            region = "dmem"
        else:
            raise BuildFailure(
                f"allocated section {section['name']} at 0x{address:08x} is outside SRAM"
            )
        end = address + size
        region_end = MEMORY[region]["origin"] + MEMORY[region]["size"]
        if end > region_end:
            raise BuildFailure(f"section {section['name']} exceeds {region}")
        alloc_sections.append(
            {
                "name": section["name"],
                "region": region,
                "address": f"0x{address:08x}",
                "size_bytes": size,
                "loadable": section["type"] != 8,
            }
        )
        static_bytes[region] += size
        if section["type"] == 8:  # SHT_NOBITS (.bss and reserved block).
            static_bytes["noload"] += size
            continue
        start = section["offset"]
        payload = data[start : start + size]
        if len(payload) != size:
            raise BuildFailure(f"truncated ELF section {section['name']}")
        image_offset = address - MEMORY[region]["origin"]
        images[region][image_offset : image_offset + size] = payload
        file_bytes[region] += size

    for name, path in (("imem", imem_path), ("dmem", dmem_path)):
        payload = images[name]
        if len(payload) % 4:
            raise BuildFailure(f"{name} image is not word aligned")
        words = struct.unpack("<" + "I" * (len(payload) // 4), payload)
        path.write_text("".join(f"{word:08x}\n" for word in words), encoding="ascii")
    return {
        "elf_entry": f"0x{elf['entry']:08x}",
        "elf_flags": f"0x{elf['flags']:08x}",
        "sections": alloc_sections,
        "initialized_bytes": file_bytes,
        "static_allocated_bytes": static_bytes,
    }


def symbols_from_nm(text: str) -> dict[str, int]:
    symbols = {}
    for line in text.splitlines():
        fields = line.split()
        if len(fields) >= 3:
            try:
                symbols[fields[-1]] = int(fields[0], 16)
            except ValueError:
                continue
    return symbols


def compiler_flags(arch: str, common: list[str]) -> list[str]:
    return [
        f"-march={arch}",
        "-mabi=ilp32",
        "-O2",
        "-ffreestanding",
        "-fno-builtin",
        "-fno-common",
        "-fno-pic",
        "-msmall-data-limit=0",
        "-ffunction-sections",
        "-fdata-sections",
        "-nostdlib",
        *common,
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark", required=True, choices=sorted(BENCHMARKS))
    parser.add_argument("--iterations", type=int)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--clock-hz", type=int, default=100000000)
    parser.add_argument(
        "--arch", choices=("rv32im_zicsr", "rv32i_zicsr"), default="rv32im_zicsr"
    )
    parser.add_argument("--cc", default="riscv64-unknown-elf-")
    args = parser.parse_args()

    benchmark = args.benchmark
    iterations = (
        BENCHMARKS[benchmark]["default_iterations"]
        if args.iterations is None
        else args.iterations
    )
    if not 1 <= iterations <= 0x7FFFFFFF:
        parser.error("--iterations must be in the range 1..2147483647")
    if benchmark in ("smoke", "counter_probe") and iterations != 1:
        parser.error("smoke and counter_probe are fixed one-iteration diagnostics")
    if not 1 <= args.clock_hz <= 0xFFFFFFFF:
        parser.error("--clock-hz must be in the range 1..4294967295")

    output_dir = (args.output_dir or (ROOT / "build" / "firmware" / benchmark)).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    log = BuildLog(output_dir)
    manifest: dict = {
        "benchmark": benchmark,
        "benchmark_id": BENCHMARKS[benchmark]["id"],
        "iterations": iterations,
        "clock_hz": args.clock_hz,
        "arch": args.arch,
        "build_status": "in_progress",
        "verification_status": "not_run",
        "output_dir": str(output_dir),
    }
    # Invalidate an earlier successful manifest before touching reused outputs.
    # An interrupted/failed rebuild must not leave an apparently completed build.
    (output_dir / "build.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    try:
        gcc, prefix = tool_prefix(args.cc)
        objdump = prefix + "objdump"
        nm = prefix + "nm"
        for program in (objdump, nm):
            if shutil.which(program) is None and not Path(program).is_file():
                raise BuildFailure(f"required binutils program not found: {program}")

        log.write(f"benchmark={benchmark} id={manifest['benchmark_id']} iterations={iterations}")
        log.write(f"clock_hz={args.clock_hz} arch={args.arch} output_dir={output_dir}")
        compiler_version = log.run([gcc, "-dumpfullversion", "-dumpversion"], ROOT).strip()
        manifest["compiler"] = gcc
        manifest["compiler_version"] = compiler_version

        log.run([sys.executable, str(ROOT / "tools" / "fetch_sources.py"), "--check"], ROOT)
        contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
        lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
        if (
            contract.get("address") != "0x00020000"
            or contract.get("reserved_bytes") != 256
            or contract.get("magic") != "0x42454e43"
            or contract.get("version") != 1
            or contract.get("word_size_bytes") != 4
            or contract.get("byte_order") != "little"
            or contract.get("words") != RESULT_FIELDS
        ):
            raise BuildFailure("benchmark contract differs from the firmware's fixed result layout")
        if contract.get("status") != {
            "empty": 0,
            "running": 1,
            "pass": 2,
            "fail": 3,
        } or contract.get("benchmarks") != {
            "smoke": 1,
            "counter_probe": 2,
            "coremark": 3,
            "dhrystone": 4,
        }:
            raise BuildFailure("benchmark contract status or benchmark IDs changed")
        manifest["contract"] = {
            "name": contract["name"],
            "version": contract["version"],
            "address": contract["address"],
            "reserved_bytes": contract["reserved_bytes"],
            "fields": contract["words"],
            "sha256": sha256_file(CONTRACT_PATH),
        }
        manifest["source_pins"] = {
            key: {
                "repository": value["repository"],
                "revision": value["revision"],
                "version": value["version"],
                "license_file": value["license_file"],
                "sha256": value["sha256"],
            }
            for key, value in lock.items()
        }

        ported = output_dir / "ported"
        generated_sources: dict[str, Path] = {}
        if benchmark == "coremark":
            generated_sources["coremark_main_ported"] = output_dir / "ported" / "core_main.c"
            patch_coremark_main(
                VENDOR / "upstream" / "coremark" / "core_main.c",
                generated_sources["coremark_main_ported"],
            )
            manifest["port_adaptations"] = [
                "Upstream CoreMark algorithm files are compiled unchanged.",
                "A build-local core_main.c copy reports the actual upstream total_errors and CRC fields before termination.",
            ]
        elif benchmark == "dhrystone":
            header_path, main_path = patch_dhrystone_sources(
                VENDOR / "upstream" / "dhrystone" / "benchmarks" / "dhrystone" / "dhrystone.h",
                VENDOR / "upstream" / "dhrystone" / "benchmarks" / "dhrystone" / "dhrystone_main.c",
                ported / "dhrystone",
                args.clock_hz,
                iterations,
            )
            generated_sources["dhrystone_header_ported"] = header_path
            generated_sources["dhrystone_main_ported"] = main_path
            manifest["port_adaptations"] = [
                "The upstream dhrystone.c computational routines are compiled unchanged and as a separate translation unit.",
                "A build-local header copy binds Start_Timer/Stop_Timer to the 64-bit high-low-high mailbox snapshots and disables the legacy short-run retry so the requested iteration count stays exact.",
                "A build-local main copy initializes the result block, checks all final arrays/scalars/strings/records, and omits the upstream target score calculation/output.",
                "The upstream alloca.h and util.h dependencies are supplied by small freestanding port headers; the empty upstream debug_printf stub is renamed for the algorithm translation unit and a port implementation writes readable output outside the measured loop.",
                "Struct assignment and strcpy/strcmp behavior remain enabled.",
            ]
        else:
            manifest["port_adaptations"] = ["The firmware smoke or counter diagnostic is compiled from local source."]

        common = compiler_flags(
            args.arch,
            [
                f"-DBENCHMARK_ID={BENCHMARKS[benchmark]['id']}u",
                f"-DBENCHMARK_ITERATIONS={iterations}u",
                f"-DBENCHMARK_CLOCK_HZ={args.clock_hz}u",
            ],
        )
        include_dirs = ["-I", str(FIRMWARE)]
        if benchmark == "coremark":
            include_dirs += [
                "-I",
                str(PORTS / "coremark"),
                "-I",
                str(VENDOR / "upstream" / "coremark"),
            ]
        if benchmark == "dhrystone":
            include_dirs += [
                "-I",
                str(PORTS / "dhrystone"),
                "-I",
                str(VENDOR / "upstream" / "dhrystone" / "benchmarks" / "dhrystone"),
            ]

        object_dir = output_dir / "obj"
        object_dir.mkdir(parents=True, exist_ok=True)
        objects: list[Path] = []
        compiled_sources: dict[str, Path] = {}

        def compile_source(
            name: str,
            source: Path,
            extra_flags: list[str] | None = None,
            extra_includes: list[str] | None = None,
        ) -> Path:
            obj = object_dir / f"{name}.o"
            command = [
                gcc,
                *common,
                "-c",
                str(source),
                *include_dirs,
                *(extra_includes or []),
                *(extra_flags or []),
                "-o",
                str(obj),
            ]
            log.run(command, ROOT)
            objects.append(obj)
            compiled_sources[name] = source
            return obj

        compile_source("start", FIRMWARE / "start.S")
        compile_source("runtime", FIRMWARE / "runtime.c")

        if benchmark in ("smoke", "counter_probe"):
            compile_source(benchmark, BENCHMARKS[benchmark]["source"])
        elif benchmark == "coremark":
            core_dir = VENDOR / "upstream" / "coremark"
            port_dir = PORTS / "coremark"
            for source in (
                core_dir / "core_list_join.c",
                generated_sources["coremark_main_ported"],
                core_dir / "core_matrix.c",
                core_dir / "core_state.c",
                core_dir / "core_util.c",
                port_dir / "core_portme.c",
            ):
                coremark_flags = [
                    "-std=gnu99",
                    "-DTOTAL_DATA_SIZE=2000",
                    "-DVALIDATION_RUN=1",
                    f'-DCOMPILER_VERSION="GCC {compiler_version}"',
                    f'-DCOMPILER_FLAGS="-march={args.arch} -mabi=ilp32 -O2 -ffreestanding -nostdlib -DVALIDATION_RUN=1 -DTOTAL_DATA_SIZE=2000"',
                ]
                if source.name == "core_portme.c":
                    coremark_flags.append("-DBENCHMARK_COREMARK_PORT=1")
                compile_source(source.stem, source, coremark_flags)
        else:
            dhr_dir = VENDOR / "upstream" / "dhrystone" / "benchmarks" / "dhrystone"
            port_dir = PORTS / "dhrystone"
            dhr_common = [
                "-std=gnu89",
                "-fno-inline",
                "-fno-ipa-icf",
                "-fno-builtin-strcpy",
                "-fno-builtin-strcmp",
                "-DBUILD_DHRYSTONE=1",
                "-include",
                str(port_dir / "string.h"),
            ]
            compile_source(
                "dhrystone",
                dhr_dir / "dhrystone.c",
                dhr_common + ["-Ddebug_printf=upstream_debug_printf"],
            )
            compile_source(
                "dhrystone_main_ported",
                generated_sources["dhrystone_main_ported"],
                dhr_common,
            )
            compile_source("dhrystone_port", port_dir / "dhrystone_port.c", dhr_common)

        linker_script = FIRMWARE / "linker.ld"
        manifest["flags"] = {
            "common": common,
            "benchmark": (
                ["-std=gnu99", "-DTOTAL_DATA_SIZE=2000", "-DVALIDATION_RUN=1"]
                if benchmark == "coremark"
                else (
                    [
                        "-std=gnu89",
                        "-fno-inline",
                        "-fno-ipa-icf",
                        "-fno-builtin-strcpy",
                "-fno-builtin-strcmp",
                "-DBUILD_DHRYSTONE=1",
                "-include",
                str(PORTS / "dhrystone" / "string.h"),
                    ]
                    if benchmark == "dhrystone"
                    else []
                )
            ),
            "link": [
                "-nostdlib",
                f"-T {linker_script}",
                "-Wl,--gc-sections",
                "-lgcc",
            ],
        }
        if benchmark == "dhrystone":
            manifest["flags"]["per_object"] = {
                "dhrystone.c": ["-Ddebug_printf=upstream_debug_printf"]
            }

        elf_path = output_dir / "program.elf"
        map_path = output_dir / "program.map"
        link_command = [
            gcc,
            f"-march={args.arch}",
            "-mabi=ilp32",
            "-O2",
            "-nostdlib",
            "-fno-pic",
            f"-Wl,-T,{linker_script}",
            f"-Wl,-Map,{map_path}",
            "-Wl,--gc-sections",
            *[str(obj) for obj in objects],
            "-lgcc",
            "-o",
            str(elf_path),
        ]
        log.run(link_command, ROOT)

        disassembly_path = output_dir / "program.dis"
        disassembly = log.run(
            [objdump, "-d", "-M", "no-aliases", str(elf_path)], ROOT
        )
        disassembly_path.write_text(disassembly, encoding="utf-8")
        nm_output = log.run([nm, "-n", str(elf_path)], ROOT)
        symbols = symbols_from_nm(nm_output)
        required_symbols = ("_start", "__text_end", "__static_end", "__stack_top")
        missing = [symbol for symbol in required_symbols if symbol not in symbols]
        if missing:
            raise BuildFailure(f"missing linker symbols: {', '.join(missing)}")

        image_info = write_hex_images(
            elf_path, output_dir / "imem.hex", output_dir / "dmem.hex"
        )
        static_end = symbols["__static_end"]
        stack_top = symbols["__stack_top"]
        text_end = symbols["__text_end"]
        static_bytes = static_end - MEMORY["dmem"]["origin"]
        stack_margin = stack_top - static_end
        imem_used = text_end - MEMORY["imem"]["origin"]
        if imem_used < 0 or imem_used > MEMORY["imem"]["size"]:
            raise BuildFailure(f"ISRAM fit check failed: {imem_used} bytes")
        if static_bytes < 0 or static_bytes > MEMORY["dmem"]["size"]:
            raise BuildFailure(f"DSRAM static fit check failed: {static_bytes} bytes")
        if stack_margin < MEMORY["minimum_stack_margin_bytes"]:
            raise BuildFailure(f"stack margin below 4 KiB: {stack_margin} bytes")
        if image_info["elf_flags"] != "0x00000000":
            raise BuildFailure(
                f"unexpected RISC-V ELF flags (compressed or float ABI may be enabled): {image_info['elf_flags']}"
            )
        if symbols["_start"] < MEMORY["imem"]["origin"] or symbols["_start"] >= text_end:
            raise BuildFailure("_start is not located in the linked ISRAM text range")

        manifest["memory_fit"] = {
            "imem_origin": f"0x{MEMORY['imem']['origin']:08x}",
            "imem_capacity_bytes": MEMORY["imem"]["size"],
            "imem_text_bytes": imem_used,
            "imem_free_bytes": MEMORY["imem"]["size"] - imem_used,
            "dmem_origin": f"0x{MEMORY['dmem']['origin']:08x}",
            "dmem_capacity_bytes": MEMORY["dmem"]["size"],
            "result_reserved_bytes": MEMORY["result_reserved_bytes"],
            "dmem_static_end": f"0x{static_end:08x}",
            "dmem_static_bytes_including_result_reservation": static_bytes,
            "stack_top": f"0x{stack_top:08x}",
            "stack_margin_bytes_after_static_data": stack_margin,
            "required_stack_margin_bytes": MEMORY["minimum_stack_margin_bytes"],
            "dynamic_stack_proven": False,
            "static_sections": image_info["sections"],
            "initialized_bytes_by_region": image_info["initialized_bytes"],
            "static_allocated_bytes_by_region": image_info["static_allocated_bytes"],
        }
        manifest["images"] = {
            "elf": str(elf_path),
            "map": str(map_path),
            "disassembly": str(disassembly_path),
            "imem_hex": str(output_dir / "imem.hex"),
            "dmem_hex": str(output_dir / "dmem.hex"),
            "log": str(log.path),
        }
        source_hashes = {
            "firmware": {},
            "ports": {},
            "upstream_files_compiled": {},
            "ported_build_copies": {},
            "linker_script": sha256_file(linker_script),
            "source_lock": sha256_file(LOCK_PATH),
            "build_tools": {
                str((ROOT / "tools" / "build_firmware.py").relative_to(ROOT)):
                    sha256_file(ROOT / "tools" / "build_firmware.py"),
                str((ROOT / "tools" / "fetch_sources.py").relative_to(ROOT)):
                    sha256_file(ROOT / "tools" / "fetch_sources.py"),
            },
        }
        for path in (FIRMWARE / "benchmark.h", FIRMWARE / "start.S", FIRMWARE / "runtime.c"):
            source_hashes["firmware"][path.relative_to(ROOT).as_posix()] = sha256_file(path)
        for name, path in compiled_sources.items():
            if str(path).startswith(str(VENDOR)):
                source_hashes["upstream_files_compiled"][path.relative_to(ROOT).as_posix()] = sha256_file(path)
            elif str(path).startswith(str(PORTS)):
                source_hashes["ports"][path.relative_to(ROOT).as_posix()] = sha256_file(path)
            elif str(path).startswith(str(FIRMWARE)):
                source_hashes["firmware"][path.relative_to(ROOT).as_posix()] = sha256_file(path)
            else:
                source_hashes["ported_build_copies"][path.name] = sha256_file(path)
        for name, path in generated_sources.items():
            source_hashes["ported_build_copies"][name] = sha256_file(path)
        if benchmark == "coremark":
            for name in ("core_portme.h",):
                path = PORTS / "coremark" / name
                source_hashes["ports"][path.relative_to(ROOT).as_posix()] = sha256_file(path)
        if benchmark == "dhrystone":
            for name in ("util.h", "alloca.h", "stdio.h", "string.h"):
                path = PORTS / "dhrystone" / name
                source_hashes["ports"][path.relative_to(ROOT).as_posix()] = sha256_file(path)
        manifest["source_hashes"] = source_hashes
        output_files = [output_dir / name for name in
                        ("program.elf", "program.map", "program.dis", "imem.hex", "dmem.hex")]
        ported_dir = output_dir / "ported"
        if ported_dir.is_dir():
            output_files.extend(path for path in ported_dir.rglob("*")
                                if path.is_file() and path.suffix in (".c", ".h"))
        manifest["output_hashes"] = {path.relative_to(output_dir).as_posix(): sha256_file(path)
                                     for path in output_files}
        manifest["build_status"] = "complete"
        manifest["verification_status"] = "not_run"
        manifest_path = output_dir / "build.json"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        log.write(f"Build complete: {elf_path}")
        log.write(f"IMEM used {imem_used}/{MEMORY['imem']['size']} bytes")
        log.write(
            f"DSRAM static {static_bytes}/{MEMORY['dmem']['size']} bytes; "
            f"stack margin {stack_margin} bytes (dynamic stack not proven)"
        )
        log.write(f"Metadata: {manifest_path}")
        print(f"benchmark={benchmark}")
        print(f"elf={elf_path}")
        print(f"map={map_path}")
        print(f"disassembly={disassembly_path}")
        print(f"imem_hex={output_dir / 'imem.hex'}")
        print(f"dmem_hex={output_dir / 'dmem.hex'}")
        print(f"build_json={manifest_path}")
        print(f"imem_used_bytes={imem_used}")
        print(f"dmem_static_bytes={static_bytes}")
        print(f"stack_margin_bytes={stack_margin}")
        return 0
    except (BuildFailure, OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        manifest["build_status"] = "failed"
        manifest["failure"] = str(exc)
        try:
            (output_dir / "build.json").write_text(
                json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
            )
        except OSError:
            pass
        log.write(f"BUILD FAILED: {exc}")
        print(f"build failed: {exc}", file=sys.stderr)
        print(f"log={log.path}", file=sys.stderr)
        return 2
    finally:
        log.close()


if __name__ == "__main__":
    raise SystemExit(main())
