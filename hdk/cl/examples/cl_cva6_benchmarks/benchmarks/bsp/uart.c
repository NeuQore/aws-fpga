#include "uart.h"

static void write_reg_u8(uintptr_t addr, uint8_t value)
{
    *(volatile uint8_t *)addr = value;
}

static uint8_t read_reg_u8(uintptr_t addr)
{
    return *(volatile uint8_t *)addr;
}

int is_transmit_empty(void)
{
    return read_reg_u8(UART_LSR) & 0x20;
}

void write_serial(char a)
{
    while (is_transmit_empty() == 0) {
    }
    write_reg_u8(UART_THR, (uint8_t)a);
}

void init_uart(uint32_t freq, uint32_t baud)
{
    uint32_t divisor = freq / (baud << 4);
    write_reg_u8(UART_IER, 0x00);
    write_reg_u8(UART_LCR, 0x80);
    write_reg_u8(UART_DLL, (uint8_t)divisor);
    write_reg_u8(UART_DLM, (uint8_t)((divisor >> 8) & 0xff));
    write_reg_u8(UART_LCR, 0x03);
    write_reg_u8(UART_FCR, 0xC7);
    write_reg_u8(UART_MCR, 0x20);
}

void print_uart(const char *str)
{
    while (*str)
        write_serial(*str++);
}

void print_uart_dec(uint64_t n)
{
    char buf[24];
    int i = 0;
    if (n == 0) {
        write_serial('0');
        return;
    }
    while (n) {
        buf[i++] = (char)('0' + (n % 10));
        n /= 10;
    }
    while (i--)
        write_serial(buf[i]);
}

void print_uart_hex(uint64_t v)
{
    static const char hex[] = "0123456789ABCDEF";
    write_serial('0');
    write_serial('x');
    for (int i = 15; i >= 0; i--)
        write_serial(hex[(v >> (i * 4)) & 0xf]);
}

void print_uart_int(uint32_t v)
{
    print_uart_hex(v);
}
