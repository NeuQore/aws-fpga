#include "bench.h"

static volatile uint64_t sink;

static uint64_t kernel(void)
{
    volatile uint64_t acc = 0;
    for (uint64_t i = 0; i < 200000u; i++)
        acc += i;
    return acc;
}


int main(void)
{
    bench_banner("bpu_1_loop_branch");
    uint64_t t0 = rdcycle();
    sink = kernel();
    uint64_t t1 = rdcycle();
    print_uart("result=");
    print_uart_dec(sink);
    print_uart("\r\n");
    bench_done("bpu_1_loop_branch", t1 - t0);
    for (;;) {}
    return 0;
}
