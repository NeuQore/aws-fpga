#include "bench.h"

static volatile uint64_t sink;

static uint64_t kernel(void)
{
    volatile uint64_t acc = 1;
    for (uint64_t i = 0; i < 100000u; i++) {
        acc = acc * 1664525u + 1013904223u;
        if ((acc & 0x7u) == 0)
            acc ^= i;
    }
    return acc;
}


int main(void)
{
    bench_banner("bpu_3_loop_branch_regdep");
    uint64_t t0 = rdcycle();
    sink = kernel();
    uint64_t t1 = rdcycle();
    print_uart("result=");
    print_uart_dec(sink);
    print_uart("\r\n");
    bench_done("bpu_3_loop_branch_regdep", t1 - t0);
    for (;;) {}
    return 0;
}
