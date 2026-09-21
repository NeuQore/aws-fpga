#pragma once

#include "uart.h"

static inline uint64_t rdcycle(void)
{
    uint64_t x;
    asm volatile("rdcycle %0" : "=r"(x));
    return x;
}

static inline void bench_banner(const char *name)
{
    init_uart(CPU_FREQ_HZ, UART_BAUD);
    print_uart("\r\n=== START ");
    print_uart(name);
    print_uart(" ===\r\n");
}

static inline void bench_done(const char *name, uint64_t cycles)
{
    print_uart("=== STOP ");
    print_uart(name);
    print_uart(" cycles=");
    print_uart_dec(cycles);
    print_uart(" ===\r\n");
}

static inline void bench_skip(const char *name, const char *why)
{
    init_uart(CPU_FREQ_HZ, UART_BAUD);
    print_uart("=== SKIP ");
    print_uart(name);
    print_uart(" : ");
    print_uart(why);
    print_uart(" ===\r\n");
}
