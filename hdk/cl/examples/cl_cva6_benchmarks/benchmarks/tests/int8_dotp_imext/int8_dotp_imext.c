#include "bench.h"

int main(void)
{
    bench_skip("int8_dotp_imext", "needs SLE IMEXT; not in this CVA6 FPGA config");
    for (;;) {}
    return 0;
}
