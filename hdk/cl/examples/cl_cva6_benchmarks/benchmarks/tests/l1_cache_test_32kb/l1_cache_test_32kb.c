#include "bench.h"

#define BYTES (32u * 1024u)
static volatile uint8_t buf[BYTES];

int main(void)
{
    bench_banner("l1_cache_test_32kb");
    uint64_t t0 = rdcycle();
    for (uint32_t i = 0; i < BYTES; i++)
        buf[i] = (uint8_t)(i * 3u);
    volatile uint64_t sum = 0;
    for (uint32_t r = 0; r < 32u; r++)
        for (uint32_t i = 0; i < BYTES; i++)
            sum += buf[i];
    uint64_t t1 = rdcycle();
    print_uart("checksum=");
    print_uart_dec(sum);
    print_uart("\r\n");
    bench_done("l1_cache_test_32kb", t1 - t0);
    for (;;) {}
    return 0;
}
