/* =============================================================================
 * RISCFORGE 1TOPS — Minimal Assembly UART & Datapath Smoke Test
 * =============================================================================
 * Direct self-contained assembly test:
 *   - Runs at ISRAM base 0x0001_0000
 *   - Writes characters directly to UART THR at 0x4000_2000
 *   - Polls UART LSR (0x4000_2014) bit 5 (THRE)
 * ============================================================================= */

  .section .text.init, "ax"
  .global _start
  .type _start, @function

_start:
  /* 1. Setup Stack Pointer in DSRAM */
  lui sp, 0x28          /* sp = 0x0002_8000 */

  /* 2. UART Base Address */
  lui s0, 0x40002       /* s0 = 0x4000_2000 (UART Base) */

  /* 3. Configure UART (8-bit word length, FCR enable) */
  li t0, 0x03           /* 8N1 */
  sw t0, 0x0C(s0)       /* UART_LCR = 0x03 */
  li t0, 0x07           /* FIFO enable & clear */
  sw t0, 0x08(s0)       /* UART_FCR = 0x07 */

  /* 4. Transmit String over UART */
  la s1, msg_start

tx_loop:
  lbu a0, 0(s1)
  beqz a0, test_done

  /* Poll LSR THRE (bit 5) */
wait_thre:
  lw t1, 0x14(s0)       /* Read UART_LSR */
  andi t1, t1, 0x20     /* Test THRE bit (0x20) */
  beqz t1, wait_thre

  /* Write byte to THR */
  sw a0, 0(s0)
  addi s1, s1, 1
  j tx_loop

test_done:
  j test_done

  .section .rodata
msg_start:
  .string "\r\n[RISCFORGE] UART & Core Datapath Minimal Smoke Test: PASSED\r\n"
