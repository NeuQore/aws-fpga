#include "bench.h"

#define CLINT_MSIP 0x02000000ULL

int main(void)
{
    bench_banner("ipi");
    uint64_t t0 = rdcycle();
    volatile uint32_t *msip = (volatile uint32_t *)CLINT_MSIP;
    *msip = 1;
    uint32_t seen = *msip;
    *msip = 0;
    uint64_t t1 = rdcycle();
    print_uart("msip_seen=");
    print_uart_dec(seen);
    print_uart("\r\n");
    bench_done("ipi", t1 - t0);
    for (;;) {}
    return 0;
}
