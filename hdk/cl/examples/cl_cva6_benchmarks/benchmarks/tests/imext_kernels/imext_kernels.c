#include "bench.h"

int main(void)
{
    bench_skip("imext_kernels", "needs SLE IMEXT; not in this CVA6 FPGA config");
    for (;;) {}
    return 0;
}
