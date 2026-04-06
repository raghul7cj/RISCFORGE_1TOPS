/* loadstore_test.c — Verify load/store through data memory
 *
 * Uses a global array (in .data section → DMEM) to test
 * that SW and LW work through the load-store unit.
 *
 * Expected results:
 *   arr = {1, 2, 3, 4, 5}
 *   sum = 1+2+3+4+5 = 15
 *   return value in a0 = 15
 */
volatile int arr[5] = {1, 2, 3, 4, 5};

int main() {
    int sum = 0;
    for (int i = 0; i < 5; i++) {
        sum += arr[i];
    }
    return sum;  /* a0 = 15 = 0x0F */
}
