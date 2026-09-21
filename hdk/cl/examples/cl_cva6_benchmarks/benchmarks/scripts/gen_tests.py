#!/usr/bin/env python3
"""Emit bare-metal RISC-V tests for cl_cva6_benchmarks / sle-benchmarks."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"

MK = """NAME := {name}
SRCS := {name}.c
include ../../bsp/common.mk
"""

def write_test(name, body):
    d = TESTS / name
    d.mkdir(parents=True, exist_ok=True)
    (d / f"{name}.c").write_text(body)
    (d / "Makefile").write_text(MK.format(name=name))


def bpu(name, kernel, iters="200000u"):
    return f'''#include "bench.h"

static volatile uint64_t sink;

{kernel}

int main(void)
{{
    bench_banner("{name}");
    uint64_t t0 = rdcycle();
    sink = kernel();
    uint64_t t1 = rdcycle();
    print_uart("result=");
    print_uart_dec(sink);
    print_uart("\\r\\n");
    bench_done("{name}", t1 - t0);
    for (;;) {{}}
    return 0;
}}
'''


write_test(
    "bpu_1_loop_branch",
    bpu(
        "bpu_1_loop_branch",
        """static uint64_t kernel(void)
{
    volatile uint64_t acc = 0;
    for (uint64_t i = 0; i < 200000u; i++)
        acc += i;
    return acc;
}
""",
    ),
)

write_test(
    "bpu_2_loop_branch",
    bpu(
        "bpu_2_loop_branch",
        """static uint64_t kernel(void)
{
    volatile uint64_t acc = 1;
    for (uint64_t i = 1; i < 150000u; i++)
        acc = acc + (i ^ (acc >> 3));
    return acc;
}
""",
    ),
)

write_test(
    "bpu_2_toggle_branch",
    bpu(
        "bpu_2_toggle_branch",
        """static uint64_t kernel(void)
{
    volatile uint64_t acc = 0;
    for (uint64_t i = 0; i < 200000u; i++) {
        if (i & 1u)
            acc += i;
        else
            acc -= 1;
    }
    return acc;
}
""",
    ),
)

write_test(
    "bpu_3_loop_branch",
    bpu(
        "bpu_3_loop_branch",
        """static uint64_t kernel(void)
{
    volatile uint64_t acc = 0;
    for (uint64_t i = 0; i < 64u; i++)
        for (uint64_t j = 0; j < 2048u; j++)
            acc += i + j;
    return acc;
}
""",
    ),
)

write_test(
    "bpu_3_loop_branch_regdep",
    bpu(
        "bpu_3_loop_branch_regdep",
        """static uint64_t kernel(void)
{
    volatile uint64_t acc = 1;
    for (uint64_t i = 0; i < 100000u; i++) {
        acc = acc * 1664525u + 1013904223u;
        if ((acc & 0x7u) == 0)
            acc ^= i;
    }
    return acc;
}
""",
    ),
)

write_test(
    "bpu_4_recursive_func_branch",
    bpu(
        "bpu_4_recursive_func_branch",
        """static uint64_t fib(uint64_t n)
{
    if (n < 2)
        return n;
    return fib(n - 1) + fib(n - 2);
}

static uint64_t kernel(void)
{
    return fib(18);
}
""",
    ),
)

write_test(
    "bpu_5_indirect_branch",
    bpu(
        "bpu_5_indirect_branch",
        """static uint64_t f0(uint64_t x) { return x + 1; }
static uint64_t f1(uint64_t x) { return x ^ 0x9e3779b97f4a7c15ull; }
static uint64_t f2(uint64_t x) { return x * 3u + 1; }
static uint64_t f3(uint64_t x) { return x - (x >> 2); }

static uint64_t kernel(void)
{
    uint64_t (*fn[4])(uint64_t) = {f0, f1, f2, f3};
    volatile uint64_t acc = 1;
    for (uint64_t i = 0; i < 80000u; i++)
        acc = fn[i & 3](acc);
    return acc;
}
""",
    ),
)

write_test(
    "bpu_6_recursive_func_branch",
    bpu(
        "bpu_6_recursive_func_branch",
        """static uint64_t walk(uint64_t n, uint64_t acc)
{
    if (n == 0)
        return acc;
    return walk(n - 1, acc + n);
}

