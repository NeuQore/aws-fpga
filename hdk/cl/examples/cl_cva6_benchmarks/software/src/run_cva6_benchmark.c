#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <time.h>

#include "fpga_pci.h"
#include "fpga_mgmt.h"
#include "utils/lcd.h"

#include "cl_cva6_linux_def.h"

static const struct logger *logger = &logger_stdout;

static void usage(const char *name)
{
    printf("usage: %s --bin PATH [--slot N] [--uart-idle-ms N] [--uart-max-ms N] [--log FILE]\n",
           name);
}

static FILE *uart_log;

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

static int drain_uart(pci_bar_handle_t bar, int idle_limit, int max_ms, int echo)
{
    int idle = 0;
    int elapsed = 0;
    int count = 0;
    int saw_end = 0;
    char tail[193];
    int tlen = 0;
    const int post_end_idle = 400;

    memset(tail, 0, sizeof(tail));

    while (elapsed < max_ms) {
        uint32_t status = 0;
        if (fpga_pci_peek(bar, CL_CVA6_STATUS, &status))
            return -1;
        if (status & CL_CVA6_STATUS_UART_VALID) {
            uint32_t ch = 0;
            int c;
            if (fpga_pci_peek(bar, CL_CVA6_UART_RX, &ch))
                return -1;
            c = (int)(ch & 0xff);
            if (echo)
                log_ch(c);
            count++;
            idle = 0;
            if (tlen < 192) {
                tail[tlen++] = (char)c;
                tail[tlen] = 0;
            } else {
                memmove(tail, tail + 1, 191);
                tail[191] = (char)c;
                tail[192] = 0;
            }
            if (strstr(tail, "=== STOP") || strstr(tail, "TRAP "))
                saw_end = 1;
        } else {
            usleep(1000);
            idle++;
            elapsed++;
            if (saw_end && idle >= post_end_idle)
                break;
            if (!saw_end && idle >= idle_limit)
                break;
        }
    }
    if (echo)
        fflush(stdout);
    if (uart_log)
        fflush(uart_log);
    // #region agent log
    {
        FILE *df = fopen("/projects/prj1/sle-wajahat/.cursor/debug-c93dda.log", "a");
        if (df) {
            long long ts = (long long)time(NULL) * 1000;
            const char *hyp = strstr(tail, "TRAP") ? "A" : "C";
            fprintf(df,
                "{\"sessionId\":\"c93dda\",\"timestamp\":%lld,\"location\":\"run_cva6_benchmark.c:drain_uart\",\"message\":\"uart_done\",\"data\":{\"bytes\":%d,\"saw_end\":%d,\"tail\":\"",
                ts, count, saw_end);
            for (int i = 0; tail[i]; i++) {
                unsigned char c = (unsigned char)tail[i];
                if (c < 32 || c == '"' || c == '\\')
                    fputc('.', df);
                else
                    fputc(c, df);
            }
            fprintf(df, "\"},\"runId\":\"run1\",\"hypothesisId\":\"%s\"}\n", hyp);
            fclose(df);
        }
    }
    // #endregion
    return count;
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

static int load_bar4(pci_bar_handle_t bar4, const uint8_t *buf, size_t nbytes)
{
    const size_t chunk_bytes = 4096;
    size_t off = 0;

    while (off < nbytes) {
        size_t n = nbytes - off;
        if (n > chunk_bytes)
            n = chunk_bytes;
        if (n % 4)
            return -1;
        int rc = fpga_pci_write_burst(bar4, CL_PCIS_HBM_BASE + off,
                                      (uint32_t *)(buf + off), n / 4);
        if (rc)
            return rc;
        off += n;
    }
    return 0;
}

int main(int argc, char **argv)
{
    int rc;
    int slot_id = 0;
    int uart_idle_ms = 120000;
    int uart_max_ms = 300000;
    const char *bin_path = NULL;
    const char *log_path = NULL;
    pci_bar_handle_t bar0 = PCI_BAR_HANDLE_INIT;
    pci_bar_handle_t bar4 = PCI_BAR_HANDLE_INIT;
    uint32_t magic = 0;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--slot") && i + 1 < argc)
            slot_id = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--bin") && i + 1 < argc)
            bin_path = argv[++i];
        else if (!strcmp(argv[i], "--uart-idle-ms") && i + 1 < argc)
            uart_idle_ms = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--uart-max-ms") && i + 1 < argc)
            uart_max_ms = atoi(argv[++i]);
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
    if (log_path) {
        uart_log = fopen(log_path, "w");
        fail_on(!uart_log, out, "open log %s", log_path);
    }

    rc = log_init("run_cva6_benchmark");
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
        log_msg("Unexpected MAGIC 0x%08x (want 0x%08x). Load cl_cva6_linux AGFI first.\n",
               magic, CL_CVA6_MAGIC_VAL);
        rc = 1;
        goto out;
    }
    log_msg("cl_cva6_linux MAGIC ok (same AGFI as cl_cva6_linux)\n");

    rc = fpga_pci_poke(bar0, CL_CVA6_CTRL, 0);
    fail_on(rc, out, "hold reset");

    rc = wait_hbm_ready(bar0);
    fail_on(rc, out, "HBM ready");
    log_msg("HBM ready\n");

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
    uint8_t *buf = calloc(1, padded);
    fail_on(!buf, out, "calloc");
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
        fclose(f);
        rc = 1;
        goto out;
    }
    fclose(f);

    rc = fpga_pci_attach(slot_id, FPGA_APP_PF, APP_PF_BAR4, BURST_CAPABLE, &bar4);
    fail_on(rc, out, "fpga_pci_attach BAR4");

    log_msg("Loading %ld bytes from %s via AppPF BAR4 @ 0x%llx\n",
           sz, bin_path, (unsigned long long)CL_PCIS_HBM_BASE);
    rc = load_bar4(bar4, buf, padded);
    fail_on(rc, out, "BAR4 burst write");
    free(buf);
    buf = NULL;

    (void)drain_uart(bar0, 200, 1000, 0);

    log_msg("Releasing CVA6 reset\n");
    rc = fpga_pci_poke(bar0, CL_CVA6_CTRL, 1);
    fail_on(rc, out, "run");

    log_msg("--- UART from CVA6 ---\n");
    int got = drain_uart(bar0, uart_idle_ms, uart_max_ms, 1);
    rc = (got < 0);
    fail_on(rc, out, "uart drain");
    log_msg("\n--- done, %d byte(s) ---\n", got);

out:
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
