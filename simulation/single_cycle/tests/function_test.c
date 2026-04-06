/* function_test.c — Verify JAL/JALR and stack frames
 *
 * Tests function call and return mechanism.
 *
 * Expected results:
 *   add(3, 4) = 7
 *   multiply_by_add(3, 4) = 12
 *   total = 7 + 12 = 19
 *   return value in a0 = 19 = 0x13
 */

int add(int x, int y) {
    return x + y;
}

int multiply_by_add(int x, int y) {
    int result = 0;
    for (int i = 0; i < y; i++) {
        result = add(result, x);
    }
    return result;
}

int main() {
    int a = add(3, 4);             /* 7 */
    int b = multiply_by_add(3, 4); /* 12 */
    int total = a + b;             /* 19 */
    return total;  /* a0 = 19 = 0x13 */
}