static uint64_t kernel(void)
{
    volatile uint64_t s = 0;
    for (uint64_t i = 0; i < 4000u; i++)
        s += walk(24, i);
    return s;
}
""",
    ),
)

write_test(
    "bpu_7_indirect_branch",
    bpu(
        "bpu_7_indirect_branch",
        """static uint64_t kernel(void)
{
    static void *table[] = {&&L0, &&L1, &&L2, &&L3};
    volatile uint64_t acc = 0;
    uint64_t i = 0;
    goto *table[0];
L0:
    acc += 1;
    if (++i >= 100000u) goto done;
    goto *table[i & 3];
L1:
    acc ^= i;
    if (++i >= 100000u) goto done;
    goto *table[i & 3];
L2:
    acc += i * 3;
    if (++i >= 100000u) goto done;
    goto *table[i & 3];
L3:
    acc -= 1;
    if (++i >= 100000u) goto done;
    goto *table[i & 3];
done:
    return acc;
}
""",
    ),
)

write_test(
    "bpu_8_nested_4loop_asc",
    bpu(
        "bpu_8_nested_4loop_asc",
        """static uint64_t kernel(void)
{
    volatile uint64_t acc = 0;
    for (uint64_t a = 0; a < 16; a++)
        for (uint64_t b = 0; b < 16; b++)
            for (uint64_t c = 0; c < 16; c++)
                for (uint64_t d = 0; d < 16; d++)
                    acc += a + b + c + d;
    return acc;
}
""",
    ),
)

write_test(
    "bpu_8_nested_4loop_desc",
    bpu(
        "bpu_8_nested_4loop_desc",
        """static uint64_t kernel(void)
{
    volatile uint64_t acc = 0;
    for (uint64_t a = 16; a > 0; a--)
        for (uint64_t b = 16; b > 0; b--)
            for (uint64_t c = 16; c > 0; c--)
                for (uint64_t d = 16; d > 0; d--)
                    acc += a * b + c * d;
    return acc;
}
""",
    ),
)

write_test(
    "bpu_combined",
    bpu(
        "bpu_combined",
        """static uint64_t rec(uint64_t n)
{
    if (n < 2) return n;
    return rec(n - 1) + (n & 1);
}

