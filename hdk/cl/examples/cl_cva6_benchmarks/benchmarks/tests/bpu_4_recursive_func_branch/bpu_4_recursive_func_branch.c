#include "bench.h"

static volatile uint64_t sink;

static uint64_t fib(uint64_t n)
{
    if (n < 2)
        return n;
    return fib(n - 1) + fib(n - 2);
}

static uint64_t kernel(void)
{
    return fib(18);
}


int main(void)
{
    bench_banner("bpu_4_recursive_func_branch");
    uint64_t t0 = rdcycle();
    sink = kernel();
    uint64_t t1 = rdcycle();
    print_uart("result=");
    print_uart_dec(sink);
    print_uart("\r\n");
    bench_done("bpu_4_recursive_func_branch", t1 - t0);
    for (;;) {}
    return 0;
}
