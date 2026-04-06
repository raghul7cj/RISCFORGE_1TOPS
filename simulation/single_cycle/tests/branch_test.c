/* branch_test.c — Verify branch instructions
 *
 * Expected results:
 *   a=10, b=3 → a > b → result = a - b = 7
 *   return value in a0 = 7
 */
int main() {
    volatile int a = 10;
    volatile int b = 3;
    volatile int result;

    if (a > b) {
        result = a - b;   /* should take this path: result = 7 */
    } else {
        result = b - a;
    }

    return result;  /* a0 = 7 */
}
