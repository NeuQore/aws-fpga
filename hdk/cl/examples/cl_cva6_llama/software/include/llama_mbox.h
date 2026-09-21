#pragma once
#include <stdint.h>

/* HBM mailbox between host BAR4 and CVA6. Lives in the 1 MiB gap between
 * heap_end (0xBFE00000) and stack (0xBFF00000). This AGFI's UART is TX-only
 * and PCIS cannot write HBM while cpu_run=1, so the host holds CVA6 in reset,
 * writes this page, then releases reset for each prompt. */
#define LLAMA_MBOX_MAGIC   0x314C4D50u /* 'PML1' */
#define LLAMA_MBOX_CVA6    0xBFE80000ULL
#define LLAMA_MBOX_TEXT    2048u
#define LLAMA_MBOX_NPRED_D 32u

struct llama_mbox {
    uint32_t magic;
    uint32_t n_predict;
    uint32_t len;
    uint32_t seq;
    char     text[LLAMA_MBOX_TEXT];
};
