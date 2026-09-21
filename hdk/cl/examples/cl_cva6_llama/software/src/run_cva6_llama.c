#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <stdarg.h>
#include <time.h>

#include "fpga_pci.h"
#include "fpga_mgmt.h"
#include "utils/lcd.h"

#include "cl_cva6_linux_def.h"
#include "llama_mbox.h"

static const struct logger *logger = &logger_stdout;

static FILE *uart_log;
static uint32_t n_predict_default = LLAMA_MBOX_NPRED_D;
static uint32_t prompt_seq;
static unsigned dbg_seen;
static uint8_t *img_buf;
static size_t img_padded;
static int hb_quiet;

#define LLAMA_MBOX_PCIS (CL_PCIS_HBM_BASE + (LLAMA_MBOX_CVA6 - 0x80000000ULL))

static const char *ascii_logo =
    "\n"
    "llama.cpp  —  CVA6 on AWS F2  (same AGFI as cl_cva6_linux)\n"
    "\n"
    "     /\\_____/\\\n"
    "    /  o   o  \\\n"
    "   ( ==  ^  == )\n"
    "    )         (\n"
    "   (           )\n"
    "    \\  ||__||  /\n"
    "     \\________/\n"
    "\n"
    "Type a prompt and press Enter.  /bye  or Ctrl-D to quit.\n"
    "UART is CVA6→host only; each prompt is written to an HBM mailbox\n"
    "while CVA6 is held in reset (same AGFI, no host UART RX).\n"
    "\n";

static void usage(const char *name)
{
    printf("usage: %s --bin PATH [--slot N] [--n N] [--log FILE]\n", name);
}

static void log_ch(int c)
{
    putchar(c);
    if (uart_log)
        fputc(c, uart_log);
}

static void log_msg(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    if (uart_log) {
        va_start(ap, fmt);
        vfprintf(uart_log, fmt, ap);
        va_end(ap);
        fflush(uart_log);
    }
}

static int uart_byte(pci_bar_handle_t bar, int *out)
{
    uint32_t status = 0;
    if (fpga_pci_peek(bar, CL_CVA6_STATUS, &status))
        return -1;
    if (!(status & CL_CVA6_STATUS_UART_VALID))
        return 0;
    uint32_t ch = 0;
    if (fpga_pci_peek(bar, CL_CVA6_UART_RX, &ch))
        return -1;
    *out = (int)(ch & 0xff);
    return 1;
}

