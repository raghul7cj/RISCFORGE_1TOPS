#include "benchmark.h"

#include <stdarg.h>
#include <stddef.h>

#ifndef BENCHMARK_ID
#define BENCHMARK_ID BENCHMARK_SMOKE
#endif
#ifndef BENCHMARK_ITERATIONS
#define BENCHMARK_ITERATIONS 1
#endif
#ifndef BENCHMARK_CLOCK_HZ
#define BENCHMARK_CLOCK_HZ 100000000
#endif

static volatile uint32_t *const result_words =
    (volatile uint32_t *)0x00020000u;
volatile benchmark_result_block_t *const benchmark_result =
    (volatile benchmark_result_block_t *)0x00020000u;
volatile uint32_t benchmark_requested_iterations = BENCHMARK_ITERATIONS;
static uint32_t console_sequence;

_Static_assert(sizeof(benchmark_result_block_t) == 29u * sizeof(uint32_t),
               "result fields must remain 29 consecutive u32 words");
_Static_assert(sizeof(benchmark_result_block_t) <= 256u,
               "result structure exceeds its reserved block");

static uint64_t combine_words(uint32_t lo, uint32_t hi)
{
    return ((uint64_t)hi << 32) | (uint64_t)lo;
}

uint64_t benchmark_read_mcycle64(void)
{
    uint32_t hi0;
    uint32_t lo;
    uint32_t hi1;
    do {
        __asm__ volatile("csrr %0, mcycleh" : "=r"(hi0));
        __asm__ volatile("csrr %0, mcycle" : "=r"(lo));
        __asm__ volatile("csrr %0, mcycleh" : "=r"(hi1));
    } while (hi0 != hi1);
    return combine_words(lo, hi0);
}

uint64_t benchmark_read_minstret64(void)
{
    uint32_t hi0;
    uint32_t lo;
    uint32_t hi1;
    do {
        __asm__ volatile("csrr %0, minstreth" : "=r"(hi0));
        __asm__ volatile("csrr %0, minstret" : "=r"(lo));
        __asm__ volatile("csrr %0, minstreth" : "=r"(hi1));
    } while (hi0 != hi1);
    return combine_words(lo, hi0);
}

static void split_counter(uint64_t value, volatile uint32_t *lo,
                          volatile uint32_t *hi)
{
    *lo = (uint32_t)value;
    *hi = (uint32_t)(value >> 32);
}

void benchmark_init(uint32_t benchmark_id, uint32_t iterations,
                    uint32_t clock_hz)
{
    uint32_t i;
    for (i = 0; i < 256u / sizeof(uint32_t); ++i) {
        result_words[i] = 0;
    }
    console_sequence = 0;
    benchmark_result->magic = BENCHMARK_MAGIC;
    benchmark_result->version = BENCHMARK_VERSION;
    benchmark_result->benchmark_id = benchmark_id;
    benchmark_result->iterations = iterations;
    benchmark_result->clock_hz = clock_hz;
    benchmark_result->result_flags = RESULT_FLAG_RETIREMENT_UNQUALIFIED |
                                     RESULT_FLAG_RTL_CAVEATS_PRESENT;
    __asm__ volatile("" ::: "memory");
    benchmark_result->status = BENCHMARK_STATUS_RUNNING;
}

void benchmark_timing_start(void)
{
    uint64_t cycles;
    uint64_t instret;
    benchmark_result->timing_phase = 1;
    __asm__ volatile("" ::: "memory");
    cycles = benchmark_read_mcycle64();
    instret = benchmark_read_minstret64();
    split_counter(cycles, &benchmark_result->cycle_start_lo,
                  &benchmark_result->cycle_start_hi);
    split_counter(instret, &benchmark_result->instret_start_lo,
                  &benchmark_result->instret_start_hi);
    __asm__ volatile("" ::: "memory");
}

void benchmark_timing_stop(void)
{
    uint64_t cycles;
    uint64_t instret;
    uint64_t cycle_start;
    uint64_t instret_start;
    benchmark_result->timing_phase = 1;
    __asm__ volatile("" ::: "memory");
    cycles = benchmark_read_mcycle64();
    instret = benchmark_read_minstret64();
    split_counter(cycles, &benchmark_result->cycle_end_lo,
                  &benchmark_result->cycle_end_hi);
    split_counter(instret, &benchmark_result->instret_end_lo,
                  &benchmark_result->instret_end_hi);
    cycle_start = combine_words(benchmark_result->cycle_start_lo,
                                benchmark_result->cycle_start_hi);
    instret_start = combine_words(benchmark_result->instret_start_lo,
                                  benchmark_result->instret_start_hi);
    if (cycles > cycle_start) {
        benchmark_result->counter_checks |= COUNTER_CHECK_CYCLE_DELTA_NONZERO;
    }
    if (instret > instret_start) {
        benchmark_result->counter_checks |= COUNTER_CHECK_INSTRET_DELTA_NONZERO;
    }
    if (cycles >= cycle_start && instret >= instret_start) {
        benchmark_result->counter_checks |= COUNTER_CHECK_MONOTONIC;
    }
    __asm__ volatile("" ::: "memory");
    benchmark_result->timing_phase = 2;
}

