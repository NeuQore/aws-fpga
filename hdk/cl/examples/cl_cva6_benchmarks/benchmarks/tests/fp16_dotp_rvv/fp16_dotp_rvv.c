#include "bench.h"

int main(void)
{
    bench_skip("fp16_dotp_rvv", "needs RVV; cv64a6_imafdc_sv39 has no V");
    for (;;) {}
    return 0;
}