/* Drain UART. Returns 1 if the tail contains a prompt marker. */
static int drain_uart(pci_bar_handle_t bar, int max_ms, int stop_on_prompt, int *saw_prompt)
{
    char tail[256];
    int tlen = 0;
    int idle = 0;
    int elapsed = 0;

    memset(tail, 0, sizeof(tail));
    if (saw_prompt)
        *saw_prompt = 0;

    while (elapsed < max_ms) {
        int c = 0;
        int n = uart_byte(bar, &c);
        if (n < 0)
            return -1;
        if (n == 1) {
            log_ch(c);
            idle = 0;
            if (tlen < (int)sizeof(tail) - 1) {
                tail[tlen++] = (char)c;
                tail[tlen] = 0;
            } else {
                memmove(tail, tail + 1, sizeof(tail) - 2);
                tail[sizeof(tail) - 2] = (char)c;
                tail[sizeof(tail) - 1] = 0;
            }
            // #region agent log
            {
                struct { unsigned bit; const char *hid; const char *needle; } marks[] = {
                    { 1u << 0, "A", "wrong shape" },
                    { 1u << 1, "A", "dims ok" },
                    { 1u << 2, "B", "weight_buft_supported: enter" },
                    { 1u << 3, "B", "weight_buft_supported: exit" },
                    { 1u << 4, "C", "selecting buft" },
                    { 1u << 5, "C", "buft ok" },
                    { 1u << 6, "D", "ctx ok" },
                    { 1u << 7, "E", "create_tensor: done" },
                    { 1u << 8, "F", "load done" },
                    { 1u << 9, "G", "generate begin" },
                    { 1u << 10, "G", "tokenize n_prompt" },
                    { 1u << 11, "H", "llama_init_from_model begin" },
                    { 1u << 12, "H", "llama_init_from_model ok" },
                    { 1u << 13, "I", "decode begin" },
                    { 1u << 14, "I", "generate done" },
                    { 1u << 15, "F", "mailbox magic" },
                };
                for (unsigned m = 0; m < sizeof(marks) / sizeof(marks[0]); m++) {
                    if ((dbg_seen & marks[m].bit) || !strstr(tail, marks[m].needle))
                        continue;
                    dbg_seen |= marks[m].bit;
                    FILE *df = fopen("/projects/prj1/sle-wajahat/.cursor/debug-c93dda.log", "a");
                    if (!df)
                        continue;
                    fprintf(df,
                        "{\"sessionId\":\"c93dda\",\"hypothesisId\":\"%s\",\"location\":\"run_cva6_llama.c:drain_uart\",\"message\":\"uart_marker\",\"data\":{\"needle\":\"%s\",\"tail\":\"",
                        marks[m].hid, marks[m].needle);
                    for (int i = 0; tail[i]; i++) {
                        unsigned char u = (unsigned char)tail[i];
                        if (u < 32 || u == '"' || u == '\\')
                            fputc('.', df);
                        else
                            fputc((char)u, df);
                    }
                    fprintf(df, "\"},\"timestamp\":%ld}\n", (long)time(NULL) * 1000);
                    fclose(df);
                }
            }
            // #endregion
            if (strstr(tail, "decode begin") || strstr(tail, "generate done"))
                hb_quiet = 1;
            if (strstr(tail, ">>> ")) {
                if (saw_prompt)
                    *saw_prompt = 1;
                if (stop_on_prompt) {
                    fflush(stdout);
                    if (uart_log)
                        fflush(uart_log);
                    return 0;
                }
            }
        } else {
            usleep(1000);
            idle++;
            elapsed++;
            if ((elapsed % 10000) == 0 && !hb_quiet) {
                log_msg("\n[host] CVA6 still loading (%d s). Wait for 'load done'.\n",
                        elapsed / 1000);
            }
            if (stop_on_prompt && idle > 50 && saw_prompt && *saw_prompt)
                break;
        }
    }
    fflush(stdout);
    if (uart_log)
        fflush(uart_log);
    return 0;
}

static int wait_hbm_ready(pci_bar_handle_t bar)
{
    for (int i = 0; i < 10000; i++) {
        uint32_t status = 0;
        if (fpga_pci_peek(bar, CL_CVA6_STATUS, &status))
            return -1;
        if (status & CL_CVA6_STATUS_HBM_READY)
            return 0;
        usleep(1000);
    }
    fprintf(stderr, "Timeout waiting for HBM ready (STATUS bit 16)\n");
    return -1;
}

static int load_bar4(pci_bar_handle_t bar4, uint64_t addr, const uint8_t *buf, size_t nbytes)
{
    const size_t chunk_bytes = 4096;
    size_t off = 0;

    while (off < nbytes) {
        size_t n = nbytes - off;
        if (n > chunk_bytes)
            n = chunk_bytes;
        if (n % 4)
            return -1;
        int rc = fpga_pci_write_burst(bar4, addr + off, (uint32_t *)(buf + off), n / 4);
        if (rc)
            return rc;
        off += n;
    }
    return 0;
}

static int write_mbox(pci_bar_handle_t bar4, const char *prompt, uint32_t n_predict)
{
    struct llama_mbox box;
    memset(&box, 0, sizeof(box));
    box.magic = LLAMA_MBOX_MAGIC;
    box.n_predict = n_predict;
    box.seq = ++prompt_seq;
    size_t n = strlen(prompt);
    if (n >= LLAMA_MBOX_TEXT)
        n = LLAMA_MBOX_TEXT - 1;
    box.len = (uint32_t)n;
    memcpy(box.text, prompt, n);

    uint8_t pad[sizeof(box)];
    memset(pad, 0, sizeof(pad));
    memcpy(pad, &box, sizeof(box));
    size_t nbytes = (sizeof(pad) + 3) & ~3u;
    return load_bar4(bar4, LLAMA_MBOX_PCIS, pad, nbytes);
}

