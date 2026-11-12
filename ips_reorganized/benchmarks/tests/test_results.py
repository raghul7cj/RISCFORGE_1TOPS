import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "ips/benchmarks/tools"))
from analyze_results import analyze_file, analyze_result  # noqa: E402


def valid_result(benchmark_id=3, status=2):
    words = [0] * 64
    words[0] = 0x42454E43
    words[1] = 1
    words[2] = status
    words[3] = benchmark_id
    words[4] = 100
    words[5] = 0
    words[6] = 100
    words[7] = 1
    words[8] = 5100
    words[9] = 1
    words[10] = 400
    words[11] = 0
    words[12] = 2400
    words[13] = 0
    words[28] = 100_000_000
    return {
        "schema_version": 1,
        "reason": "none" if status == 2 else "firmware_status_fail",
        "testbench_marker": "BENCH_TB_PASS" if status == 2 else "BENCH_TB_FAIL",
        "observed_clock_cycles": 6000,
        "held_wb_cycles": 12,
        "raw_wb_valid_cycles": 5000,
        "running_seen": 1,
        "timing_phase_first_cycle": 120,
        "timing_phase_last_cycle": 4900,
        "trap_seen": 0,
        "words": [f"0x{word:08x}" for word in words],
    }


class ResultAnalysisTests(unittest.TestCase):
    def test_valid_result_keeps_unqualified_counters_and_estimate_label(self):
        result = analyze_result(valid_result(), expected_benchmark="coremark", expected_iterations=100)
        self.assertTrue(result["valid"], result["failure_reasons"])
        self.assertEqual(result["cycle_delta"], 5000)
        self.assertEqual(result["cycles_per_iteration"], 50.0)
        self.assertEqual(result["cpi_raw_unqualified"], 5000 / 2000)
        self.assertEqual(result["qualification"]["minstret"], "unqualified")
        self.assertEqual(result["qualification"]["normalized_score"], "engineering_estimate_only")
        self.assertFalse(result["qualification"]["published_compliance"])
        self.assertIsNone(result["published_score"])
        self.assertFalse(result["engineering_score_estimate"]["published_compliant"])
        self.assertEqual(result["engineering_score_estimate"]["value"], 20_000.0)

    def test_detects_corrupt_magic_and_unsupported_benchmark(self):
        raw = valid_result(benchmark_id=99)
        raw["words"][0] = "0xdeadbeef"
        result = analyze_result(raw)
        self.assertIn("result_magic_mismatch", result["failure_reasons"])
        self.assertIn("unknown_benchmark_id", result["failure_reasons"])
        self.assertFalse(result["valid"])

    def test_preserves_firmware_failure(self):
        result = analyze_result(valid_result(status=3), expected_benchmark="coremark")
        self.assertFalse(result["valid"])
        self.assertIn("firmware_status_fail", result["failure_reasons"])
        self.assertIn("testbench_reason:firmware_status_fail", result["failure_reasons"])

    def test_preserves_watchdog_timeout_and_running_status(self):
        raw = valid_result(status=1)
        raw["reason"] = "cycle_watchdog_timeout"
        raw["testbench_marker"] = "BENCH_TB_FAIL"
        result = analyze_result(raw, expected_benchmark="coremark")
        self.assertIn("firmware_status_running", result["failure_reasons"])
        self.assertIn("testbench_reason:cycle_watchdog_timeout", result["failure_reasons"])
        self.assertIsNone(result["engineering_score_estimate"])

    def test_handles_64_bit_counter_wrap_and_unqualified_zero_instret(self):
        raw = valid_result(benchmark_id=1)
        words = raw["words"]
        words[6] = "0xfffffffe"
        words[7] = "0xffffffff"
        words[8] = "0x00000001"
        words[9] = "0x00000000"
        for index in (10, 11, 12, 13):
            words[index] = "0x00000000"
        result = analyze_result(raw, expected_benchmark="smoke")
        self.assertTrue(result["valid"], result["failure_reasons"])
        self.assertEqual(result["cycle_delta"], 3)
        self.assertIsNone(result["cpi_raw_unqualified"])
        self.assertIn("raw_minstret_delta_is_zero_or_unavailable", result["warnings"])

    def test_rejects_iteration_mismatch_and_zero_timing_delta(self):
        raw = valid_result(benchmark_id=2)
        words = raw["words"]
        words[8] = words[6]
        words[9] = words[7]
        result = analyze_result(raw, expected_benchmark="counter_probe", expected_iterations=101)
        self.assertIn("iteration_count_mismatch", result["failure_reasons"])
        self.assertIn("zero_firmware_cycle_delta", result["failure_reasons"])

    def test_missing_raw_file_is_a_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = analyze_file(Path(temporary) / "missing.json")
        self.assertFalse(result["valid"])
        self.assertTrue(result["failure_reasons"][0].startswith("raw_result_missing:"))

    def test_qualification_record_qualifies_counters_and_records_basis(self):
        record = {
            "schema_version": 1,
            "minstret": "qualified",
            "cpi": "qualified",
            "normalized_score": "engineering_estimate_only",
            "published_compliance": False,
            "basis": "issue closed by a recorded fix commit",
            "issue": "https://example.invalid/issues/16",
            "fix_commit": "0" * 40,
            "required_source_sha256": {"ips/riscv_core/rtl/top.v": "a" * 64},
        }
        source_hashes = {"sha256": {"ips/riscv_core/rtl/top.v": "a" * 64}}
        result = analyze_result(valid_result(), expected_benchmark="coremark", expected_iterations=100,
                                qualification_record=record, source_hashes=source_hashes)
        self.assertTrue(result["valid"], result["failure_reasons"])
        self.assertEqual(result["qualification"]["minstret"], "qualified")
        self.assertEqual(result["qualification"]["cpi"], "qualified")
        self.assertFalse(result["qualification"]["published_compliance"])
        self.assertEqual(result["qualification_basis"]["fix_commit"], "0" * 40)
        self.assertIn("ips/riscv_core/rtl/top.v", result["qualification_basis"]["verified_sources"])

    def test_qualification_record_fails_closed_on_source_mismatch(self):
        record = {
            "schema_version": 1,
            "minstret": "qualified",
            "cpi": "qualified",
            "normalized_score": "engineering_estimate_only",
            "published_compliance": False,
            "basis": "issue closed by a recorded fix commit",
            "required_source_sha256": {"ips/riscv_core/rtl/top.v": "a" * 64},
        }
        source_hashes = {"sha256": {"ips/riscv_core/rtl/top.v": "b" * 64}}
        result = analyze_result(valid_result(), qualification_record=record, source_hashes=source_hashes)
        self.assertFalse(result["valid"])
        self.assertIn("qualification_source_hash_mismatch:ips/riscv_core/rtl/top.v",
                      result["failure_reasons"])
        self.assertEqual(result["qualification"]["minstret"], "unqualified")

    def test_qualification_record_requires_source_hashes_and_valid_schema(self):
        record = {
            "schema_version": 1,
            "minstret": "qualified",
            "cpi": "qualified",
            "normalized_score": "engineering_estimate_only",
            "published_compliance": False,
            "basis": "issue closed by a recorded fix commit",
            "required_source_sha256": {"ips/riscv_core/rtl/top.v": "a" * 64},
        }
        result = analyze_result(valid_result(), qualification_record=record)
        self.assertFalse(result["valid"])
        self.assertIn("qualification_source_hashes_not_provided", result["failure_reasons"])

        broken = dict(record)
        broken["minstret"] = "definitely"
        result = analyze_result(valid_result(), qualification_record=broken,
                                source_hashes={"sha256": {"ips/riscv_core/rtl/top.v": "a" * 64}})
        self.assertFalse(result["valid"])
        self.assertIn("qualification_record_minstret_invalid", result["failure_reasons"])

    def test_build_metadata_identity_is_checked(self):
        metadata = {"target": {"benchmark": {"name": "coremark", "id": 3, "iterations": 100}}}
        result = analyze_result(valid_result(), expected_benchmark="coremark", expected_iterations=100,
                                build_metadata=metadata)
        self.assertTrue(result["valid"], result["failure_reasons"])

    def test_terminal_result_requires_observed_running_status(self):
        raw = valid_result()
        del raw["running_seen"]
        result = analyze_result(raw)
        self.assertIn("running_status_not_observed", result["failure_reasons"])

    def test_cycle_delta_cannot_exceed_the_entire_observed_run(self):
        raw = valid_result()
        raw["observed_clock_cycles"] = 4999
        result = analyze_result(raw)
        self.assertIn("firmware_cycle_delta_exceeds_observed_clock_cycles", result["failure_reasons"])
        self.assertIsNone(result["engineering_score_estimate"])

    def test_error_and_trap_words_override_an_apparent_pass(self):
        raw = valid_result()
        raw["words"][18] = "0x1001"
        raw["words"][19] = "0x2"
        result = analyze_result(raw)
        self.assertIn("firmware_error_code_nonzero", result["failure_reasons"])
        self.assertIn("firmware_trap_details_nonzero", result["failure_reasons"])

    def test_firmware_cannot_relabel_the_simulated_clock(self):
        raw = valid_result(benchmark_id=4)
        raw["words"][28] = "1000000"
        result = analyze_result(raw)
        self.assertIn("firmware_clock_hz_does_not_match_testbench", result["failure_reasons"])
        self.assertIsNone(result["engineering_score_estimate"])

    def test_missing_or_null_trap_observation_is_not_a_pass(self):
        for value in ("missing", None, 0.0):
            with self.subTest(value=value):
                raw = valid_result()
                if value == "missing":
                    del raw["trap_seen"]
                else:
                    raw["trap_seen"] = value
                result = analyze_result(raw)
                self.assertIn("trap_observation_missing_or_invalid", result["failure_reasons"])
                self.assertIsNone(result["engineering_score_estimate"])


if __name__ == "__main__":
    unittest.main()
