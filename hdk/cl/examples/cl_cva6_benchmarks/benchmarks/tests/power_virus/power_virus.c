#include "bench.h"

int main(void)
{
    bench_banner("power_virus");
    uint64_t t0 = rdcycle();
    volatile uint64_t a = 0x0123456789abcdefull;
    volatile uint64_t b = 0xfedcba9876543210ull;
    volatile double f = 1.1;
    for (uint64_t i = 0; i < 200000u; i++) {
        a = a * 6364136223846793005ull + 1;
        b ^= (a << 7) | (a >> 3);
        f = f * 1.0000001 + (double)(a & 0xff);
        a += (uint64_t)f;
    }
    uint64_t t1 = rdcycle();
    print_uart("a=");
    print_uart_hex(a);
    print_uart("\r\n");
    bench_done("power_virus", t1 - t0);
    for (;;) {}
    return 0;
}
