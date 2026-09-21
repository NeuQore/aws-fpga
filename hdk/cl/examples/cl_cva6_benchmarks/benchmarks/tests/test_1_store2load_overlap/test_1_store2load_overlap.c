#include "bench.h"

#define N 4096
static volatile uint64_t arr[N];

int main(void)
{
    bench_banner("test_1_store2load_overlap");
    uint64_t t0 = rdcycle();
    volatile uint64_t sum = 0;
    for (uint32_t r = 0; r < 64u; r++) {
        for (uint32_t i = 0; i < N; i++)
            arr[i] = i + r;
        for (uint32_t i = 0; i < N; i += 1)
            sum += arr[i];
    }
    uint64_t t1 = rdcycle();
    print_uart("sum=");
    print_uart_dec(sum);
    print_uart(" stride=1\r\n");
    bench_done("test_1_store2load_overlap", t1 - t0);
    for (;;) {}
    return 0;
}
