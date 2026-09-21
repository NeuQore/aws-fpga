#include "bench.h"

/* Small original HMM-style scoring kernel (not SPEC CPU hmmer). */
static int8_t seq[256];
static int8_t prof[32];

int main(void)
{
    bench_banner("hmmer");
    for (int i = 0; i < 256; i++)
        seq[i] = (int8_t)((i * 17) & 31);
    for (int i = 0; i < 32; i++)
        prof[i] = (int8_t)(i - 16);
    uint64_t t0 = rdcycle();
    volatile int32_t best = -100000;
    for (int r = 0; r < 64; r++) {
        for (int i = 0; i < 256 - 32; i++) {
            int32_t s = 0;
            for (int k = 0; k < 32; k++)
                s += (int32_t)seq[i + k] * (int32_t)prof[k];
            if (s > best)
                best = s;
        }
    }
    uint64_t t1 = rdcycle();
    print_uart("best=");
    print_uart_dec((uint64_t)best);
    print_uart("\r\n");
    bench_done("hmmer", t1 - t0);
    for (;;) {}
    return 0;
}
