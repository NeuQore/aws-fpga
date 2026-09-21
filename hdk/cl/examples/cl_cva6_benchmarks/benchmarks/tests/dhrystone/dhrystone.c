#include "bench.h"

/* Compact original integer mix inspired by Dhrystone (not Weicker's source). */
#define LOOPS 20000u

static char s1[32] = "DHRYSTONE_CVA6_F2";
static char s2[32];

static int copy_str(char *d, const char *s)
{
    int n = 0;
    while ((*d++ = *s++))
        n++;
    return n;
}

static int cmp_str(const char *a, const char *b)
{
    while (*a && *a == *b) {
        a++;
        b++;
    }
    return (unsigned char)*a - (unsigned char)*b;
}

static uint64_t proc(uint64_t x, uint64_t y)
{
    uint64_t t = x + y;
    if (t & 1)
        t = (t << 1) ^ y;
    else
        t = (t >> 1) + x;
    return t;
}

int main(void)
{
    bench_banner("dhrystone");
    volatile uint64_t acc = 1;
    uint64_t t0 = rdcycle();
    for (uint64_t i = 0; i < LOOPS; i++) {
        acc = proc(acc, i);
        copy_str(s2, s1);
        if (cmp_str(s1, s2) != 0)
            acc ^= 1;
        acc += (uint64_t)s2[i & 15];
    }
    uint64_t t1 = rdcycle();
    print_uart("acc=");
    print_uart_dec(acc);
    print_uart(" dhrystones=");
    print_uart_dec(LOOPS);
    print_uart("\r\n");
    bench_done("dhrystone", t1 - t0);
    for (;;) {
    }
    return 0;
}