static uint64_t kernel(void)
{
    volatile uint64_t acc = 0;
    for (uint64_t i = 0; i < 40000u; i++) {
        if (i & 1)
            acc += i;
        else
            acc ^= rec(8);
        acc += (i % 7 == 0);
    }
    return acc;
}
""",
    ),
)

write_test(
    "retire_test",
    '''#include "bench.h"

int main(void)
{
    bench_banner("retire_test");
    uint64_t t0 = rdcycle();
    volatile uint64_t acc = 0;
    for (uint64_t i = 0; i < 300000u; i++) {
        acc += 1;
        acc ^= i;
        acc += (acc << 1);
    }
    uint64_t t1 = rdcycle();
    print_uart("retired_ops_proxy=");
    print_uart_dec(acc);
    print_uart("\\r\\n");
    bench_done("retire_test", t1 - t0);
    for (;;) {}
    return 0;
}
''',
)

write_test(
    "l1_cache_test_32kb",
    '''#include "bench.h"

#define BYTES (32u * 1024u)
static volatile uint8_t buf[BYTES];

int main(void)
{
    bench_banner("l1_cache_test_32kb");
    uint64_t t0 = rdcycle();
    for (uint32_t i = 0; i < BYTES; i++)
        buf[i] = (uint8_t)(i * 3u);
    volatile uint64_t sum = 0;
    for (uint32_t r = 0; r < 32u; r++)
        for (uint32_t i = 0; i < BYTES; i++)
            sum += buf[i];
    uint64_t t1 = rdcycle();
    print_uart("checksum=");
    print_uart_dec(sum);
    print_uart("\\r\\n");
    bench_done("l1_cache_test_32kb", t1 - t0);
    for (;;) {}
    return 0;
}
''',
)

write_test(
    "lrsc",
    '''#include "bench.h"

static volatile uint64_t lock_word;

static int cas(volatile uint64_t *p, uint64_t exp, uint64_t neu)
{
    uint64_t old;
    asm volatile(
        "1: lr.d %0, (%2)\\n"
        "   bne  %0, %3, 2f\\n"
        "   sc.d t0, %4, (%2)\\n"
        "   bnez t0, 1b\\n"
        "2:"
        : "=&r"(old)
        : "r"(p), "r"(p), "r"(exp), "r"(neu)
        : "t0", "memory");
    return old == exp;
}

int main(void)
{
    bench_banner("lrsc");
    lock_word = 0;
    uint64_t t0 = rdcycle();
    uint64_t ok = 0;
    for (uint64_t i = 0; i < 10000u; i++) {
        if (cas(&lock_word, i, i + 1))
            ok++;
    }
    uint64_t t1 = rdcycle();
    print_uart("cas_ok=");
    print_uart_dec(ok);
    print_uart(" word=");
    print_uart_dec(lock_word);
    print_uart("\\r\\n");
    bench_done("lrsc", t1 - t0);
    for (;;) {}
    return 0;
}
''',
)

write_test(
    "lrsc_mutex",
    '''#include "bench.h"

static volatile uint64_t lock;

static void acquire(void)
{
    uint64_t tmp, one = 1;
    asm volatile(
        "1: lr.d %0, (%1)\\n"
        "   bnez %0, 1b\\n"
        "   sc.d %0, %2, (%1)\\n"
        "   bnez %0, 1b\\n"
        : "=&r"(tmp)
        : "r"(&lock), "r"(one)
        : "memory");
}

static void release(void)
{
    asm volatile("sd zero, (%0)" :: "r"(&lock) : "memory");
}

int main(void)
{
    bench_banner("lrsc_mutex");
    volatile uint64_t counter = 0;
    uint64_t t0 = rdcycle();
    for (uint64_t i = 0; i < 20000u; i++) {
        acquire();
        counter++;
        release();
    }
    uint64_t t1 = rdcycle();
    print_uart("counter=");
    print_uart_dec(counter);
    print_uart("\\r\\n");
    bench_done("lrsc_mutex", t1 - t0);
    for (;;) {}
    return 0;
}
''',
)

write_test(
    "lrsc_mutex_cb",
    '''#include "bench.h"

static volatile uint64_t lock;

static void acquire_backoff(void)
{
    uint64_t tmp, one = 1, spin;
    for (;;) {
        asm volatile(
            "lr.d %0, (%1)\\n"
            "bnez %0, 1f\\n"
            "sc.d %0, %2, (%1)\\n"
            "1:"
            : "=&r"(tmp)
            : "r"(&lock), "r"(one)
            : "memory");
        if (tmp == 0)
            return;
        for (spin = 0; spin < 32; spin++)
            asm volatile("nop");
    }
}

static void release(void)
{
    asm volatile("sd zero, (%0)" :: "r"(&lock) : "memory");
}

int main(void)
{
    bench_banner("lrsc_mutex_cb");
    volatile uint64_t counter = 0;
    uint64_t t0 = rdcycle();
    for (uint64_t i = 0; i < 15000u; i++) {
        acquire_backoff();
        counter += 3;
        release();
    }
    uint64_t t1 = rdcycle();
    print_uart("counter=");
    print_uart_dec(counter);
    print_uart("\\r\\n");
    bench_done("lrsc_mutex_cb", t1 - t0);
    for (;;) {}
    return 0;
}
''',
)

for i, stride in enumerate((1, 8, 64, 256), start=1):
    write_test(
        f"test_{i}_store2load_overlap",
        f'''#include "bench.h"

#define N 4096
static volatile uint64_t arr[N];

int main(void)
{{
    bench_banner("test_{i}_store2load_overlap");
    uint64_t t0 = rdcycle();
    volatile uint64_t sum = 0;
    for (uint32_t r = 0; r < 64u; r++) {{
        for (uint32_t i = 0; i < N; i++)
            arr[i] = i + r;
        for (uint32_t i = 0; i < N; i += {stride})
            sum += arr[i];
    }}
    uint64_t t1 = rdcycle();
    print_uart("sum=");
    print_uart_dec(sum);
    print_uart(" stride={stride}\\r\\n");
    bench_done("test_{i}_store2load_overlap", t1 - t0);
    for (;;) {{}}
    return 0;
}}
''',
    )

write_test(
    "power_virus",
    '''#include "bench.h"

int main(void)
{
    bench_banner("power_virus");
    uint64_t t0 = rdcycle();
    volatile uint64_t a = 0x0123456789abcdefull;
    volatile uint64_t b = 0xfedcba9876543210ull;
    volatile double f = 1.1;
    for (uint64_t i = 0; i < 200000u; i++) {
        a = a * 6364136223846793005ull + 1;
        b ^= (a << 7) | (a >> 3);
        f = f * 1.0000001 + (double)(a & 0xff);
        a += (uint64_t)f;
    }
    uint64_t t1 = rdcycle();
    print_uart("a=");
    print_uart_hex(a);
    print_uart("\\r\\n");
    bench_done("power_virus", t1 - t0);
    for (;;) {}
    return 0;
}
''',
)

write_test(
    "ipi",
    '''#include "bench.h"

#define CLINT_MSIP 0x02000000ULL

int main(void)
{
    bench_banner("ipi");
    uint64_t t0 = rdcycle();
    volatile uint32_t *msip = (volatile uint32_t *)CLINT_MSIP;
    *msip = 1;
    uint32_t seen = *msip;
    *msip = 0;
    uint64_t t1 = rdcycle();
    print_uart("msip_seen=");
    print_uart_dec(seen);
    print_uart("\\r\\n");
    bench_done("ipi", t1 - t0);
    for (;;) {}
    return 0;
}
''',
)

write_test(
    "uart_baud",
    '''#include "bench.h"

int main(void)
{
    const uint32_t bauds[] = {9600, 38400, 115200, 230400};
    for (unsigned i = 0; i < 4; i++) {
        init_uart(CPU_FREQ_HZ, bauds[i]);
        print_uart("uart_baud=");
        print_uart_dec(bauds[i]);
        print_uart("\\r\\n");
    }
    init_uart(CPU_FREQ_HZ, UART_BAUD);
    bench_done("uart_baud", 0);
    for (;;) {}
    return 0;
}
''',
)

write_test(
    "ncore_mem_access",
    '''#include "bench.h"

#define REGIONS 4
#define STRIDE  64
#define WORDS   1024
static volatile uint64_t region[REGIONS][WORDS];

int main(void)
{
    bench_banner("ncore_mem_access");
    uint64_t t0 = rdcycle();
    volatile uint64_t sum = 0;
    for (uint32_t r = 0; r < 16u; r++) {
        for (uint32_t g = 0; g < REGIONS; g++)
            for (uint32_t i = 0; i < WORDS; i += STRIDE / 8)
                region[g][i] = (uint64_t)r + g + i;
        for (uint32_t g = 0; g < REGIONS; g++)
            for (uint32_t i = 0; i < WORDS; i += STRIDE / 8)
                sum += region[g][i];
    }
    uint64_t t1 = rdcycle();
    print_uart("sum=");
    print_uart_dec(sum);
    print_uart("\\r\\n");
    bench_done("ncore_mem_access", t1 - t0);
    for (;;) {}
    return 0;
}
''',
)

write_test(
    "hmmer",
    '''#include "bench.h"

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
    print_uart("\\r\\n");
    bench_done("hmmer", t1 - t0);
    for (;;) {}
    return 0;
}
''',
)

write_test(
    "libquantum",
    '''#include "bench.h"

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
    print_uart("\\r\\n");
    bench_done("libquantum", t1 - t0);
    for (;;) {}
    return 0;
}
''',
)

write_test(
    "mcf",
    '''#include "bench.h"

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
    print_uart("\\r\\n");
    bench_done("mcf", t1 - t0);
    for (;;) {}
    return 0;
}
''',
)

SKIP = [
    ("fp16_dotp_rvv", "needs RVV; cv64a6_imafdc_sv39 has no V"),
    ("int8_dotp_rvv", "needs RVV; cv64a6_imafdc_sv39 has no V"),
    ("int8_dotp_imext", "needs SLE IMEXT; not in this CVA6 FPGA config"),
    ("mxfp4_dotp_imext_ar", "needs SLE IMEXT; not in this CVA6 FPGA config"),
    ("imext_kernels", "needs SLE IMEXT; not in this CVA6 FPGA config"),
    ("qspi", "no QSPI in cl_cva6_linux shell/CL"),
    ("sdio_sdhc", "no SDIO in cl_cva6_linux shell/CL"),
]

for name, why in SKIP:
    write_test(
        name,
        f'''#include "bench.h"

int main(void)
{{
    bench_skip("{name}", "{why}");
    for (;;) {{}}
    return 0;
}}
''',
    )

print("wrote tests under", TESTS)
''