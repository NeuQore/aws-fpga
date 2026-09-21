#include "bench.h"

/* Tiny original min-cost-flow style relaxation (not SPEC mcf). */
#define N 64
static int cost[N][N];
static int dist[N];

int main(void)
{
    bench_banner("mcf");
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++)
            cost[i][j] = (int)(((i * 13 + j * 7) % 97) + 1);
    uint64_t t0 = rdcycle();
    for (int i = 0; i < N; i++)
        dist[i] = 1 << 20;
    dist[0] = 0;
    for (int k = 0; k < N - 1; k++)
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                if (dist[i] + cost[i][j] < dist[j])
                    dist[j] = dist[i] + cost[i][j];
    volatile int sum = 0;
    for (int i = 0; i < N; i++)
        sum += dist[i];
    uint64_t t1 = rdcycle();
    print_uart("dist_sum=");
    print_uart_dec((uint64_t)sum);
    print_uart("\r\n");
    bench_done("mcf", t1 - t0);
    for (;;) {}
    return 0;
}
