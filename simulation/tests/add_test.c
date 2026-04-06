/* add_test.c — Verify basic arithmetic operations
 *
 * Expected results (check register dump):
 *   The final value of z (a + b) should be 12 (0x0C),
 *   stored on the stack. After main returns, a0 should
 *   hold the return value from main (12).
 */
int main() {
    volatile int a = 6;
    volatile int b = 7;
    volatile int z = a + b;  /* z = 12 */
    return z;  /* a0 = 12 = 0x0C */
}
