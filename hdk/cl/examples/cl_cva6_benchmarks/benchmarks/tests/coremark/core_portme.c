#include "coremark.h"
#include "uart.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

#define GETMYTIME(_t) (*_t = ({ uint64_t _c; asm volatile("rdcycle %0" : "=r"(_c)); _c; }))
#define MYTIMEDIFF(fin, ini) ((fin) - (ini))
#define EE_TICKS_PER_SEC     62500000u

static CORETIMETYPE start_time_val, stop_time_val;

void start_time(void) { GETMYTIME(&start_time_val); }
void stop_time(void) { GETMYTIME(&stop_time_val); }

CORE_TICKS get_time(void)
{
    return (CORE_TICKS)(MYTIMEDIFF(stop_time_val, start_time_val));
}

secs_ret time_in_secs(CORE_TICKS ticks)
{
    return ((secs_ret)ticks) / (secs_ret)EE_TICKS_PER_SEC;
}

ee_u32 default_num_contexts = 1;

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    init_uart(CPU_FREQ_HZ, UART_BAUD);
    print_uart("\r\n=== START coremark ===\r\n");
    if (sizeof(ee_ptr_int) != sizeof(ee_u8 *))
        ee_printf("ERROR! ee_ptr_int size\n");
    if (sizeof(ee_u32) != 4)
        ee_printf("ERROR! ee_u32 size\n");
    p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
    print_uart("=== STOP coremark ===\r\n");
    p->portable_id = 0;
    for (;;) {
    }
}
