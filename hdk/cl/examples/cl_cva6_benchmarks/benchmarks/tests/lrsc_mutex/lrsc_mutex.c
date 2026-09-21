#include "bench.h"

static volatile uint64_t lock;

static void acquire(void)
{
    uint64_t tmp, one = 1;
    asm volatile(
        "1: lr.d %0, (%1)\n"
        "   bnez %0, 1b\n"
        "   sc.d %0, %2, (%1)\n"
        "   bnez %0, 1b\n"
        : "=&r"(tmp)
        : "r"(&lock), "r"(one)
        : "memory");
}

static void release(void)
{
    asm volatile("sd zero, (%0)" :: "r"(&lock) : "memory");
}

int main(void)
{
    bench_banner("lrsc_mutex");
    volatile uint64_t counter = 0;
    uint64_t t0 = rdcycle();
    for (uint64_t i = 0; i < 20000u; i++) {
        acquire();
        counter++;
        release();
    }
    uint64_t t1 = rdcycle();
    print_uart("counter=");
    print_uart_dec(counter);
    print_uart("\r\n");
    bench_done("lrsc_mutex", t1 - t0);
    for (;;) {}
    return 0;
}
