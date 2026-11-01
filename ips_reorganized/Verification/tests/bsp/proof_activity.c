/* =============================================================================
 * RISCFORGE 1TOPS — Proof-Stage Activity Attestation Storage (proof_activity.c)
 * =============================================================================
 * Definitions for the firmware-observed activity counters declared in
 * proof_activity.h. Kept in .bss (DSRAM) by link.ld so the counters survive
 * across the whole run and the TB can read them back out of memory if needed.
 * ============================================================================= */

#include "proof_activity.h"

volatile uint32_t proof_dsram_reads;
volatile uint32_t proof_dsram_sig;
volatile uint32_t proof_mmio_reads;
volatile uint32_t proof_mmio_writes;
volatile uint32_t proof_mmio_slots_touched;
volatile uint32_t proof_slot_bitmap;

volatile uint32_t proof_dscratch[PROOF_DSRAM_WORDS];