static int clear_mbox(pci_bar_handle_t bar4)
{
    uint8_t pad[(sizeof(struct llama_mbox) + 3) & ~3u];
    memset(pad, 0, sizeof(pad));
    return load_bar4(bar4, LLAMA_MBOX_PCIS, pad, sizeof(pad));
}

static int hold_and_poke_prompt(pci_bar_handle_t bar0, pci_bar_handle_t bar4, const char *prompt)
{
    int rc = fpga_pci_poke(bar0, CL_CVA6_CTRL, 0);
    if (rc)
        return rc;
    usleep(20000);
    for (int i = 0; i < 4096; i++) {
        int c = 0;
        int n = uart_byte(bar0, &c);
        if (n < 0)
            return -1;
        if (n == 0)
            break;
    }
    /* CRT only zeros .bss. First run mutates .data in HBM; rewrite the ELF. */
    if (img_buf && img_padded) {
        log_msg("[host] rewriting %zu-byte ELF so .data is clean...\n", img_padded);
        rc = load_bar4(bar4, CL_PCIS_HBM_BASE, img_buf, img_padded);
        if (rc)
            return rc;
    }
    rc = write_mbox(bar4, prompt, n_predict_default);
    if (rc)
        return rc;
    rc = fpga_pci_poke(bar0, CL_CVA6_CTRL, 1);
    return rc;
}

