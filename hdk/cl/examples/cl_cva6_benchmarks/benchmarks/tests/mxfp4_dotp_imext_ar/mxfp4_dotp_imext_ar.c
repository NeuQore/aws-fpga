#include "bench.h"

int main(void)
{
    bench_skip("mxfp4_dotp_imext_ar", "needs SLE IMEXT; not in this CVA6 FPGA config");
    for (;;) {}
    return 0;
}
