#include "bench.h"

/* Tiny original amplitude-iteration kernel (not SPEC libquantum). */
#define N 64
static volatile double re[N], im[N];

int main(void)
{
    bench_banner("libquantum");
    for (int i = 0; i < N; i++) {
        re[i] = 1.0 / (double)N;
        im[i] = 0.0;
    }
    uint64_t t0 = rdcycle();
    for (int step = 0; step < 128; step++) {
        for (int i = 0; i < N; i++) {
            int j = i ^ 1;
            double a = re[i] + re[j];
            double b = im[i] - im[j];
            re[i] = a * 0.70710678118;
            im[i] = b * 0.70710678118;
        }
    }
    volatile double nrm = 0;
    for (int i = 0; i < N; i++)
        nrm += re[i] * re[i] + im[i] * im[i];
    uint64_t t1 = rdcycle();
    print_uart("norm_bits=");
    print_uart_dec((uint64_t)(nrm * 1000.0));
    print_uart("\r\n");
    bench_done("libquantum", t1 - t0);
    for (;;) {}
    return 0;
}
