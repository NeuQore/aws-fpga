#include "bench.h"

static volatile uint64_t sink;

static uint64_t f0(uint64_t x) { return x + 1; }
static uint64_t f1(uint64_t x) { return x ^ 0x9e3779b97f4a7c15ull; }
static uint64_t f2(uint64_t x) { return x * 3u + 1; }
static uint64_t f3(uint64_t x) { return x - (x >> 2); }

static uint64_t kernel(void)
{
    uint64_t (*fn[4])(uint64_t) = {f0, f1, f2, f3};
    volatile uint64_t acc = 1;
    for (uint64_t i = 0; i < 80000u; i++)
        acc = fn[i & 3](acc);
    return acc;
}


int main(void)
{
    bench_banner("bpu_5_indirect_branch");
    uint64_t t0 = rdcycle();
    sink = kernel();
    uint64_t t1 = rdcycle();
    print_uart("result=");
    print_uart_dec(sink);
    print_uart("\r\n");
    bench_done("bpu_5_indirect_branch", t1 - t0);
    for (;;) {}
    return 0;
}