int main(int argc, char **argv)
{
    int rc;
    int slot_id = 0;
    const char *bin_path = NULL;
    const char *log_path = NULL;
    pci_bar_handle_t bar0 = PCI_BAR_HANDLE_INIT;
    pci_bar_handle_t bar4 = PCI_BAR_HANDLE_INIT;
    uint32_t magic = 0;
    uint8_t *buf = NULL;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--slot") && i + 1 < argc)
            slot_id = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--bin") && i + 1 < argc)
            bin_path = argv[++i];
        else if (!strcmp(argv[i], "--n") && i + 1 < argc)
            n_predict_default = (uint32_t)atoi(argv[++i]);
        else if (!strcmp(argv[i], "--log") && i + 1 < argc)
            log_path = argv[++i];
        else {
            usage(argv[0]);
            return 1;
        }
    }
    if (!bin_path) {
        usage(argv[0]);
        return 1;
    }
    if (n_predict_default < 1)
        n_predict_default = 1;
    if (n_predict_default > 128)
        n_predict_default = 128;

    if (log_path) {
        uart_log = fopen(log_path, "w");
        fail_on(!uart_log, out, "open log %s", log_path);
    }

    fputs(ascii_logo, stdout);
    fflush(stdout);

    rc = log_init("run_cva6_llama");
    fail_on(rc, out, "log_init");
    rc = log_attach(logger, NULL, 0);
    fail_on(rc, out, "log_attach");
    rc = fpga_mgmt_init();
    fail_on(rc, out, "fpga_mgmt_init");
    rc = fpga_pci_init();
    fail_on(rc, out, "fpga_pci_init");

    rc = fpga_pci_attach(slot_id, FPGA_APP_PF, APP_PF_BAR0, 0, &bar0);
    fail_on(rc, out, "fpga_pci_attach BAR0");

    rc = fpga_pci_peek(bar0, CL_CVA6_MAGIC, &magic);
    fail_on(rc, out, "peek MAGIC");
    if (magic != CL_CVA6_MAGIC_VAL) {
        log_msg("Unexpected MAGIC 0x%08x (want 0x%08x). Load AGFI agfi-0248c1f84010b03e9 first.\n",
                magic, CL_CVA6_MAGIC_VAL);
        rc = 1;
        goto out;
    }

    rc = fpga_pci_poke(bar0, CL_CVA6_CTRL, 0);
    fail_on(rc, out, "hold reset");
    rc = wait_hbm_ready(bar0);
    fail_on(rc, out, "HBM ready");

    FILE *f = fopen(bin_path, "rb");
    fail_on(!f, out, "open %s", bin_path);
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz < 0 || (unsigned long)sz > CL_CVA6_DRAM_BYTES) {
        fprintf(stderr, "Image is %ld bytes; DRAM window is %llu bytes.\n",
                sz, (unsigned long long)CL_CVA6_DRAM_BYTES);
        fclose(f);
        rc = 1;
        goto out;
    }
    size_t padded = (size_t)((sz + 3) & ~3L);
    buf = calloc(1, padded);
    fail_on(!buf, out, "calloc");
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
        fclose(f);
        rc = 1;
        goto out;
    }
    fclose(f);
    img_buf = buf;
    img_padded = padded;

    rc = fpga_pci_attach(slot_id, FPGA_APP_PF, APP_PF_BAR4, BURST_CAPABLE, &bar4);
    fail_on(rc, out, "fpga_pci_attach BAR4");

    log_msg("Loading %ld bytes from %s\n", sz, bin_path);
    rc = load_bar4(bar4, CL_PCIS_HBM_BASE, buf, padded);
    fail_on(rc, out, "BAR4 burst write");

    /* HBM mailbox survives ELF reload; leftover magic would auto-run the last prompt. */
    rc = clear_mbox(bar4);
    fail_on(rc, out, "clear mailbox");
    log_msg("Mailbox cleared (first boot waits for a prompt).\n");

    log_msg("CVA6 loading model (62.5 MHz; this can take a while)...\n");
    rc = fpga_pci_poke(bar0, CL_CVA6_CTRL, 1);
    fail_on(rc, out, "run");

    int saw = 0;
    rc = drain_uart(bar0, 600000, 1, &saw);
    fail_on(rc, out, "uart drain");
    if (!saw)
        log_msg("\n(no prompt marker yet — type anyway after the model finishes loading)\n");
    else
        log_msg("\n[host] waiting for a prompt (or /bye).\n");

    char line[LLAMA_MBOX_TEXT];
    for (;;) {
        struct pollfd p = { .fd = STDIN_FILENO, .events = POLLIN };
        int pr = poll(&p, 1, 20);
        if (pr < 0) {
            if (errno == EINTR)
                continue;
            rc = 1;
            break;
        }
        drain_uart(bar0, 5, 0, NULL);

        if (pr == 0)
            continue;
        if (!fgets(line, sizeof(line), stdin))
            break;
        size_t n = strlen(line);
        while (n && (line[n - 1] == '\n' || line[n - 1] == '\r'))
            line[--n] = 0;
        if (!n)
            continue;
        if (!strcmp(line, "/bye") || !strcmp(line, "/quit") || !strcmp(line, "/exit"))
            break;

        log_msg("\n[host] sending prompt to CVA6 (reset + mailbox)...\n");
        log_msg("[host] CVA6 must reload the model after reset; wait for 'load done' then generate (several minutes at 62.5 MHz).\n");
        dbg_seen = 0;
        hb_quiet = 0;
        rc = hold_and_poke_prompt(bar0, bar4, line);
        fail_on(rc, out, "inject prompt");
        saw = 0;
        rc = drain_uart(bar0, 600000, 1, &saw);
        fail_on(rc, out, "uart drain");
        log_msg("\n[host] waiting for a prompt (or /bye).\n");
    }

    log_msg("\n--- session end ---\n");
    rc = 0;

out:
    free(buf);
    if (uart_log) {
        fclose(uart_log);
        uart_log = NULL;
    }
    if (bar4 != PCI_BAR_HANDLE_INIT)
        fpga_pci_detach(bar4);
    if (bar0 != PCI_BAR_HANDLE_INIT)
        fpga_pci_detach(bar0);
    return rc;
}
