#pragma once

#define CL_CVA6_CTRL      0x00
#define CL_CVA6_STATUS    0x04
#define CL_CVA6_UART_RX   0x08
#define CL_CVA6_MAGIC     0x0C
#define CL_CVA6_MEM_ADDR  0x10
#define CL_CVA6_MEM_WDATA 0x14
#define CL_CVA6_MEM_RDATA 0x18
#define CL_CVA6_MEM_CMD   0x1C

#define CL_CVA6_MAGIC_VAL 0xC6A66401u
#define CL_CVA6_MEM_WRITE 1u
#define CL_CVA6_MEM_READ  2u

#define CL_CVA6_STATUS_UART_VALID (1u << 0)
#define CL_CVA6_STATUS_HBM_READY  (1u << 16)
#define CL_CVA6_STATUS_CPU_GRANT  (1u << 17)

/* AppPF BAR4 / PCIS window used by cl_dram_hbm_dma for HBM. */
#define CL_PCIS_HBM_BASE   0x0000001000000000ULL
#define CL_CVA6_DRAM_BYTES (1ULL << 30)
