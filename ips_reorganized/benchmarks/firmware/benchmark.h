#ifndef RISCFORGE_BENCHMARK_H
#define RISCFORGE_BENCHMARK_H

#include <stdint.h>
#include <stdarg.h>

#define BENCHMARK_MAGIC 0x42454e43u
#define BENCHMARK_VERSION 1u

#define BENCHMARK_STATUS_EMPTY 0u
#define BENCHMARK_STATUS_RUNNING 1u
#define BENCHMARK_STATUS_PASS 2u
#define BENCHMARK_STATUS_FAIL 3u

#define BENCHMARK_SMOKE 1u
#define BENCHMARK_COUNTER_PROBE 2u
#define BENCHMARK_COREMARK 3u
#define BENCHMARK_DHRYSTONE 4u

#define RESULT_FLAG_RETIREMENT_UNQUALIFIED (1u << 0)
#define RESULT_FLAG_RTL_CAVEATS_PRESENT (1u << 1)
#define RESULT_FLAG_SHORT_COREMARK_RUN (1u << 2)
#define RESULT_FLAG_DIAGNOSTIC_PROBE (1u << 3)

#define COUNTER_CHECK_CYCLE_DELTA_NONZERO (1u << 0)
#define COUNTER_CHECK_INSTRET_DELTA_NONZERO (1u << 1)
#define COUNTER_CHECK_MONOTONIC (1u << 2)

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t status;
    uint32_t benchmark_id;
    uint32_t iterations;
    uint32_t validation_errors;
    uint32_t cycle_start_lo;
    uint32_t cycle_start_hi;
    uint32_t cycle_end_lo;
    uint32_t cycle_end_hi;
    uint32_t instret_start_lo;
    uint32_t instret_start_hi;
    uint32_t instret_end_lo;
    uint32_t instret_end_hi;
    uint32_t crc_list;
    uint32_t crc_matrix;
    uint32_t crc_state;
    uint32_t crc_final;
    uint32_t error_code;
    uint32_t trap_cause;
    uint32_t trap_epc;
    uint32_t trap_tval;
    uint32_t counter_checks;
    uint32_t console_word;
    uint32_t probe_expected;
    uint32_t probe_observed;
    uint32_t timing_phase;
    uint32_t result_flags;
    uint32_t clock_hz;
} benchmark_result_block_t;

extern volatile benchmark_result_block_t *const benchmark_result;
extern volatile uint32_t benchmark_requested_iterations;

void benchmark_init(uint32_t benchmark_id, uint32_t iterations, uint32_t clock_hz);
uint64_t benchmark_read_mcycle64(void);
uint64_t benchmark_read_minstret64(void);
void benchmark_timing_start(void);
void benchmark_timing_stop(void);
void benchmark_set_validation_errors(int32_t errors, uint32_t error_code);
void benchmark_record_error(uint32_t error_code);
void benchmark_finish(void) __attribute__((noreturn));
void benchmark_unexpected_return(void) __attribute__((noreturn));
void benchmark_trap_c(void) __attribute__((noreturn));
void benchmark_console_putc(char byte);
int firmware_printf(const char *format, ...);
int firmware_vprintf(const char *format, va_list args);

void benchmark_dhrystone_timer_start(void);
void benchmark_dhrystone_timer_stop(void);
void benchmark_dhrystone_validate(int int_1, int int_2, int int_3,
                                  int enum_loc, const char *str_1,
                                  const char *str_2);
void benchmark_coremark_report(int32_t total_errors, int32_t crc_errors,
                               uint32_t crc_list,
                               uint32_t crc_matrix, uint32_t crc_state,
                               uint32_t crc_final);

#endif
