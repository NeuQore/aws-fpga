#include "bench.h"

int main(void)
{
    const uint32_t bauds[] = {9600, 38400, 115200, 230400};
    for (unsigned i = 0; i < 4; i++) {
        init_uart(CPU_FREQ_HZ, bauds[i]);
        print_uart("uart_baud=");
        print_uart_dec(bauds[i]);
        print_uart("\r\n");
    }
    init_uart(CPU_FREQ_HZ, UART_BAUD);
    bench_done("uart_baud", 0);
    for (;;) {}
    return 0;
}