void benchmark_set_validation_errors(int32_t errors, uint32_t error_code)
{
    benchmark_result->validation_errors = (uint32_t)errors;
    if (error_code != 0 && benchmark_result->error_code == 0) {
        benchmark_result->error_code = error_code;
    }
}

void benchmark_record_error(uint32_t error_code)
{
    benchmark_result->validation_errors += 1;
    if (benchmark_result->error_code == 0) {
        benchmark_result->error_code = error_code;
    }
}

static void halt_forever(void) __attribute__((noreturn));
static void halt_forever(void)
{
    for (;;) {
        __asm__ volatile("j ." ::: "memory");
    }
}

void benchmark_finish(void)
{
    uint32_t status = BENCHMARK_STATUS_PASS;
    if (benchmark_result->validation_errors != 0 ||
        benchmark_result->trap_cause != 0 ||
        benchmark_result->error_code != 0) {
        status = BENCHMARK_STATUS_FAIL;
    }
    __asm__ volatile("" ::: "memory");
    benchmark_result->status = status;
    halt_forever();
}

void benchmark_unexpected_return(void)
{
    if (benchmark_result->magic != BENCHMARK_MAGIC ||
        benchmark_result->status != BENCHMARK_STATUS_RUNNING) {
        benchmark_init(BENCHMARK_ID, BENCHMARK_ITERATIONS,
                       BENCHMARK_CLOCK_HZ);
    }
    benchmark_record_error(0x0000fff0u);
    benchmark_finish();
}

void benchmark_trap_c(void)
{
    uint32_t cause;
    uint32_t epc;
    uint32_t tval;
    __asm__ volatile("csrr %0, mcause" : "=r"(cause));
    __asm__ volatile("csrr %0, mepc" : "=r"(epc));
    __asm__ volatile("csrr %0, mtval" : "=r"(tval));
    if (benchmark_result->magic != BENCHMARK_MAGIC ||
        benchmark_result->status != BENCHMARK_STATUS_RUNNING) {
        benchmark_init(BENCHMARK_ID, BENCHMARK_ITERATIONS,
                       BENCHMARK_CLOCK_HZ);
    }
    benchmark_result->trap_cause = cause;
    benchmark_result->trap_epc = epc;
    benchmark_result->trap_tval = tval;
    benchmark_result->validation_errors = 1;
    benchmark_result->error_code = 0x0000f001u;
    __asm__ volatile("" ::: "memory");
    benchmark_result->status = BENCHMARK_STATUS_FAIL;
    halt_forever();
}

void benchmark_console_putc(char byte)
{
    console_sequence = (console_sequence + 1u) & 0x00ffffffu;
    benchmark_result->console_word = (console_sequence << 8) |
                                     (uint32_t)(uint8_t)byte;
}

static int starts_with(const char *text, const char *prefix)
{
    while (*prefix != '\0') {
        if (*text++ != *prefix++) {
            return 0;
        }
    }
    return 1;
}

static void emit_unsigned(uint32_t value, uint32_t base, int upper)
{
    char buffer[32];
    unsigned int count = 0;
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    do {
        buffer[count++] = digits[value % base];
        value /= base;
    } while (value != 0 && count < sizeof(buffer));
    while (count != 0) {
        benchmark_console_putc(buffer[--count]);
    }
}

