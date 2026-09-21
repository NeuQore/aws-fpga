#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <inttypes.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#include <time.h>

#include "fpga_pci.h"
#include "fpga_mgmt.h"
#include "utils/lcd.h"

#include "cl_cva6_trackers_def.h"
#include "riscv_disasm.h"

static const struct logger *logger = &logger_stdout;
static FILE *uart_log;

static int mkdir_p(const char *path)
{
    char tmp[512];
    size_t n;
    char *p;

    if (!path || !path[0])
        return -1;
    n = strlen(path);
    if (n >= sizeof(tmp))
        return -1;
    memcpy(tmp, path, n + 1);
    if (tmp[n - 1] == '/')
        tmp[n - 1] = '\0';
    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, 0755) && errno != EEXIST)
                return -1;
            *p = '/';
        }
    }
    if (mkdir(tmp, 0755) && errno != EEXIST)
        return -1;
    return 0;
}

static void usage(const char *name)
{
    printf("usage: %s --bin PATH [--slot N] [--window-start N] [--window-end N]\n"
           "          [--trace-dir DIR] [--uart-idle-ms N] [--uart-max-ms N] [--log FILE]\n"
           "          [--stop-on-exception]\n"
           "\n"
           "CPU cycles are counted from cpu_run. instr/icache/dcache capture is\n"
           "[window-start, window-end). events.csv is always-on while tracing:\n"
           "traps, flushes, mispredicts (with live LSU VA/PA and CSRs).\n"
           "--stop-on-exception freezes the cycle window on the first trap.\n",
           name);
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

static int poke64(pci_bar_handle_t bar, uint64_t lo_off, uint64_t v)
{
    int rc = fpga_pci_poke(bar, lo_off, (uint32_t)v);
    if (rc)
        return rc;
    return fpga_pci_poke(bar, lo_off + 4, (uint32_t)(v >> 32));
}

static int peek64(pci_bar_handle_t bar, uint64_t lo_off, uint64_t *out)
{
    uint32_t lo = 0, hi = 0;
    int rc = fpga_pci_peek(bar, lo_off, &lo);
    if (rc)
        return rc;
    rc = fpga_pci_peek(bar, lo_off + 4, &hi);
    if (rc)
        return rc;
    *out = ((uint64_t)hi << 32) | lo;
    return 0;
}

static uint8_t *g_image;
static size_t g_image_len;

static const char *abi_reg_name(unsigned r)
{
    static const char *names[32] = {
        "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
        "fp", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
        "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
        "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
    };
    if (r < 32)
        return names[r];
    return NULL;
}

static void fmt_none(char *buf, size_t n)
{
    if (buf && n)
        snprintf(buf, n, "NONE");
}

static void fmt_reg_csv(char *buf, size_t n, int has, unsigned r)
{
    const char *abi;
    if (!has || !buf || n == 0) {
        fmt_none(buf, n);
        return;
    }
    abi = abi_reg_name(r);
    if (abi)
        snprintf(buf, n, "%s", abi);
    else
        snprintf(buf, n, "x%u", r);
}

static void fmt_hex_csv(char *buf, size_t n, int has, uint64_t v)
{
    if (!has || !buf || n == 0) {
        fmt_none(buf, n);
        return;
    }
    snprintf(buf, n, "%" PRIx64, v);
}

static void fmt_imm_csv(char *buf, size_t n, int has, int64_t imm)
{
    if (!has || !buf || n == 0) {
        fmt_none(buf, n);
        return;
    }
    if (imm < 0)
        snprintf(buf, n, "-%" PRIx64, (uint64_t)(-imm));
    else
        snprintf(buf, n, "%" PRIx64, (uint64_t)imm);
}

static const char *fu_op_name(unsigned op, unsigned rs1)
{
    /* Fallback only if the instruction bytes at PC cannot be fetched. */
    static const char *names[] = {
        "add", "sub", "addw", "subw", "xor", "or", "and",
        "sra", "srl", "sll", "srlw", "sllw", "sraw",
        "blt", "bltu", "bge", "bgeu", "beq", "bne",
        "jalr", "branch", "slt", "sltu",
        "mret", "sret", "dret", "ecall", "wfi", "fence", "fence.i",
        "sfence.vma", "hfence.vvma", "hfence.gvma",
        "csrw", "csrr", "csrs", "csrc",
        "ld", "sd", "lw", "lwu", "sw", "lh", "lhu", "sh", "lb", "sb", "lbu",
        "hlv.b", "hlv.bu", "hlv.h", "hlv.hu", "hlvx.hu", "hlv.w", "hlvx.wu",
        "hsv.b", "hsv.h", "hsv.w", "hlv.wu", "hlv.d", "hsv.d",
        "lr.w", "lr.d", "sc.w", "sc.d",
        "amoswap.w", "amoadd.w", "amoand.w", "amoor.w", "amoxor.w",
        "amomax.w", "amomaxu.w", "amomin.w", "amominu.w",
        "amoswap.d", "amoadd.d", "amoand.d", "amoor.d", "amoxor.d",
        "amomax.d", "amomaxu.d", "amomin.d", "amominu.d",
        "cbo.clean", "cbo.flush", "cbo.inval", "cbo.zero",
        "mul", "mulh", "mulhu", "mulhsu", "mulw",
        "div", "divu", "divw", "divuw", "rem", "remu", "remw", "remuw",
        "fld", "flw", "flh", "flb", "fsd", "fsw", "fsh", "fsb",
        "fadd", "fsub", "fmul", "fdiv", "fmin_max", "fsqrt",
        "fmadd", "fmsub", "fnmsub", "fnmadd",
        "fcvt.f2i", "fcvt.i2f", "fcvt.f2f", "fsgnj", "fmv.f2x", "fmv.x2f",
        "fcmp", "fclass"
    };
    if (op == 19 && rs1 == 0)
        return "jal";
    if (op < sizeof(names) / sizeof(names[0]))
        return names[op];
    return NULL;
}

static const char *priv_name(unsigned p)
{
    switch (p) {
    case 3: return "M_MODE";
    case 2: return "HS_MODE";
    case 1: return "S_MODE";
    default: return "U_MODE";
    }
}

static void fmt_cause(char *buf, size_t n, uint64_t cause, unsigned flags)
{
    unsigned irq = (flags >> 31) & 1;
    unsigned code = (flags >> 16) & 0xff;
    if (!irq && code == 0 && cause == 0) {
        snprintf(buf, n, "EXCP_NONE(0x0)");
        return;
    }
    snprintf(buf, n, "%s(0x%" PRIx64 ")", irq ? "INTERRUPT" : "EXCP", cause);
}

static const char *excp_name(uint64_t cause)
{
    unsigned irq = (unsigned)(cause >> 63);
    unsigned code = (unsigned)(cause & 0xff);
    if (irq) {
        switch (code) {
        case 1:  return "IRQ_S_SOFT";
        case 3:  return "IRQ_M_SOFT";
        case 5:  return "IRQ_S_TIMER";
        case 7:  return "IRQ_M_TIMER";
        case 9:  return "IRQ_S_EXT";
        case 11: return "IRQ_M_EXT";
        default: return "IRQ";
        }
    }
    switch (code) {
    case 0:  return "INSTR_ADDR_MISALIGNED";
    case 1:  return "INSTR_ACCESS_FAULT";
    case 2:  return "ILLEGAL_INSTR";
    case 3:  return "BREAKPOINT";
    case 4:  return "LD_ADDR_MISALIGNED";
    case 5:  return "LD_ACCESS_FAULT";
    case 6:  return "ST_ADDR_MISALIGNED";
    case 7:  return "ST_ACCESS_FAULT";
    case 8:  return "ECALL_U";
    case 9:  return "ECALL_S";
    case 11: return "ECALL_M";
    case 12: return "INSTR_PAGE_FAULT";
    case 13: return "LOAD_PAGE_FAULT";
    case 15: return "STORE_PAGE_FAULT";
    default: return "EXCP";
    }
}

static void fmt_event_kind(char *buf, size_t n, uint64_t flags)
{
    char tmp[48];
    tmp[0] = 0;
    if (flags & 1)
        strcat(tmp, "trap");
    if (flags & 2) {
        if (tmp[0])
            strcat(tmp, "|");
        strcat(tmp, "flush");
    }
    if (flags & 4) {
        if (tmp[0])
            strcat(tmp, "|");
        strcat(tmp, "misp");
    }
    if (flags & (1ULL << 44)) {
        if (tmp[0])
            strcat(tmp, "|");
        strcat(tmp, "icmiss");
    }
    if (flags & (1ULL << 45)) {
        if (tmp[0])
            strcat(tmp, "|");
        strcat(tmp, "dcmiss");
    }
    if (!tmp[0])
        snprintf(buf, n, "none");
    else
        snprintf(buf, n, "%s", tmp);
}

static const char *kind_name(unsigned k)
{
    switch (k) {
    case 0: return "AR";
    case 1: return "R";
    case 2: return "AW";
    case 3: return "W";
    case 4: return "B";
    case 5: return "LSU";
    case 6: return "L1I_MISS";
    case 7: return "L1D_MISS";
    default: return "UNK";
    }
}

static const char *axi_resp_name(unsigned r)
{
    switch (r) {
    case 0: return "OKAY";
    case 1: return "EXOKAY";
    case 2: return "SLVERR";
    case 3: return "DECERR";
    default: return "UNK";
    }
}

static void append_tok(char *buf, size_t n, const char *tok)
{
    size_t used;
    if (!buf || n == 0 || !tok || !tok[0])
        return;
    used = strlen(buf);
    if (used && used + 1 < n) {
        buf[used++] = ';';
        buf[used] = '\0';
    }
    if (used >= n)
        return;
    snprintf(buf + used, n - used, "%s", tok);
}

static void fmt_icache_beat(char *buf, size_t n, uint64_t data,
                            uint16_t *carry, int *has_carry, int last)
{
    uint8_t b[10];
    int nb = 0;
    int off = 0;

    if (!buf || n == 0)
        return;
    buf[0] = '\0';
    if (*has_carry) {
        b[nb++] = (uint8_t)*carry;
        b[nb++] = (uint8_t)(*carry >> 8);
    }
    for (int i = 0; i < 8; i++)
        b[nb++] = (uint8_t)(data >> (8 * i));
    *has_carry = 0;
    while (off + 1 < nb) {
        uint16_t lo = (uint16_t)b[off] | ((uint16_t)b[off + 1] << 8);
        char mnem[32];
        uint32_t insn;
        if ((lo & 3u) != 3u) {
            insn = lo;
            off += 2;
        } else if (off + 3 >= nb) {
            *carry = lo;
            *has_carry = 1;
            break;
        } else {
            insn = (uint32_t)lo |
                   ((uint32_t)b[off + 2] << 16) |
                   ((uint32_t)b[off + 3] << 24);
            off += 4;
        }
        if (riscv_disasm_mnemonic(insn, mnem, sizeof(mnem)) != 0)
            snprintf(mnem, sizeof(mnem), "unknown");
        append_tok(buf, n, mnem);
    }
    if (last && *has_carry) {
        append_tok(buf, n, "partial");
        *has_carry = 0;
    }
    if (!buf[0])
        fmt_none(buf, n);
}

static void fmt_dcache_ascii(char *buf, size_t n, uint64_t data,
                             unsigned strb, int use_strb)
{
    char ascii[9];
    int any = 0;
    for (int i = 0; i < 8; i++) {
        int live = !use_strb || ((strb >> i) & 1);
        uint8_t c = (uint8_t)(data >> (8 * i));
        if (live && c >= 32 && c < 127) {
            ascii[i] = (char)c;
            any = 1;
        } else {
            ascii[i] = live ? '.' : ' ';
        }
    }
    ascii[8] = '\0';
    if (any)
        snprintf(buf, n, "%s", ascii);
    else
        fmt_none(buf, n);
}

static int read_record(pci_bar_handle_t bar, unsigned sel, unsigned idx,
                       unsigned nwords, uint64_t *words)
{
    int rc;
    rc = fpga_pci_poke(bar, CL_CVA6_TRACE_SEL, sel);
    if (rc)
        return rc;
    rc = fpga_pci_poke(bar, CL_CVA6_TRACE_IDX, idx);
    if (rc)
        return rc;
    for (unsigned w = 0; w < nwords; w++) {
        rc = fpga_pci_poke(bar, CL_CVA6_TRACE_WORD, w);
        if (rc)
            return rc;
        rc = peek64(bar, CL_CVA6_TRACE_RDATA_LO, &words[w]);
        if (rc)
            return rc;
    }
    return 0;
}

static int dump_instr_csv(pci_bar_handle_t bar, const char *path, uint32_t count)
{
    FILE *f = fopen(path, "w");
    uint64_t w[CL_CVA6_INSTR_WORDS];
    unsigned decode_hits = 0, decode_miss = 0, watch_logged = 0;
    uint64_t gpr[32];
    uint8_t gpr_known[32];
    unsigned replay_known_reads = 0, replay_unknown_reads = 0;
    if (!f)
        return -1;
    memset(gpr, 0, sizeof(gpr));
    memset(gpr_known, 0, sizeof(gpr_known));
    gpr_known[0] = 1;
    fprintf(f, "cycle,pc,op,insn,trans_id,rs1,rs1_val,rs2,rs2_val,rd,imm,retire,excp,cause,priv_lvl,rd_valid,rd_wdata,minstret\n");
    for (uint32_t i = 0; i < count; i++) {
        char cause_buf[64];
        char op_buf[32];
        char rs1_buf[8], rs2_buf[8], rd_buf[8];
        char rs1v_buf[20], rs2v_buf[20], imm_buf[24];
        char mnem[32];
        const char *opn;
        unsigned flags, op, trans_id, rtl_rs1, rtl_rs2, rtl_rd, priv;
        uint32_t insn = 0;
        int compressed = 0;
        int fetched;
        riscv_operands_t ops;
        unsigned rs1, rs2, rd;
        int has_rs1, has_rs2, has_rd, has_imm;
        int rs1_known = 0, rs2_known = 0;
        uint64_t rs1_val = 0, rs2_val = 0;
        int rd_valid;
        if (read_record(bar, 0, i, CL_CVA6_INSTR_WORDS, w)) {
            fclose(f);
            return -1;
        }
        op       = (unsigned)((w[2] >> 32) & 0xff);
        trans_id = (unsigned)((w[2] >> 40) & 0xff);
        rtl_rs1  = (unsigned)((w[2] >> 56) & 0xff);
        rtl_rs2  = (unsigned)((w[2] >> 8) & 0xff);
        rtl_rd   = (unsigned)(w[2] & 0xff);
        flags    = (unsigned)w[3];
        priv     = (flags >> 9) & 3;
        rd_valid = (flags >> 4) & 1;
        memset(&ops, 0, sizeof(ops));
        fetched = riscv_fetch_insn(g_image, g_image_len, RISCV_IMAGE_BASE,
                                   w[1], &insn, &compressed);
        if (fetched == 0 && riscv_disasm_mnemonic(insn, mnem, sizeof(mnem)) == 0) {
            opn = mnem;
            decode_hits++;
        } else {
            opn = fu_op_name(op, rtl_rs1);
            decode_miss++;
        }
        if (opn)
            snprintf(op_buf, sizeof(op_buf), "%s", opn);
        else
            snprintf(op_buf, sizeof(op_buf), "OP_0x%02x", op);
        if (fetched == 0 && riscv_decode_operands(insn, &ops) == 0) {
            has_rs1 = ops.has_rs1;
            has_rs2 = ops.has_rs2;
            has_rd  = ops.has_rd;
            has_imm = ops.has_imm;
            rs1 = ops.rs1;
            rs2 = ops.rs2;
            rd  = ops.rd;
        } else {
            has_rs1 = 1;
            has_rs2 = (rtl_rs2 != 0);
            has_rd  = (rtl_rd != 0);
            has_imm = 0;
            rs1 = rtl_rs1;
            rs2 = rtl_rs2;
            rd  = rtl_rd;
        }
        if (has_rs1 && rs1 < 32 && gpr_known[rs1]) {
            rs1_known = 1;
            rs1_val = gpr[rs1];
            replay_known_reads++;
        } else if (has_rs1) {
            replay_unknown_reads++;
        }
        if (has_rs2 && rs2 < 32 && gpr_known[rs2]) {
            rs2_known = 1;
            rs2_val = gpr[rs2];
            replay_known_reads++;
        } else if (has_rs2) {
            replay_unknown_reads++;
        }
        fmt_reg_csv(rs1_buf, sizeof(rs1_buf), has_rs1, rs1);
        fmt_reg_csv(rs2_buf, sizeof(rs2_buf), has_rs2, rs2);
        fmt_reg_csv(rd_buf, sizeof(rd_buf), has_rd, rd);
        fmt_hex_csv(rs1v_buf, sizeof(rs1v_buf), rs1_known, rs1_val);
        fmt_hex_csv(rs2v_buf, sizeof(rs2v_buf), rs2_known, rs2_val);
        fmt_imm_csv(imm_buf, sizeof(imm_buf), has_imm, ops.imm);
        // #region agent log
        {
            uint64_t pc = w[1];
            const char *fu = fu_op_name(op, rtl_rs1);
            int watch = (pc == 0x80000000ULL || pc == 0x80000002ULL ||
                         pc == 0x8000000aULL || pc == 0x8000001eULL);
            if (watch && watch_logged < 4) {
                FILE *dbg = fopen("/projects/prj1/sle-wajahat/.cursor/debug-29681a.log", "a");
                if (dbg) {
                    fprintf(dbg,
                        "{\"sessionId\":\"29681a\",\"runId\":\"operands\",\"hypothesisId\":\"A\","
                        "\"location\":\"run_cva6_trackers.c:dump_instr_csv\","
                        "\"message\":\"operand decode + gpr replay\","
                        "\"data\":{\"pc\":\"%" PRIx64 "\",\"insn\":\"%x\",\"compressed\":%d,"
                        "\"fetched\":%d,\"printed\":\"%s\",\"fu_name\":\"%s\","
                        "\"rs1\":\"%s\",\"rs1_val\":\"%s\",\"rs2\":\"%s\",\"rs2_val\":\"%s\","
                        "\"rd\":\"%s\",\"imm\":\"%s\",\"rd_wdata\":\"%" PRIx64 "\","
                        "\"rtl_rs1\":%u,\"rtl_rs2\":%u,\"rtl_rd\":%u},"
                        "\"timestamp\":%lld}\n",
                        pc, insn, compressed, fetched, op_buf, fu ? fu : "",
                        rs1_buf, rs1v_buf, rs2_buf, rs2v_buf, rd_buf, imm_buf, w[4],
                        rtl_rs1, rtl_rs2, rtl_rd, (long long)time(NULL) * 1000);
                    fclose(dbg);
                    watch_logged++;
                }
            }
        }
        // #endregion
        fmt_cause(cause_buf, sizeof(cause_buf), w[10], flags);
        fprintf(f,
            "%" PRIu64 ",%" PRIx64 ",%s,%x,%u,%s,%s,%s,%s,%s,%s,%u,%u,%s,%s,%u,%" PRIx64 ",%" PRIu64 "\n",
            w[0], w[1], op_buf, insn, trans_id,
            rs1_buf, rs1v_buf, rs2_buf, rs2v_buf, rd_buf, imm_buf,
            (flags >> 3) & 1, (flags >> 1) & 1, cause_buf, priv_name(priv),
            rd_valid, w[4], w[13]);
        /* This AFI's w[2] low bits are not a reliable rd (rtl_rd is 0 on lui t0). */
        if (rd_valid) {
            unsigned dest = (has_rd && rd != 0) ? rd : rtl_rd;
            if (dest < 32 && dest != 0) {
                gpr[dest] = w[4];
                gpr_known[dest] = 1;
            }
        }
        gpr[0] = 0;
        gpr_known[0] = 1;
    }
    // #region agent log
    {
        FILE *dbg = fopen("/projects/prj1/sle-wajahat/.cursor/debug-29681a.log", "a");
        if (dbg) {
            fprintf(dbg,
                "{\"sessionId\":\"29681a\",\"runId\":\"operands\",\"hypothesisId\":\"D\","
                "\"location\":\"run_cva6_trackers.c:dump_instr_csv\","
                "\"message\":\"runtime decode coverage\","
                "\"data\":{\"rows\":%u,\"decode_hits\":%u,\"decode_miss\":%u,\"image_len\":%zu,"
                "\"replay_known_reads\":%u,\"replay_unknown_reads\":%u},"
                "\"timestamp\":%lld}\n",
                count, decode_hits, decode_miss, g_image_len,
                replay_known_reads, replay_unknown_reads,
                (long long)time(NULL) * 1000);
            fclose(dbg);
        }
    }
    // #endregion
    fclose(f);
    return 0;
}

static int dump_cache_csv(pci_bar_handle_t bar, unsigned sel, const char *path, uint32_t count)
{
    FILE *f = fopen(path, "w");
    uint64_t w[CL_CVA6_CACHE_WORDS];
    uint64_t ar_cyc[16] = {0}, aw_cyc[16] = {0};
    int r_beat[16] = {0}, w_beat[16] = {0};
    uint16_t ic_carry[16] = {0};
    int ic_has_carry[16] = {0};
    int is_icache = (sel == 1);
    unsigned watch_logged = 0;
    unsigned l1_kind_n = 0;
    if (!f)
        return -1;
    fprintf(f, "cycle,kind,va,line,pa,beat,data,decode,strb,bytes,resp,last,latency\n");
    for (uint32_t i = 0; i < count; i++) {
        unsigned flags, kind, id, strb, size, resp, last;
        unsigned bytes, beat = 0;
        int has_data, has_strb, has_resp, has_beat, has_lat;
        uint64_t line, pa, latency = 0;
        char data_buf[20], strb_buf[8], beat_buf[8], lat_buf[20];
        char pa_buf[20], va_buf[20], decode_buf[96], resp_buf[12];
        if (read_record(bar, sel, i, CL_CVA6_CACHE_WORDS, w)) {
            fclose(f);
            return -1;
        }
        flags = (unsigned)w[4];
        kind  = (flags >> 20) & 0xf;
        id    = (flags >> 4) & 0xf;
        strb  = (flags >> 8) & 0xff;
        size  = (flags >> 16) & 7;
        resp  = (flags >> 2) & 3;
        last  = (flags >> 1) & 1;
        bytes = 1u << size;
        line  = w[2];
        pa    = line;
        has_data = (kind == 1 || kind == 3);
        has_strb = (kind == 3);
        has_resp = (kind == 1 || kind == 4);
        has_beat = 0;
        has_lat  = 0;
        decode_buf[0] = '\0';
        if (kind == 0) { /* AR */
            r_beat[id] = 0;
            ar_cyc[id] = w[0];
            ic_has_carry[id] = 0;
            fmt_none(decode_buf, sizeof(decode_buf));
        } else if (kind == 1) { /* R */
            beat = (unsigned)r_beat[id]++;
            pa = line + (uint64_t)beat * bytes;
            has_beat = 1;
            if (ar_cyc[id]) {
                latency = w[0] - ar_cyc[id];
                has_lat = 1;
            }
            if (is_icache)
                fmt_icache_beat(decode_buf, sizeof(decode_buf), w[3],
                                &ic_carry[id], &ic_has_carry[id], last);
            else
                fmt_dcache_ascii(decode_buf, sizeof(decode_buf), w[3], strb, 0);
            if (last)
                r_beat[id] = 0;
        } else if (kind == 2) { /* AW */
            w_beat[id] = 0;
            aw_cyc[id] = w[0];
            fmt_none(decode_buf, sizeof(decode_buf));
        } else if (kind == 3) { /* W */
            beat = (unsigned)w_beat[id]++;
            pa = line + (uint64_t)beat * bytes;
            has_beat = 1;
            if (aw_cyc[id]) {
                latency = w[0] - aw_cyc[id];
                has_lat = 1;
            }
            fmt_dcache_ascii(decode_buf, sizeof(decode_buf), w[3], strb, 1);
            if (last)
                w_beat[id] = 0;
        } else if (kind == 4) { /* B */
            if (aw_cyc[id]) {
                latency = w[0] - aw_cyc[id];
                has_lat = 1;
            }
            fmt_none(decode_buf, sizeof(decode_buf));
        } else { /* L1I_MISS / L1D_MISS leftover from mixed-AXI AFIs */
            snprintf(decode_buf, sizeof(decode_buf), "miss");
            l1_kind_n++;
        }
        if (has_data)
            snprintf(data_buf, sizeof(data_buf), "%016" PRIx64, w[3]);
        else
            fmt_none(data_buf, sizeof(data_buf));
        if (has_strb)
            snprintf(strb_buf, sizeof(strb_buf), "%02x", strb);
        else
            fmt_none(strb_buf, sizeof(strb_buf));
        if (has_beat)
            snprintf(beat_buf, sizeof(beat_buf), "%u", beat);
        else
            fmt_none(beat_buf, sizeof(beat_buf));
        if (has_lat)
            snprintf(lat_buf, sizeof(lat_buf), "%" PRIu64, latency);
        else
            fmt_none(lat_buf, sizeof(lat_buf));
        if (has_resp)
            snprintf(resp_buf, sizeof(resp_buf), "%s", axi_resp_name(resp));
        else
            fmt_none(resp_buf, sizeof(resp_buf));
        snprintf(pa_buf, sizeof(pa_buf), "%" PRIx64, pa);
        if (w[1])
            snprintf(va_buf, sizeof(va_buf), "%" PRIx64, w[1]);
        else
            fmt_none(va_buf, sizeof(va_buf));
        // #region agent log
        if (has_data && watch_logged < 2) {
            FILE *dbg = fopen("/projects/prj1/sle-wajahat/.cursor/debug-29681a.log", "a");
            if (dbg) {
                fprintf(dbg,
                    "{\"sessionId\":\"29681a\",\"runId\":\"cache-decode\",\"hypothesisId\":\"G\","
                    "\"location\":\"run_cva6_trackers.c:dump_cache_csv\","
                    "\"message\":\"cache beat decode\","
                    "\"data\":{\"sel\":%u,\"kind\":\"%s\",\"line\":\"%" PRIx64 "\","
                    "\"pa\":\"%s\",\"beat\":\"%s\",\"data\":\"%s\",\"decode\":\"%s\","
                    "\"latency\":\"%s\"},"
                    "\"timestamp\":%lld}\n",
                    sel, kind_name(kind), line, pa_buf, beat_buf, data_buf, decode_buf,
                    lat_buf, (long long)time(NULL) * 1000);
                fclose(dbg);
                watch_logged++;
            }
        }
        // #endregion
        fprintf(f,
            "%" PRIu64 ",%s,%s,%" PRIx64 ",%s,%s,%s,%s,%s,%u,%s,%u,%s\n",
            w[0], kind_name(kind), va_buf, line, pa_buf, beat_buf, data_buf, decode_buf,
            strb_buf, bytes, resp_buf, last, lat_buf);
    }
    // #region agent log
    {
        FILE *dbg = fopen("/projects/prj1/sle-wajahat/.cursor/debug-29681a.log", "a");
        if (dbg) {
            fprintf(dbg,
                "{\"sessionId\":\"29681a\",\"runId\":\"l1\",\"hypothesisId\":\"B\","
                "\"location\":\"run_cva6_trackers.c:dump_cache_csv\","
                "\"message\":\"AXI CSV L1-kind count\","
                "\"data\":{\"sel\":%u,\"rows\":%u,\"l1_kind_n\":%u},"
                "\"timestamp\":%lld}\n",
                sel, count, l1_kind_n, (long long)time(NULL) * 1000);
            fclose(dbg);
        }
    }
    // #endregion
    fclose(f);
    return 0;
}

static int dump_event_csv(pci_bar_handle_t bar, const char *path, uint32_t count)
{
    FILE *f = fopen(path, "w");
    uint64_t w[CL_CVA6_EVENT_WORDS];
    if (!f)
        return -1;
    fprintf(f, "cycle,kind,pc,cause,tval,lsu_va,lsu_pa,target,"
               "mstatus,mepc,mcause,mtval,mtvec,satp,mie,mip,"
               "trans_id,rs1,priv,taken,debug\n");
    for (uint32_t i = 0; i < count; i++) {
        char kind_buf[32];
        char rs1_buf[8];
        const char *abi;
        uint64_t flags;
        unsigned trans_id, rs1, priv;
        if (read_record(bar, 3, i, CL_CVA6_EVENT_WORDS, w)) {
            fclose(f);
            return -1;
        }
        flags = w[2];
        fmt_event_kind(kind_buf, sizeof(kind_buf), flags);
        trans_id = (unsigned)((flags >> 16) & 0xff);
        rs1 = (unsigned)((flags >> 24) & 0xff);
        priv = (unsigned)((flags >> 5) & 3);
        abi = abi_reg_name(rs1);
        if (abi)
            snprintf(rs1_buf, sizeof(rs1_buf), "%s", abi);
        else
            snprintf(rs1_buf, sizeof(rs1_buf), "x%u", rs1);
        // #region agent log
        if (i == 0) {
            FILE *dbg = fopen("/projects/prj1/sle-wajahat/.cursor/debug-29681a.log", "a");
            if (dbg) {
                fprintf(dbg,
                    "{\"sessionId\":\"29681a\",\"runId\":\"post-fix\",\"hypothesisId\":\"F\","
                    "\"location\":\"run_cva6_trackers.c:dump_event_csv\","
                    "\"message\":\"first event\","
                    "\"data\":{\"kind\":\"%s\",\"pc\":\"%" PRIx64 "\",\"cause\":\"%s\","
                    "\"tval\":\"%" PRIx64 "\",\"lsu_va\":\"%" PRIx64 "\",\"mstatus\":\"%" PRIx64 "\"},"
                    "\"timestamp\":%lld}\n",
                    kind_buf, w[1], excp_name(w[3]), w[4], w[5], w[8],
                    (long long)time(NULL) * 1000);
                fclose(dbg);
            }
        }
        // #endregion
        fprintf(f,
            "%" PRIu64 ",%s,%" PRIx64 ",%s(0x%" PRIx64 "),%" PRIx64 ","
            "%" PRIx64 ",%" PRIx64 ",%" PRIx64 ","
            "%" PRIx64 ",%" PRIx64 ",%" PRIx64 ",%" PRIx64 ","
            "%" PRIx64 ",%" PRIx64 ",%" PRIx64 ",%" PRIx64 ","
            "%u,%s,%s,%u,%u\n",
            w[0], kind_buf, w[1], excp_name(w[3]), w[3], w[4],
            w[5], w[6], w[7],
            w[8], w[9], w[10], w[11],
            w[12], w[13], w[14], w[15],
            trans_id, rs1_buf, priv_name(priv),
            (unsigned)((flags >> 3) & 1), (unsigned)((flags >> 4) & 1));
    }
    fclose(f);
    return 0;
}

static int dump_l1_csv(pci_bar_handle_t bar, const char *path, uint32_t count)
{
    FILE *f = fopen(path, "w");
    uint64_t w[CL_CVA6_L1_WORDS];
    unsigned watch_logged = 0;
    unsigned hit_n = 0, miss_n = 0, ic_n = 0, dc_n = 0;
    if (!f)
        return -1;
    fprintf(f, "cycle,cache,kind,va,pa\n");
    for (uint32_t i = 0; i < count; i++) {
        uint64_t flags;
        int is_hit, is_miss, is_d;
        char va_buf[20], pa_buf[20];
        if (read_record(bar, 4, i, CL_CVA6_L1_WORDS, w)) {
            fclose(f);
            return -1;
        }
        flags = w[3];
        is_hit  = (int)(flags & 1);
        is_miss = (int)((flags >> 1) & 1);
        is_d    = (int)((flags >> 2) & 1);
        if (is_d)
            dc_n++;
        else
            ic_n++;
        if (is_hit)
            hit_n++;
        if (is_miss)
            miss_n++;
        fmt_hex_csv(va_buf, sizeof(va_buf), w[1] != 0, w[1]);
        fmt_hex_csv(pa_buf, sizeof(pa_buf), w[2] != 0, w[2]);
        // #region agent log
        if (watch_logged < 3) {
            FILE *dbg = fopen("/projects/prj1/sle-wajahat/.cursor/debug-29681a.log", "a");
            if (dbg) {
                fprintf(dbg,
                    "{\"sessionId\":\"29681a\",\"runId\":\"l1\",\"hypothesisId\":\"C\","
                    "\"location\":\"run_cva6_trackers.c:dump_l1_csv\","
                    "\"message\":\"l1 lookup row\","
                    "\"data\":{\"i\":%u,\"cycle\":%" PRIu64 ",\"is_d\":%d,\"hit\":%d,\"miss\":%d,"
                    "\"va\":\"%s\",\"pa\":\"%s\",\"flags\":\"%" PRIx64 "\"},"
                    "\"timestamp\":%lld}\n",
                    i, w[0], is_d, is_hit, is_miss, va_buf, pa_buf, flags,
                    (long long)time(NULL) * 1000);
                fclose(dbg);
                watch_logged++;
            }
        }
        // #endregion
        fprintf(f, "%" PRIu64 ",%s,%s,%s,%s\n",
                w[0], is_d ? "D" : "I",
                is_hit ? "hit" : (is_miss ? "miss" : "NONE"),
                va_buf, pa_buf);
    }
    // #region agent log
    {
        FILE *dbg = fopen("/projects/prj1/sle-wajahat/.cursor/debug-29681a.log", "a");
        if (dbg) {
            fprintf(dbg,
                "{\"sessionId\":\"29681a\",\"runId\":\"l1\",\"hypothesisId\":\"C\","
                "\"location\":\"run_cva6_trackers.c:dump_l1_csv\","
                "\"message\":\"l1 dump summary\","
                "\"data\":{\"rows\":%u,\"hit_n\":%u,\"miss_n\":%u,\"ic_n\":%u,\"dc_n\":%u},"
                "\"timestamp\":%lld}\n",
                count, hit_n, miss_n, ic_n, dc_n, (long long)time(NULL) * 1000);
            fclose(dbg);
        }
    }
    // #endregion
    fclose(f);
    return 0;
}

int main(int argc, char **argv)
{
    int rc;
    int slot_id = 0;
    int uart_idle_ms = 120000;
    int uart_max_ms = 300000;
    uint64_t window_start = 2000;
    uint64_t window_end = 4000;
    const char *bin_path = NULL;
    const char *log_path = NULL;
    const char *trace_dir = ".";
    pci_bar_handle_t bar0 = PCI_BAR_HANDLE_INIT;
    pci_bar_handle_t bar4 = PCI_BAR_HANDLE_INIT;
    uint32_t magic = 0;
    uint32_t instr_n = 0, ic_n = 0, dc_n = 0, evt_n = 0, l1_n = 0, st = 0;
    uint32_t ic_hit_n = 0, ic_miss_n = 0, dc_hit_n = 0, dc_miss_n = 0;
    int stop_on_excp = 0;
    char path[512];

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--slot") && i + 1 < argc)
            slot_id = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--bin") && i + 1 < argc)
            bin_path = argv[++i];
        else if (!strcmp(argv[i], "--window-start") && i + 1 < argc)
            window_start = strtoull(argv[++i], NULL, 0);
        else if (!strcmp(argv[i], "--window-end") && i + 1 < argc)
            window_end = strtoull(argv[++i], NULL, 0);
        else if (!strcmp(argv[i], "--trace-dir") && i + 1 < argc)
            trace_dir = argv[++i];
        else if (!strcmp(argv[i], "--uart-idle-ms") && i + 1 < argc)
            uart_idle_ms = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--uart-max-ms") && i + 1 < argc)
            uart_max_ms = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--log") && i + 1 < argc)
            log_path = argv[++i];
        else if (!strcmp(argv[i], "--stop-on-exception"))
            stop_on_excp = 1;
        else {
            usage(argv[0]);
            return 1;
        }
    }
    if (!bin_path || window_end <= window_start) {
        usage(argv[0]);
        return 1;
    }
    if (mkdir_p(trace_dir)) {
        fprintf(stderr, "mkdir %s: %s\n", trace_dir, strerror(errno));
        return 1;
    }
    if (log_path) {
        uart_log = fopen(log_path, "w");
        fail_on(!uart_log, out, "open log %s", log_path);
    }

    rc = log_init("run_cva6_trackers");
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
        log_msg("Unexpected MAGIC 0x%08x (want 0x%08x). Load the cl_cva6_trackers AFI.\n",
               magic, CL_CVA6_MAGIC_VAL);
        rc = 1;
        goto out;
    }
    log_msg("cl_cva6_trackers MAGIC ok\n");

    rc = fpga_pci_poke(bar0, CL_CVA6_CTRL, 0);
    fail_on(rc, out, "hold reset");

    rc = wait_hbm_ready(bar0);
    fail_on(rc, out, "HBM ready");
    log_msg("HBM ready\n");

    rc = poke64(bar0, CL_CVA6_TRACE_START_LO, window_start);
    fail_on(rc, out, "trace start");
    rc = poke64(bar0, CL_CVA6_TRACE_END_LO, window_end);
    fail_on(rc, out, "trace end");
    uint32_t tctrl = CL_CVA6_TRACE_ENABLE | CL_CVA6_TRACE_CLEAR;
    if (stop_on_excp)
        tctrl |= CL_CVA6_TRACE_STOP_EXCP;
    rc = fpga_pci_poke(bar0, CL_CVA6_TRACE_CTRL, tctrl);
    fail_on(rc, out, "trace clear");
    usleep(1000);
    tctrl = CL_CVA6_TRACE_ENABLE;
    if (stop_on_excp)
        tctrl |= CL_CVA6_TRACE_STOP_EXCP;
    rc = fpga_pci_poke(bar0, CL_CVA6_TRACE_CTRL, tctrl);
    fail_on(rc, out, "trace enable");
    log_msg("Trace window [%" PRIu64 ", %" PRIu64 ") CPU cycles%s\n",
            window_start, window_end,
            stop_on_excp ? " stop-on-exception" : "");

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
    g_image = buf;
    if (fread(g_image, 1, (size_t)sz, f) != (size_t)sz) {
        fclose(f);
        rc = 1;
        goto out;
    }
    fclose(f);
    g_image_len = (size_t)sz;

    rc = fpga_pci_attach(slot_id, FPGA_APP_PF, APP_PF_BAR4, BURST_CAPABLE, &bar4);
    fail_on(rc, out, "fpga_pci_attach BAR4");

    log_msg("Loading %ld bytes from %s via AppPF BAR4 @ 0x%llx\n",
           sz, bin_path, (unsigned long long)CL_PCIS_HBM_BASE);
    rc = load_bar4(bar4, g_image, padded);
    fail_on(rc, out, "BAR4 burst write");

    (void)drain_uart(bar0, 200, 1000, 0);

    log_msg("Releasing CVA6 reset\n");
    rc = fpga_pci_poke(bar0, CL_CVA6_CTRL, 1);
    fail_on(rc, out, "run");

    log_msg("--- UART from CVA6 ---\n");
    int got = drain_uart(bar0, uart_idle_ms, uart_max_ms, 1);
    rc = (got < 0);
    fail_on(rc, out, "uart drain");
    log_msg("\n--- done, %d byte(s) ---\n", got);

    rc = fpga_pci_peek(bar0, CL_CVA6_TRACE_STATUS, &st);
    fail_on(rc, out, "trace status");
    rc = fpga_pci_peek(bar0, CL_CVA6_TRACE_INSTR_CNT, &instr_n);
    fail_on(rc, out, "instr count");
    rc = fpga_pci_peek(bar0, CL_CVA6_TRACE_IC_CNT, &ic_n);
    fail_on(rc, out, "icache count");
    rc = fpga_pci_peek(bar0, CL_CVA6_TRACE_DC_CNT, &dc_n);
    fail_on(rc, out, "dcache count");
    rc = fpga_pci_peek(bar0, CL_CVA6_TRACE_EVT_CNT, &evt_n);
    fail_on(rc, out, "event count");
    rc = fpga_pci_peek(bar0, CL_CVA6_TRACE_L1_CNT, &l1_n);
    fail_on(rc, out, "l1 count");
    rc = fpga_pci_peek(bar0, CL_CVA6_TRACE_IC_HIT, &ic_hit_n);
    fail_on(rc, out, "ic hit");
    rc = fpga_pci_peek(bar0, CL_CVA6_TRACE_IC_MISS, &ic_miss_n);
    fail_on(rc, out, "ic miss");
    rc = fpga_pci_peek(bar0, CL_CVA6_TRACE_DC_HIT, &dc_hit_n);
    fail_on(rc, out, "dc hit");
    rc = fpga_pci_peek(bar0, CL_CVA6_TRACE_DC_MISS, &dc_miss_n);
    fail_on(rc, out, "dc miss");
    // #region agent log
    {
        FILE *dbg = fopen("/projects/prj1/sle-wajahat/.cursor/debug-29681a.log", "a");
        if (dbg) {
            fprintf(dbg,
                "{\"sessionId\":\"29681a\",\"runId\":\"l1\",\"hypothesisId\":\"A\","
                "\"location\":\"run_cva6_trackers.c:main\","
                "\"message\":\"raw L1/hit-miss OCL peeks\","
                "\"data\":{\"evt_n\":%u,\"l1_n\":%u,\"ic_hit\":%u,\"ic_miss\":%u,"
                "\"dc_hit\":%u,\"dc_miss\":%u,\"st\":%u},"
                "\"timestamp\":%lld}\n",
                evt_n, l1_n, ic_hit_n, ic_miss_n, dc_hit_n, dc_miss_n, st,
                (long long)time(NULL) * 1000);
            fclose(dbg);
        }
    }
    // #endregion
    if (evt_n > 256) {
        log_msg("TRACE_EVT_CNT=0x%08x (no event FIFO on this AFI); skipping events.csv\n",
                evt_n);
        evt_n = 0;
    }
    if (l1_n > CL_CVA6_L1_DEPTH) {
        log_msg("TRACE_L1_CNT=0x%08x (no L1 lookup FIFO on this AFI); skipping l1.csv\n",
                l1_n);
        l1_n = 0;
        ic_hit_n = ic_miss_n = dc_hit_n = dc_miss_n = 0;
    }
    log_msg("Trace status 0x%08x  instr=%u icache=%u dcache=%u events=%u l1=%u%s%s%s%s%s%s\n",
            st, instr_n, ic_n, dc_n, evt_n, l1_n,
            (st & CL_CVA6_TRACE_ST_INSTR_OVF) ? " INSTR_OVF" : "",
            (st & CL_CVA6_TRACE_ST_IC_OVF) ? " IC_OVF" : "",
            (st & CL_CVA6_TRACE_ST_DC_OVF) ? " DC_OVF" : "",
            (st & CL_CVA6_TRACE_ST_EVT_OVF) ? " EVT_OVF" : "",
            (st & CL_CVA6_TRACE_ST_L1_OVF) ? " L1_OVF" : "",
            (st & CL_CVA6_TRACE_ST_FROZEN) ? " FROZEN" : "");
    log_msg("L1 counters  ic_hit=%u ic_miss=%u dc_hit=%u dc_miss=%u\n",
            ic_hit_n, ic_miss_n, dc_hit_n, dc_miss_n);

    snprintf(path, sizeof(path), "%s/instr.csv", trace_dir);
    rc = dump_instr_csv(bar0, path, instr_n);
    fail_on(rc, out, "write %s", path);
    log_msg("Wrote %s (%u rows)\n", path, instr_n);

    snprintf(path, sizeof(path), "%s/icache.csv", trace_dir);
    rc = dump_cache_csv(bar0, 1, path, ic_n);
    fail_on(rc, out, "write %s", path);
    log_msg("Wrote %s (%u rows)\n", path, ic_n);

    snprintf(path, sizeof(path), "%s/dcache.csv", trace_dir);
    rc = dump_cache_csv(bar0, 2, path, dc_n);
    fail_on(rc, out, "write %s", path);
    log_msg("Wrote %s (%u rows)\n", path, dc_n);

    snprintf(path, sizeof(path), "%s/events.csv", trace_dir);
    rc = dump_event_csv(bar0, path, evt_n);
    fail_on(rc, out, "write %s", path);
    log_msg("Wrote %s (%u rows)\n", path, evt_n);

    snprintf(path, sizeof(path), "%s/l1.csv", trace_dir);
    rc = dump_l1_csv(bar0, path, l1_n);
    fail_on(rc, out, "write %s", path);
    log_msg("Wrote %s (%u rows)\n", path, l1_n);

out:
    free(g_image);
    g_image = NULL;
    g_image_len = 0;
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
