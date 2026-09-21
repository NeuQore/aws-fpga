#include "bench.h"

static volatile uint64_t sink;

static uint64_t rec(uint64_t n)
{
    if (n < 2) return n;
    return rec(n - 1) + (n & 1);
}

static uint64_t kernel(void)
{
    volatile uint64_t acc = 0;
    for (uint64_t i = 0; i < 40000u; i++) {
        if (i & 1)
            acc += i;
        else
            acc ^= rec(8);
        acc += (i % 7 == 0);
    }
    return acc;
}


int main(void)
{
    bench_banner("bpu_combined");
    uint64_t t0 = rdcycle();
    sink = kernel();
    uint64_t t1 = rdcycle();
    print_uart("result=");
    print_uart_dec(sink);
    print_uart("\r\n");
    bench_done("bpu_combined", t1 - t0);
    for (;;) {}
    return 0;
}
