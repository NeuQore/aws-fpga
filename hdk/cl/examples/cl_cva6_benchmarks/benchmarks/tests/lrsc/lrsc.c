#include "bench.h"

static volatile uint64_t lock_word;

static int cas(volatile uint64_t *p, uint64_t exp, uint64_t neu)
{
    uint64_t old;
    asm volatile(
        "1: lr.d %0, (%2)\n"
        "   bne  %0, %3, 2f\n"
        "   sc.d t0, %4, (%2)\n"
        "   bnez t0, 1b\n"
        "2:"
        : "=&r"(old)
        : "r"(p), "r"(p), "r"(exp), "r"(neu)
        : "t0", "memory");
    return old == exp;
}

int main(void)
{
    bench_banner("lrsc");
    lock_word = 0;
    uint64_t t0 = rdcycle();
    uint64_t ok = 0;
    for (uint64_t i = 0; i < 10000u; i++) {
        if (cas(&lock_word, i, i + 1))
            ok++;
    }
    uint64_t t1 = rdcycle();
    print_uart("cas_ok=");
    print_uart_dec(ok);
    print_uart(" word=");
    print_uart_dec(lock_word);
    print_uart("\r\n");
    bench_done("lrsc", t1 - t0);
    for (;;) {}
    return 0;
}
