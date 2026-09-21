#pragma once

#include <stdint.h>

#define UART_BASE 0x10000000ULL
#define UART_THR  (UART_BASE + 0)
#define UART_IER  (UART_BASE + 4)
#define UART_FCR  (UART_BASE + 8)
#define UART_LCR  (UART_BASE + 12)
#define UART_MCR  (UART_BASE + 16)
#define UART_LSR  (UART_BASE + 20)
#define UART_DLL  (UART_BASE + 0)
#define UART_DLM  (UART_BASE + 4)

#define CPU_FREQ_HZ 62500000u
#define UART_BAUD   115200u

void init_uart(uint32_t freq, uint32_t baud);
void write_serial(char a);
void print_uart(const char *str);
void print_uart_dec(uint64_t n);
void print_uart_hex(uint64_t v);
void print_uart_int(uint32_t v);
