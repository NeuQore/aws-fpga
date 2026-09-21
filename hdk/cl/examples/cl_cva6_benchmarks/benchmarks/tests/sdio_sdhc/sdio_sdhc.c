#include "bench.h"

int main(void)
{
    bench_skip("sdio_sdhc", "no SDIO in cl_cva6_linux shell/CL");
    for (;;) {}
    return 0;
}
