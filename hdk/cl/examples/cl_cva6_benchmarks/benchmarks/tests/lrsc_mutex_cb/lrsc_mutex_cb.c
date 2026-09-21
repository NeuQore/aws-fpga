#include "bench.h"

static volatile uint64_t lock;

static void acquire_backoff(void)
{
    uint64_t tmp, one = 1, spin;
    for (;;) {
        asm volatile(
            "lr.d %0, (%1)\n"
            "bnez %0, 1f\n"
            "sc.d %0, %2, (%1)\n"
            "1:"
            : "=&r"(tmp)
            : "r"(&lock), "r"(one)
            : "memory");
        if (tmp == 0)
            return;
        for (spin = 0; spin < 32; spin++)
            asm volatile("nop");
    }
}

static void release(void)
{
    asm volatile("sd zero, (%0)" :: "r"(&lock) : "memory");
}

int main(void)
{
    bench_banner("lrsc_mutex_cb");
    volatile uint64_t counter = 0;
    uint64_t t0 = rdcycle();
    for (uint64_t i = 0; i < 15000u; i++) {
        acquire_backoff();
        counter += 3;
        release();
    }
    uint64_t t1 = rdcycle();
    print_uart("counter=");
    print_uart_dec(counter);
    print_uart("\r\n");
    bench_done("lrsc_mutex_cb", t1 - t0);
    for (;;) {}
    return 0;
}
