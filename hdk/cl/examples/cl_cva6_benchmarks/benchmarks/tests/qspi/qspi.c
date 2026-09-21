#include "bench.h"

int main(void)
{
    bench_skip("qspi", "no QSPI in cl_cva6_linux shell/CL");
    for (;;) {}
    return 0;
}
