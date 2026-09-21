#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

#include "fpga_pci.h"
#include "fpga_mgmt.h"
#include "utils/lcd.h"

#include "cl_cva6_linux_def.h"

static const struct logger *logger = &logger_stdout;

static void usage(const char *name)
{
    printf("usage: %s [--slot N] [--bin PATH] [--verify] [--uart-idle-ms N]\n", name);
}

// #region agent log
static void dbg_status(const char *hyp, const char *msg, uint32_t status, int extra)
{
    printf("STATUS 0x%08x grant=%u hbm=%u uart_cnt=%u uart_valid=%u (%s)\n",
           status,
           !!(status & CL_CVA6_STATUS_CPU_GRANT),
           !!(status & CL_CVA6_STATUS_HBM_READY),
           (status >> 8) & 0xff,
           !!(status & CL_CVA6_STATUS_UART_VALID),
           msg);
    FILE *df = fopen("/projects/prj1/sle-wajahat/.cursor/debug-76b74b.log", "a");
    if (!df)
        return;
    fprintf(df,
            "{\"sessionId\":\"76b74b\",\"hypothesisId\":\"%s\",\"location\":\"hello_cva6_linux.c\","
            "\"message\":\"%s\",\"data\":{\"status\":%u,\"grant\":%u,\"hbm\":%u,"
            "\"uart_cnt\":%u,\"uart_valid\":%u,\"extra\":%d},"
            "\"timestamp\":%ld,\"runId\":\"linux-boot\"}\n",
            hyp, msg, status,
            !!(status & CL_CVA6_STATUS_CPU_GRANT),
            !!(status & CL_CVA6_STATUS_HBM_READY),
            (status >> 8) & 0xff,
            !!(status & CL_CVA6_STATUS_UART_VALID), extra,
            (long)time(NULL) * 1000);
    fclose(df);
}
// #endregion

static char uart_cap[96];
static int uart_cap_n;