int firmware_vprintf(const char *format, va_list args)
{
    int emitted = 0;
    if (starts_with(format, "Iterations/Sec") ||
        starts_with(format, "CoreMark 1.0") ||
        starts_with(format, "Dhrystones per Second") ||
        starts_with(format, "Microseconds for one run")) {
        return 0;
    }
    while (*format != '\0') {
        if (*format != '%') {
            benchmark_console_putc(*format++);
            ++emitted;
            continue;
        }
        ++format;
        if (*format == '%') {
            benchmark_console_putc('%');
            ++format;
            ++emitted;
            continue;
        }
        while (*format == '-' || *format == '+' || *format == '0' ||
               *format == '#' || *format == ' ' || *format == '.') {
            ++format;
        }
        while (*format >= '0' && *format <= '9') {
            ++format;
        }
        {
            int long_argument = 0;
            if (*format == 'l') {
                long_argument = 1;
                ++format;
                if (*format == 'l') {
                    ++format;
                }
            } else if (*format == 'h' || *format == 'z') {
                ++format;
            }
            switch (*format) {
            case 's': {
                const char *string = va_arg(args, const char *);
                if (string == NULL) {
                    string = "(null)";
                }
                while (*string != '\0') {
                    benchmark_console_putc(*string++);
                    ++emitted;
                }
                break;
            }
            case 'c':
                benchmark_console_putc((char)va_arg(args, int));
                ++emitted;
                break;
            case 'd':
            case 'i': {
                int32_t value = long_argument
                                    ? (int32_t)va_arg(args, long)
                                    : (int32_t)va_arg(args, int);
                uint32_t magnitude;
                if (value < 0) {
                    benchmark_console_putc('-');
                    ++emitted;
                    magnitude = 0u - (uint32_t)value;
                } else {
                    magnitude = (uint32_t)value;
                }
                emit_unsigned(magnitude, 10u, 0);
                ++emitted;
                break;
            }
            case 'u':
                emit_unsigned(long_argument
                                  ? (uint32_t)va_arg(args, unsigned long)
                                  : (uint32_t)va_arg(args, unsigned int),
                              10u, 0);
                ++emitted;
                break;
            case 'x':
                emit_unsigned(long_argument
                                  ? (uint32_t)va_arg(args, unsigned long)
                                  : (uint32_t)va_arg(args, unsigned int),
                              16u, 0);
                ++emitted;
                break;
            case 'X':
                emit_unsigned(long_argument
                                  ? (uint32_t)va_arg(args, unsigned long)
                                  : (uint32_t)va_arg(args, unsigned int),
                              16u, 1);
                ++emitted;
                break;
            case 'p':
                emit_unsigned((uint32_t)(uintptr_t)va_arg(args, void *),
                              16u, 0);
                ++emitted;
                break;
            default:
                benchmark_console_putc('%');
                if (*format != '\0') {
                    benchmark_console_putc(*format);
                    ++format;
                }
                emitted += 2;
                break;
            }
        }
        if (*format != '\0') {
            ++format;
        }
    }
    return emitted;
}

int firmware_printf(const char *format, ...)
{
    int emitted;
    va_list args;
    va_start(args, format);
    emitted = firmware_vprintf(format, args);
    va_end(args);
    return emitted;
}

int printf(const char *format, ...)
{
    int emitted;
    va_list args;
    va_start(args, format);
    emitted = firmware_vprintf(format, args);
    va_end(args);
    return emitted;
}

void *memcpy(void *destination, const void *source, size_t count)
{
    unsigned char *dst = (unsigned char *)destination;
    const unsigned char *src = (const unsigned char *)source;
    size_t i;
    for (i = 0; i < count; ++i) {
        dst[i] = src[i];
    }
    return destination;
}

void *memset(void *destination, int value, size_t count)
{
    unsigned char *dst = (unsigned char *)destination;
    size_t i;
    for (i = 0; i < count; ++i) {
        dst[i] = (unsigned char)value;
    }
    return destination;
}

size_t strlen(const char *text)
{
    size_t count = 0;
    while (text[count] != '\0') {
        ++count;
    }
    return count;
}

char *strcpy(char *destination, const char *source)
{
    char *original = destination;
    while ((*destination++ = *source++) != '\0') {
    }
    return original;
}

int strcmp(const char *left, const char *right)
{
    while (*left != '\0' && *left == *right) {
        ++left;
        ++right;
    }
    return (unsigned char)*left - (unsigned char)*right;
}

void benchmark_dhrystone_timer_start(void)
{
    benchmark_timing_start();
}

void benchmark_dhrystone_timer_stop(void)
{
    benchmark_timing_stop();
}

void benchmark_coremark_report(int32_t total_errors, int32_t crc_errors,
                               uint32_t crc_list,
                               uint32_t crc_matrix, uint32_t crc_state,
                               uint32_t crc_final)
{
    uint64_t start = combine_words(benchmark_result->cycle_start_lo,
                                   benchmark_result->cycle_start_hi);
    uint64_t end = combine_words(benchmark_result->cycle_end_lo,
                                 benchmark_result->cycle_end_hi);
    uint64_t minimum_ticks = (uint64_t)benchmark_result->clock_hz * 10u;
    int short_run = end >= start && end - start < minimum_ticks;
    benchmark_result->crc_list = crc_list;
    benchmark_result->crc_matrix = crc_matrix;
    benchmark_result->crc_state = crc_state;
    benchmark_result->crc_final = crc_final;
    if (short_run) {
        benchmark_result->result_flags |= RESULT_FLAG_SHORT_COREMARK_RUN;
    }
    // Upstream selects its CRC table from the seed/data-size signature and
    // records CRC failures in results[0].err. Do not duplicate that table here:
    // the 2K validation configuration differs from 6K validation. A negative
    // crc_errors means upstream did not recognize the configuration.
    if (crc_errors > 0) {
        benchmark_set_validation_errors(total_errors, 0x00003002u);
    } else if (crc_errors < 0) {
        benchmark_set_validation_errors(total_errors, 0x00003003u);
    } else if (short_run && total_errors == 1) {
        benchmark_set_validation_errors(total_errors, 0x00003001u);
    } else if (total_errors != 0 || short_run) {
        benchmark_set_validation_errors(total_errors, 0x00003003u);
    } else {
        benchmark_set_validation_errors(0, 0);
    }
    benchmark_finish();
}

