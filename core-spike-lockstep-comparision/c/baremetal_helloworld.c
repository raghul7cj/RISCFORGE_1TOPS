volatile char sim_buffer[64];
volatile int  idx = 0;

void print_sim(const char *str) {
    while (*str) {
        sim_buffer[idx++] = *str++;
    }
}

int main(void) {
    print_sim("hello world !\n");
    return 0; 
}
