"""Upstream validation remains authoritative; report classification stays separate."""
import importlib.util
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def function_body(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


class CoreMarkHookTests(unittest.TestCase):
    def test_generated_copy_preserves_upstream_checks(self):
        spec = importlib.util.spec_from_file_location("builder", ROOT / "tools/build_firmware.py")
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        upstream = ROOT / "vendor/upstream/coremark/core_main.c"
        before = upstream.read_bytes()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "core_main.c"
            builder.patch_coremark_main(upstream, output)
            generated = output.read_text()
        self.assertEqual(before, upstream.read_bytes())
        self.assertIn("known_id >= 0 ? (int32_t)results[0].err : -1", generated)
        # Only an include and a post-validation reporting call may differ.
        restored = generated.replace('#include "benchmark.h"\n', "", 1)
        start = restored.index("    benchmark_coremark_report(")
        end = restored.index(";\n", start) + 2
        restored = restored[:start] + restored[end:]
        self.assertEqual(restored, before.decode().replace("\r\n", "\n"))

    @unittest.skipUnless(shutil.which("gcc"), "native GCC required; run this test under WSL")
    def test_actual_c_report_duration_crc_and_other_failures(self):
        source = (ROOT / "firmware/runtime.c").read_text()
        actual = "\n\n".join(function_body(source, signature) for signature in [
            "static uint64_t combine_words(", "void benchmark_set_validation_errors(",
            "void benchmark_finish(", "void benchmark_coremark_report("])
        harness = r'''
#include "benchmark.h"
#include <setjmp.h>
#include <stdio.h>
#include <string.h>
static benchmark_result_block_t result;
volatile benchmark_result_block_t *const benchmark_result = &result;
static jmp_buf stop;
static void halt_forever(void) { longjmp(stop, 1); }
'''
        checks = r'''
typedef struct {
    const char *name;
    int total_errors, crc_errors;
    uint64_t start, ticks;
    unsigned list, matrix, state, code, status;
} report_case;
int main(void) {
    const report_case cases[] = {
      {"2K validation accepted",0,0,0,1000000000ULL,0xe3c1,0x0747,0x8d84,0,2},
      {"6K validation accepted",0,0,0,1000000000ULL,0x3340,0x1199,0x39bf,0,2},
      {"short correct CRCs",1,0,0,534940,0xe3c1,0x0747,0x8d84,0x3001,3},
      {"CRC failure",1,1,0,1000000000ULL,0,0,0,0x3002,3},
      {"CRC plus duration",2,1,0,534940,0,0,0,0x3002,3},
      {"other upstream error",1,0,0,1000000000ULL,0xe3c1,0x0747,0x8d84,0x3003,3},
      {"other plus duration",2,0,0,534940,0xe3c1,0x0747,0x8d84,0x3003,3},
      {"unknown seeds",-1,-1,0,1000000000ULL,0,0,0,0x3003,3},
      {"unknown plus duration",0,-1,0,534940,0,0,0,0x3003,3},
      {"inconsistent short success",0,0,0,534940,0xe3c1,0x0747,0x8d84,0x3003,3},
      {"one tick below minimum",1,0,0,999999999ULL,0xe3c1,0x0747,0x8d84,0x3001,3},
      {"snapshot low-word carry",0,0,0xfffffff0ULL,1000000000ULL,0xe3c1,0x0747,0x8d84,0,2}
    };
    for (unsigned i=0;i<sizeof(cases)/sizeof(cases[0]);++i) {
        const report_case *c=&cases[i];
        uint64_t end=c->start+c->ticks;
        memset(&result,0,sizeof(result));
        result.clock_hz=100000000;
        result.cycle_start_lo=c->start; result.cycle_start_hi=c->start>>32;
        result.cycle_end_lo=end; result.cycle_end_hi=end>>32;
        if(setjmp(stop)==0)
            benchmark_coremark_report(c->total_errors,c->crc_errors,c->list,c->matrix,c->state,0x1234);
        if(result.error_code!=c->code || result.status!=c->status ||
           result.validation_errors!=(uint32_t)c->total_errors ||
           result.crc_list!=c->list || result.crc_matrix!=c->matrix ||
           result.crc_state!=c->state || result.crc_final!=0x1234 ||
           !!(result.result_flags & RESULT_FLAG_SHORT_COREMARK_RUN)!=(c->ticks<1000000000ULL)) {
            printf("FAIL %s code=%x status=%u errors=%u\n",c->name,result.error_code,result.status,result.validation_errors);
            return 1;
        }
        printf("PASS %s\n",c->name);
    }
    return 0;
}
'''
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            path = directory / "report_cases.c"
            path.write_text(harness + actual + checks)
            executable = directory / "report_cases"
            compiled = subprocess.run(["gcc", "-std=c11", "-O0", "-I", str(ROOT / "firmware"),
                                       str(path), "-o", str(executable)], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = subprocess.run([str(executable)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout.count("PASS "), 12, result.stdout)
            print(result.stdout, end="")


if __name__ == "__main__":
    unittest.main()
