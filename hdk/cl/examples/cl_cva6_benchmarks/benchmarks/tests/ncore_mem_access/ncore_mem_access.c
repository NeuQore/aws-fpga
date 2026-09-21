#include "bench.h"

#define REGIONS 4
#define STRIDE  64
#define WORDS   1024
static volatile uint64_t region[REGIONS][WORDS];

int main(void)
{
    bench_banner("ncore_mem_access");
    uint64_t t0 = rdcycle();
    volatile uint64_t sum = 0;
    for (uint32_t r = 0; r < 16u; r++) {
        for (uint32_t g = 0; g < REGIONS; g++)
            for (uint32_t i = 0; i < WORDS; i += STRIDE / 8)
                region[g][i] = (uint64_t)r + g + i;
        for (uint32_t g = 0; g < REGIONS; g++)
            for (uint32_t i = 0; i < WORDS; i += STRIDE / 8)
                sum += region[g][i];
    }
    uint64_t t1 = rdcycle();
    print_uart("sum=");
    print_uart_dec(sum);
    print_uart("\r\n");
    bench_done("ncore_mem_access", t1 - t0);
    for (;;) {}
    return 0;
}
