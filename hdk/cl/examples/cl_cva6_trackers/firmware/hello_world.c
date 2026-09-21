#include "uart.h"

int main(void)
{
    init_uart(62500000, 115200);
    print_uart("Hello World!\r\n");
    while (1) {
        ;
    }
    return 0;
}
