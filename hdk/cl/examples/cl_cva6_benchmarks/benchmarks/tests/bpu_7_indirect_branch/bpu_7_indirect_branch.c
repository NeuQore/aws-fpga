#include "bench.h"

static volatile uint64_t sink;

static uint64_t kernel(void)
{
    static void *table[] = {&&L0, &&L1, &&L2, &&L3};
    volatile uint64_t acc = 0;
    uint64_t i = 0;
    goto *table[0];
L0:
    acc += 1;
    if (++i >= 100000u) goto done;
    goto *table[i & 3];
L1:
    acc ^= i;
    if (++i >= 100000u) goto done;
    goto *table[i & 3];
L2:
    acc += i * 3;
    if (++i >= 100000u) goto done;
    goto *table[i & 3];
L3:
    acc -= 1;
    if (++i >= 100000u) goto done;
    goto *table[i & 3];
done:
    return acc;
}


int main(void)
{
    bench_banner("bpu_7_indirect_branch");
    uint64_t t0 = rdcycle();
    sink = kernel();
    uint64_t t1 = rdcycle();
    print_uart("result=");
    print_uart_dec(sink);
    print_uart("\r\n");
    bench_done("bpu_7_indirect_branch", t1 - t0);
    for (;;) {}
    return 0;
}
