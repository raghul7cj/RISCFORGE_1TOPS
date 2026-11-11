/* ==============================================================================
 * File: main.c
 * Description: Sample bare-metal C program for RV32I processor core
 * ============================================================================== */

int add(int a, int b) {
    return a + b;
}

int main() {
    volatile int x = 10;
    volatile int y = 20;
    volatile int result = add(x, y);

    // Loop through an array
    volatile int arr[5] = {1, 2, 3, 4, 5};
    volatile int sum = 0;
    for (int i = 0; i < 5; i++) {
        sum += arr[i];
    }

    return result + sum;
}









