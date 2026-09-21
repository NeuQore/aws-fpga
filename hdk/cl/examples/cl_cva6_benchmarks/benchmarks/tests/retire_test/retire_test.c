#include "bench.h"

int main(void)
{
    bench_banner("retire_test");
    uint64_t t0 = rdcycle();
    volatile uint64_t acc = 0;
    for (uint64_t i = 0; i < 300000u; i++) {
        acc += 1;
        acc ^= i;
        acc += (acc << 1);
    }
    uint64_t t1 = rdcycle();
    print_uart("retired_ops_proxy=");
    print_uart_dec(acc);
    print_uart("\r\n");
    bench_done("retire_test", t1 - t0);
    for (;;) {}
    return 0;
}
