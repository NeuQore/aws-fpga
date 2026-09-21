#include "bench.h"

static volatile uint64_t sink;

static uint64_t walk(uint64_t n, uint64_t acc)
{
    if (n == 0)
        return acc;
    return walk(n - 1, acc + n);
}

static uint64_t kernel(void)
{
    volatile uint64_t s = 0;
    for (uint64_t i = 0; i < 4000u; i++)
        s += walk(24, i);
    return s;
}


int main(void)
{
    bench_banner("bpu_6_recursive_func_branch");
    uint64_t t0 = rdcycle();
    sink = kernel();
    uint64_t t1 = rdcycle();
    print_uart("result=");
    print_uart_dec(sink);
    print_uart("\r\n");
    bench_done("bpu_6_recursive_func_branch", t1 - t0);
    for (;;) {}
    return 0;
}
