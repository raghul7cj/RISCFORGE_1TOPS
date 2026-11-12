#!/usr/bin/env python3
"""Validate raw benchmark mailbox captures and report explicitly unqualified metrics."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_CONTRACT = ROOT / "ips/benchmarks/contract.json"
MODELED_CLOCK_HZ = 100_000_000
COUNTER_MODULUS = 1 << 64


def _word(value: Any, index: int) -> int:
    if isinstance(value, bool):
        raise ValueError(f"word {index} is boolean, not uint32")
    if isinstance(value, int):
        result = value
    elif isinstance(value, str):
        text = value.strip().lower()
        result = int(text, 16) if text.startswith("0x") else int(text, 10)
    else:
        raise ValueError(f"word {index} has unsupported type {type(value).__name__}")
    if result < 0 or result > 0xFFFF_FFFF:
        raise ValueError(f"word {index} is outside uint32 range")
    return result


def _load_contract(contract: dict[str, Any] | str | Path) -> dict[str, Any]:
    if isinstance(contract, dict):
        return contract
    return json.loads(Path(contract).read_text(encoding="utf-8"))


def _metadata_values(node: Any, aliases: set[str], found: list[Any]) -> None:
    if isinstance(node, dict):
        for key, value in node.items():
            normalized = str(key).replace("-", "_").lower()
            if normalized in aliases:
                found.append(value)
            _metadata_values(value, aliases, found)
    elif isinstance(node, list):
        for value in node:
            _metadata_values(value, aliases, found)


QUALIFICATION_VALUES = ("qualified", "unqualified")
QUALIFICATION_SCORE_VALUES = ("engineering_estimate_only", "qualified")


def validate_qualification_record(record: Any) -> list[str]:
    """Validate an explicit qualification record.

    The record is the only way a run may claim a qualified instruction
    counter. It must name the issue and fix it relies on and must pin the
    source hashes that carry the fix, so a claim cannot be reused against a
    different RTL snapshot.
    """
    if not isinstance(record, dict):
        return ["qualification_record_is_not_an_object"]
    errors: list[str] = []
    if record.get("schema_version") != 1:
        errors.append("qualification_record_schema_version_unsupported")
    for key in ("minstret", "cpi"):
        if record.get(key) not in QUALIFICATION_VALUES:
            errors.append(f"qualification_record_{key}_invalid")
    if record.get("normalized_score") not in QUALIFICATION_SCORE_VALUES:
        errors.append("qualification_record_normalized_score_invalid")
    if not isinstance(record.get("published_compliance"), bool):
        errors.append("qualification_record_published_compliance_invalid")
    basis = record.get("basis")
    if not isinstance(basis, str) or not basis.strip():
        errors.append("qualification_record_basis_missing")
    required = record.get("required_source_sha256")
    if not isinstance(required, dict) or not required:
        errors.append("qualification_record_required_source_sha256_missing")
    else:
        for path, digest in required.items():
            if not isinstance(path, str) or not path.strip():
                errors.append("qualification_record_source_path_invalid")
            if not isinstance(digest, str) or len(digest) != 64:
                errors.append(f"qualification_record_source_hash_invalid:{path}")
    return errors


def load_qualification_record(path: str | Path) -> dict[str, Any]:
    record = json.loads(Path(path).read_text(encoding="utf-8"))
    errors = validate_qualification_record(record)
    if errors:
        raise ValueError("; ".join(errors))
    return record


def apply_qualification_record(
    result: dict[str, Any],
    errors: list[str],
    record: dict[str, Any],
    source_hashes: dict[str, Any] | None,
) -> None:
    record_errors = validate_qualification_record(record)
    if record_errors:
        errors.extend(record_errors)
        return
    required = record["required_source_sha256"]
    available = source_hashes.get("sha256") if isinstance(source_hashes, dict) else None
    if not isinstance(available, dict) or not available:
        errors.append("qualification_source_hashes_not_provided")
        return
    verified: dict[str, str] = {}
    verification_errors: list[str] = []
    for path, digest in required.items():
        actual = available.get(path)
        if actual is None:
            verification_errors.append(f"qualification_source_missing:{path}")
        elif str(actual).lower() != str(digest).lower():
            verification_errors.append(f"qualification_source_hash_mismatch:{path}")
        else:
            verified[path] = str(actual)
    if verification_errors:
        # Fail closed: the run stays unqualified and the analysis is invalid.
        errors.extend(verification_errors)
        return
    result["qualification_basis"] = {
        "issue": record.get("issue"),
        "fix_commit": record.get("fix_commit"),
        "basis": record.get("basis"),
        "evidence": record.get("evidence", []),
        "limits": record.get("limits", []),
        "verified_sources": verified,
    }
    result["qualification"] = {
        "minstret": record["minstret"],
        "cpi": record["cpi"],
        "normalized_score": record["normalized_score"],
        "published_compliance": record["published_compliance"],
    }


def analyze_result(
    raw: dict[str, Any],
    contract: dict[str, Any] | str | Path = DEFAULT_CONTRACT,
    expected_benchmark: str | None = None,
    expected_iterations: int | None = None,
    build_metadata: dict[str, Any] | None = None,
    qualification_record: dict[str, Any] | None = None,
    source_hashes: dict[str, Any] | None = None,
) -> dict[str, Any]:
    contract_data = _load_contract(contract)
    errors: list[str] = []
    warnings: list[str] = []
    result: dict[str, Any] = {
        "schema_version": 1,
        "valid": False,
        "failure_reasons": errors,
        "warnings": warnings,
        "qualification": {
            "minstret": "unqualified",
            "cpi": "unqualified",
            "normalized_score": "engineering_estimate_only",
            "published_compliance": False,
        },
        "published_score": None,
        "raw_reason": raw.get("reason") if isinstance(raw, dict) else "invalid_raw_result",
    }
    if not isinstance(raw, dict):
        errors.append("raw_result_is_not_an_object")
        return result
    if raw.get("schema_version") != 1:
        errors.append("unsupported_raw_schema_version")
    words_raw = raw.get("words")
    if not isinstance(words_raw, list) or len(words_raw) < 64:
        errors.append("raw_words_missing_or_short")
        result["word_count"] = len(words_raw) if isinstance(words_raw, list) else None
        return result
    try:
        words = [_word(value, index) for index, value in enumerate(words_raw[:64])]
    except (ValueError, TypeError) as exc:
        errors.append(f"invalid_word_data:{exc}")
        return result

    magic = int(str(contract_data["magic"]), 0)
    expected_version = int(contract_data["version"])
    statuses = {int(value): str(key) for key, value in contract_data["status"].items()}
    benchmark_ids = {str(key): int(value) for key, value in contract_data["benchmarks"].items()}
    id_names = {value: key for key, value in benchmark_ids.items()}
    result.update({
        "magic": f"0x{words[0]:08x}",
        "version": words[1],
        "status": statuses.get(words[2], "unknown"),
        "benchmark_id": words[3],
        "benchmark": id_names.get(words[3]),
        "iterations": words[4],
        "validation_errors": words[5],
        "error_code": f"0x{words[18]:08x}",
        "firmware_trap": {"cause": words[19], "epc": words[20], "tval": words[21]},
        "counter_checks": words[22],
        "probe_expected": words[24],
        "probe_observed": words[25],
        "result_flags": words[27],
        "coremark_crc": {"list": f"0x{words[14]:04x}", "matrix": f"0x{words[15]:04x}",
                         "state": f"0x{words[16]:04x}", "final": f"0x{words[17]:04x}"},
        "words": [f"0x{word:08x}" for word in words],
        "testbench_marker": raw.get("testbench_marker"),
    })

    if words[0] != magic:
        errors.append("result_magic_mismatch")
    if words[1] != expected_version:
        errors.append("result_version_mismatch")
    if words[2] not in statuses:
        errors.append("unknown_terminal_status")
    elif words[2] != int(contract_data["status"]["pass"]):
        errors.append(f"firmware_status_{statuses[words[2]]}")
    if words[3] not in id_names:
        errors.append("unknown_benchmark_id")
    if expected_benchmark is not None:
        if expected_benchmark not in benchmark_ids:
            errors.append("unsupported_expected_benchmark")
        elif words[3] != benchmark_ids[expected_benchmark]:
            errors.append("benchmark_id_mismatch")
        elif result["benchmark"] != expected_benchmark:
            errors.append("benchmark_name_mismatch")
    if words[4] == 0:
        errors.append("zero_iterations")
    if expected_iterations is not None and words[4] != int(expected_iterations):
        errors.append("iteration_count_mismatch")
    if words[5] != 0:
        errors.append("firmware_validation_errors_nonzero")
    if raw.get("testbench_marker") != "BENCH_TB_PASS":
        errors.append("missing_testbench_pass_marker")
    if raw.get("reason") != "none":
        errors.append(f"testbench_reason:{raw.get('reason')}")
    running_seen = raw.get("running_seen")
    if not (running_seen is True or (type(running_seen) is int and running_seen == 1)):
        errors.append("running_status_not_observed")
    if words[18] != 0:
        errors.append("firmware_error_code_nonzero")
    if any(words[index] != 0 for index in (19, 20, 21)):
        errors.append("firmware_trap_details_nonzero")
    trap_seen = raw.get("trap_seen")
    if not (trap_seen is False or (type(trap_seen) is int and trap_seen == 0)):
        errors.append("trap_observed" if trap_seen is True or trap_seen == 1 else "trap_observation_missing_or_invalid")

    cycle_start = (words[7] << 32) | words[6]
    cycle_end = (words[9] << 32) | words[8]
    instret_start = (words[11] << 32) | words[10]
    instret_end = (words[13] << 32) | words[12]
    cycle_delta = (cycle_end - cycle_start) % COUNTER_MODULUS
    instret_delta = (instret_end - instret_start) % COUNTER_MODULUS
    result.update({
        "cycle_start_raw": cycle_start,
        "cycle_end_raw": cycle_end,
        "cycle_delta": cycle_delta,
        "raw_instret_start": instret_start,
        "raw_instret_end": instret_end,
        "raw_instret_delta_unqualified": instret_delta,
        "observed_clock_cycles": raw.get("observed_clock_cycles"),
        "held_wb_cycles": raw.get("held_wb_cycles"),
        "raw_wb_valid_cycles": raw.get("raw_wb_valid_cycles"),
        "timing_phase_first_cycle": raw.get("timing_phase_first_cycle"),
        "timing_phase_last_cycle": raw.get("timing_phase_last_cycle"),
        "trap_seen": bool(raw.get("trap_seen", False)),
    })
    if cycle_delta == 0:
        errors.append("zero_firmware_cycle_delta")
    observed_cycles = raw.get("observed_clock_cycles")
    if isinstance(observed_cycles, bool) or not isinstance(observed_cycles, int) or observed_cycles <= 0:
        errors.append("invalid_observed_clock_cycles")
    elif cycle_delta > observed_cycles:
        errors.append("firmware_cycle_delta_exceeds_observed_clock_cycles")
    if words[4] > 0 and cycle_delta > 0:
        result["cycles_per_iteration"] = cycle_delta / words[4]
    else:
        result["cycles_per_iteration"] = None
    if instret_delta > 0 and cycle_delta > 0:
        result["cpi_raw_unqualified"] = cycle_delta / instret_delta
    else:
        result["cpi_raw_unqualified"] = None
        warnings.append("raw_minstret_delta_is_zero_or_unavailable")
    # Stable aliases: the same measured values, independent of the
    # qualification label that the record below may attach to them.
    result["instret_delta"] = instret_delta
    result["cpi"] = result["cpi_raw_unqualified"]

    clock_hz = MODELED_CLOCK_HZ
    result["clock_hz_source"] = "testbench_10ns_clock"
    result["modeled_clock_hz"] = MODELED_CLOCK_HZ
    result["firmware_clock_hz"] = words[28]
    if words[28] != MODELED_CLOCK_HZ:
        errors.append("firmware_clock_hz_does_not_match_testbench")

    score: dict[str, Any] | None = None
    functional_pass = not errors
    if functional_pass and cycle_delta > 0 and words[4] > 0:
        if result["benchmark"] == "coremark":
            score = {
                "label": "CoreMark/MHz engineering estimate",
                "value": words[4] * 1_000_000 / cycle_delta,
                "published_compliant": False,
                "limitations": [
                    "short RTL campaign has not demonstrated the published minimum run duration",
                    "full required validation-seed and source/configuration evidence is not present",
                ],
            }
        elif result["benchmark"] == "dhrystone":
            dhrystones_per_second = words[4] * clock_hz / cycle_delta
            score = {
                "label": "Dhrystones/second engineering estimate",
                "value": dhrystones_per_second,
                "dmips_estimate": dhrystones_per_second / 1757,
                "published_compliant": False,
                "limitations": ["RTL simulation cycles and modeled clock are engineering evidence, not a published-system score"],
            }
    result["engineering_score_estimate"] = score

    if build_metadata is not None:
        result["build_metadata"] = build_metadata
        benchmark_values: list[Any] = []
        id_values: list[Any] = []
        iteration_values: list[Any] = []
        _metadata_values(build_metadata, {"benchmark", "benchmark_name"}, benchmark_values)
        _metadata_values(build_metadata, {"benchmark_id", "id"}, id_values)
        _metadata_values(build_metadata, {"iterations", "iteration_count"}, iteration_values)
        if expected_benchmark and benchmark_values:
            names = [str(v.get("name")) if isinstance(v, dict) and "name" in v else str(v)
                     for v in benchmark_values]
            if expected_benchmark not in names:
                errors.append("build_metadata_benchmark_mismatch")
        if expected_benchmark and id_values:
            try:
                if benchmark_ids[expected_benchmark] not in [int(v) for v in id_values]:
                    errors.append("build_metadata_id_mismatch")
            except (TypeError, ValueError):
                errors.append("build_metadata_id_invalid")
        if expected_iterations is not None and iteration_values:
            try:
                if int(expected_iterations) not in [int(v) for v in iteration_values]:
                    errors.append("build_metadata_iterations_mismatch")
            except (TypeError, ValueError):
                errors.append("build_metadata_iterations_invalid")

    if qualification_record is not None:
        apply_qualification_record(result, errors, qualification_record, source_hashes)

    if errors:
        result["engineering_score_estimate"] = None
    result["valid"] = not errors
    return result


def analyze_file(
    raw_path: str | Path,
    contract_path: str | Path = DEFAULT_CONTRACT,
    expected_benchmark: str | None = None,
    expected_iterations: int | None = None,
    build_metadata_path: str | Path | None = None,
    qualification_record_path: str | Path | None = None,
    source_hashes_path: str | Path | None = None,
) -> dict[str, Any]:
    path = Path(raw_path)
    if not path.is_file():
        return {
            "schema_version": 1,
            "valid": False,
            "failure_reasons": [f"raw_result_missing:{path}"],
            "published_score": None,
            "engineering_score_estimate": None,
        }
    raw = json.loads(path.read_text(encoding="utf-8"))
    metadata = None
    if build_metadata_path is not None:
        metadata = json.loads(Path(build_metadata_path).read_text(encoding="utf-8"))
    record = None
    if qualification_record_path is not None:
        record = load_qualification_record(qualification_record_path)
    source_hashes = None
    if source_hashes_path is not None:
        source_hashes = json.loads(Path(source_hashes_path).read_text(encoding="utf-8"))
    return analyze_result(raw, contract_path, expected_benchmark, expected_iterations, metadata,
                           record, source_hashes)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("raw_result", type=Path)
    parser.add_argument("--contract", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--benchmark", choices=("smoke", "counter_probe", "coremark", "dhrystone"))
    parser.add_argument("--iterations", type=int)
    parser.add_argument("--build-json", type=Path)
    parser.add_argument("--qualification-record", type=Path)
    parser.add_argument("--source-hashes", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    try:
        result = analyze_file(args.raw_result, args.contract, args.benchmark, args.iterations,
                              args.build_json, args.qualification_record, args.source_hashes)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"analyze_results: error: {exc}", file=sys.stderr)
        return 2
    serialized = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(serialized, encoding="utf-8")
    print(serialized, end="")
    return 0 if result.get("valid") else 1


if __name__ == "__main__":
    raise SystemExit(main())
