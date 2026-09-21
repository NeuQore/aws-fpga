#include "bench.h"

static volatile uint64_t sink;

static uint64_t kernel(void)
{
    volatile uint64_t acc = 0;
    for (uint64_t a = 16; a > 0; a--)
        for (uint64_t b = 16; b > 0; b--)
            for (uint64_t c = 16; c > 0; c--)
                for (uint64_t d = 16; d > 0; d--)
                    acc += a * b + c * d;
    return acc;
}


int main(void)
{
    bench_banner("bpu_8_nested_4loop_desc");
    uint64_t t0 = rdcycle();
    sink = kernel();
    uint64_t t1 = rdcycle();
    print_uart("result=");
    print_uart_dec(sink);
    print_uart("\r\n");
    bench_done("bpu_8_nested_4loop_desc", t1 - t0);
    for (;;) {}
    return 0;
}