static int drain_uart(pci_bar_handle_t bar, int idle_limit, int echo)
{
    int idle = 0;
    int count = 0;

    while (idle < idle_limit) {
        uint32_t status = 0;
        if (fpga_pci_peek(bar, CL_CVA6_STATUS, &status))
            return -1;
        if (status & CL_CVA6_STATUS_UART_VALID) {
            uint32_t ch = 0;
            if (fpga_pci_peek(bar, CL_CVA6_UART_RX, &ch))
                return -1;
            if (echo) {
                putchar((int)(ch & 0xff));
                fflush(stdout);
            }
            if (uart_cap_n < (int)sizeof(uart_cap) - 1)
                uart_cap[uart_cap_n++] = (char)(ch & 0xff);
            count++;
            idle = 0;
        } else {
            usleep(1000);
            idle++;
            // #region agent log
            if (idle == 1 || (idle % 5000) == 0)
                dbg_status("C", "drain_idle", status, count);
            // #endregion
        }
    }
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
    int verify = 0;
    int uart_idle_ms = 8000;
    const char *bin_path = "../firmware/hello_world.bin";
    pci_bar_handle_t bar0 = PCI_BAR_HANDLE_INIT;
    pci_bar_handle_t bar4 = PCI_BAR_HANDLE_INIT;
    uint32_t magic = 0;

    for (int i = 1; i < argc; i++) {
        if (!strncmp(argv[i], "--slot", 6) && i + 1 < argc)
            slot_id = atoi(argv[++i]);
        else if (!strncmp(argv[i], "--bin", 5) && i + 1 < argc)
            bin_path = argv[++i];
        else if (!strcmp(argv[i], "--verify"))
            verify = 1;
        else if (!strcmp(argv[i], "--uart-idle-ms") && i + 1 < argc)
            uart_idle_ms = atoi(argv[++i]);
        else {
            usage(argv[0]);
            return 1;
        }
    }

    rc = log_init("hello_cva6_linux");
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
        printf("Unexpected MAGIC 0x%08x (want 0x%08x). Is cl_cva6_linux loaded?\n",
               magic, CL_CVA6_MAGIC_VAL);
        rc = 1;
        goto out;
    }
    printf("cl_cva6_linux MAGIC ok\n");

    rc = fpga_pci_poke(bar0, CL_CVA6_CTRL, 0);
    fail_on(rc, out, "hold reset");

    rc = wait_hbm_ready(bar0);
    fail_on(rc, out, "HBM ready");
    printf("HBM ready\n");

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

    printf("Loading %ld bytes from %s via AppPF BAR4 @ 0x%llx\n",
           sz, bin_path, (unsigned long long)CL_PCIS_HBM_BASE);
    rc = load_bar4(bar4, buf, padded);
    fail_on(rc, out, "BAR4 burst write");
    uint32_t expect_word = 0;
    memcpy(&expect_word, buf, sizeof(expect_word));
    free(buf);
    buf = NULL;

    {
        uint32_t got_word = 0;
        int peek_rc = fpga_pci_peek(bar4, CL_PCIS_HBM_BASE, &got_word);
        printf("HBM[0] peek rc=%d val=0x%08x expect=0x%08x\n",
               peek_rc, got_word, expect_word);
        // #region agent log
        FILE *df = fopen("/projects/prj1/sle-wajahat/.cursor/debug-76b74b.log", "a");
        if (df) {
            fprintf(df,
                    "{\"sessionId\":\"76b74b\",\"hypothesisId\":\"D\",\"location\":\"hello_cva6_linux.c\","
                    "\"message\":\"hbm0_peek\",\"data\":{\"rc\":%d,\"got\":%u,\"expect\":%u},"
                    "\"timestamp\":%ld,\"runId\":\"linux-boot\"}\n",
                    peek_rc, got_word, expect_word, (long)time(NULL) * 1000);
            fclose(df);
        }
        // #endregion
    }

    if (verify) {
        int stale = drain_uart(bar0, 200, 0);
        rc = (stale < 0);
        fail_on(rc, out, "flush stale UART bytes");
        printf("Flushed %d stale UART byte(s)\n", stale);

        printf("--- phase A: image loaded, core STILL HELD IN RESET ---\n");
        int quiet = drain_uart(bar0, 2000, 1);
        rc = (quiet < 0);
        fail_on(rc, out, "phase A drain");
        printf("phase A bytes: %d  ->  %s\n", quiet,
               quiet == 0 ? "PASS (silent)"
                          : "FAIL (UART traffic without an executing core)");
    }

    printf("Releasing CVA6 reset\n");
    rc = fpga_pci_poke(bar0, CL_CVA6_CTRL, 1);
    fail_on(rc, out, "run");
    usleep(20000);
    {
        uint32_t status = 0;
        if (fpga_pci_peek(bar0, CL_CVA6_STATUS, &status) == 0)
            dbg_status("B", "after_cpu_run", status, 0);
    }

    printf("--- UART from CVA6 ---\n");
    int got = drain_uart(bar0, verify ? 2000 : uart_idle_ms, 1);
    rc = (got < 0);
    fail_on(rc, out, "uart drain");
    printf("\n--- done, %d byte(s) ---\n", got);
    // #region agent log
    {
        FILE *df = fopen("/projects/prj1/sle-wajahat/.cursor/debug-76b74b.log", "a");
        if (df) {
            int i;
            fprintf(df,
                    "{\"sessionId\":\"76b74b\",\"hypothesisId\":\"E\",\"location\":\"hello_cva6_linux.c\","
                    "\"message\":\"uart_done\",\"data\":{\"bytes\":%d,\"prefix\":\"",
                    got);
            uart_cap[uart_cap_n] = 0;
            for (i = 0; i < uart_cap_n; i++) {
                unsigned char c = (unsigned char)uart_cap[i];
                if (c == '"' || c == '\\')
                    fputc('\\', df);
                if (c >= 32 && c < 127)
                    fputc(c, df);
                else
                    fprintf(df, "\\u%04x", c);
            }
            fprintf(df, "\"},\"timestamp\":%ld,\"runId\":\"post-fix\"}\n",
                    (long)time(NULL) * 1000);
            fclose(df);
        }
    }
    // #endregion

    if (verify)
        printf("phase B bytes: %d  ->  %s\n", got,
               got > 0 ? "PASS (traffic appeared only after reset release)"
                       : "FAIL (no UART traffic from the core)");

out:
    if (bar4 != PCI_BAR_HANDLE_INIT)
        fpga_pci_detach(bar4);
    if (bar0 != PCI_BAR_HANDLE_INIT)
        fpga_pci_detach(bar0);
    return rc;
}
