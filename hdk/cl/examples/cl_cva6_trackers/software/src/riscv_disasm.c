#include "riscv_disasm.h"

#include <stdio.h>
#include <string.h>

#define OPCODE(i)  ((i) & 0x7fu)
#define RD(i)      (((i) >> 7) & 0x1fu)
#define FUNCT3(i)  (((i) >> 12) & 0x7u)
#define RS1(i)     (((i) >> 15) & 0x1fu)
#define RS2(i)     (((i) >> 20) & 0x1fu)
#define FUNCT7(i)  (((i) >> 25) & 0x7fu)
#define IMM12(i)   ((int32_t)(i) >> 20)

static int put(char *out, size_t n, const char *s)
{
    if (!out || n == 0)
        return -1;
    snprintf(out, n, "%s", s);
    return 0;
}

int riscv_fetch_insn(const uint8_t *image, size_t len, uint64_t base,
                     uint64_t pc, uint32_t *insn, int *compressed)
{
    size_t off;
    uint16_t lo;

    if (!image || !insn || pc < base)
        return -1;
    off = (size_t)(pc - base);
    if (off + 1 >= len)
        return -1;
    lo = (uint16_t)image[off] | ((uint16_t)image[off + 1] << 8);
    if ((lo & 3u) != 3u) {
        *insn = lo;
        if (compressed)
            *compressed = 1;
        return 0;
    }
    if (off + 3 >= len)
        return -1;
    *insn = (uint32_t)lo |
            ((uint32_t)image[off + 2] << 16) |
            ((uint32_t)image[off + 3] << 24);
    if (compressed)
        *compressed = 0;
    return 0;
}

static int disasm_c(uint16_t c, char *out, size_t n)
{
    unsigned op = c & 3u;
    unsigned f3 = (c >> 13) & 7u;
    unsigned rd = (c >> 7) & 0x1fu;
    unsigned rs2 = (c >> 2) & 0x1fu;
    unsigned bit12 = (c >> 12) & 1u;

    if (op == 0u) {
        switch (f3) {
        case 0: return put(out, n, "addi");  /* c.addi4spn */
        case 1: return put(out, n, "fld");
        case 2: return put(out, n, "lw");
        case 3: return put(out, n, "ld");
        case 5: return put(out, n, "fsd");
        case 6: return put(out, n, "sw");
        case 7: return put(out, n, "sd");
        default: return put(out, n, "c.unk");
        }
    }
    if (op == 1u) {
        switch (f3) {
        case 0: {
            int imm = ((c & 0x1000) ? ~0x1f : 0) | ((c >> 2) & 0x1f);
            if (rd == 0 && imm == 0)
                return put(out, n, "nop");
            return put(out, n, "addi");
        }
        case 1: return put(out, n, "addiw");
        case 2: return put(out, n, "li");
        case 3:
            if (rd == 2)
                return put(out, n, "addi"); /* c.addi16sp */
            return put(out, n, "lui");
        case 4: {
            unsigned f = (c >> 10) & 3u;
            unsigned f2 = (c >> 5) & 3u;
            if (f == 0)
                return put(out, n, "srli");
            if (f == 1)
                return put(out, n, "srai");
            if (f == 2)
                return put(out, n, "andi");
            if (!bit12) {
                if (f2 == 0) return put(out, n, "sub");
                if (f2 == 1) return put(out, n, "xor");
                if (f2 == 2) return put(out, n, "or");
                return put(out, n, "and");
            }
            if (f2 == 0) return put(out, n, "subw");
            if (f2 == 1) return put(out, n, "addw");
            return put(out, n, "c.unk");
        }
        case 5: return put(out, n, "j");
        case 6: return put(out, n, "beqz");
        case 7: return put(out, n, "bnez");
        default: return put(out, n, "c.unk");
        }
    }
    if (op == 2u) {
        switch (f3) {
        case 0: return put(out, n, "slli");
        case 1: return put(out, n, "fld");
        case 2: return put(out, n, "lw");
        case 3: return put(out, n, "ld");
        case 4:
            if (!bit12 && rs2 == 0) {
                if (rd == 1)
                    return put(out, n, "ret");
                return put(out, n, "jr");
            }
            if (!bit12 && rs2 != 0)
                return put(out, n, "mv");
            if (bit12 && rd == 0 && rs2 == 0)
                return put(out, n, "ebreak");
            if (bit12 && rs2 == 0)
                return put(out, n, "jalr");
            return put(out, n, "add");
        case 5: return put(out, n, "fsd");
        case 6: return put(out, n, "sw");
        case 7: return put(out, n, "sd");
        default: return put(out, n, "c.unk");
        }
    }
    return put(out, n, "c.unk");
}

static int disasm_32(uint32_t i, char *out, size_t n)
{
    unsigned opc = OPCODE(i);
    unsigned f3 = FUNCT3(i);
    unsigned f7 = FUNCT7(i);
    unsigned rd = RD(i);
    unsigned rs1 = RS1(i);
    unsigned rs2 = RS2(i);
    int imm12 = IMM12(i);

    switch (opc) {
    case 0x37: return put(out, n, "lui");
    case 0x17: return put(out, n, "auipc");
    case 0x6f: return put(out, n, rd ? "jal" : "j");
    case 0x67:
        if (f3 == 0) {
            if (rd == 0 && rs1 == 1 && imm12 == 0)
                return put(out, n, "ret");
            if (rd == 0)
                return put(out, n, "jr");
            return put(out, n, "jalr");
        }
        break;
    case 0x63:
        switch (f3) {
        case 0: return put(out, n, rs2 ? "beq" : "beqz");
        case 1: return put(out, n, rs2 ? "bne" : "bnez");
        case 4: return put(out, n, "blt");
        case 5: return put(out, n, "bge");
        case 6: return put(out, n, "bltu");
        case 7: return put(out, n, "bgeu");
        default: break;
        }
        break;
    case 0x03:
        switch (f3) {
        case 0: return put(out, n, "lb");
        case 1: return put(out, n, "lh");
        case 2: return put(out, n, "lw");
        case 3: return put(out, n, "ld");
        case 4: return put(out, n, "lbu");
        case 5: return put(out, n, "lhu");
        case 6: return put(out, n, "lwu");
        default: break;
        }
        break;
    case 0x23:
        switch (f3) {
        case 0: return put(out, n, "sb");
        case 1: return put(out, n, "sh");
        case 2: return put(out, n, "sw");
        case 3: return put(out, n, "sd");
        default: break;
        }
        break;
    case 0x13:
        switch (f3) {
        case 0:
            if (rs1 == 0)
                return put(out, n, "li");
            if (imm12 == 0)
                return put(out, n, "mv");
            return put(out, n, "addi");
        case 1: return put(out, n, "slli");
        case 2: return put(out, n, "slti");
        case 3: return put(out, n, "sltiu");
        case 4: return put(out, n, "xori");
        case 5: return put(out, n, (f7 & 0x20) ? "srai" : "srli");
        case 6: return put(out, n, "ori");
        case 7:
            if ((imm12 & 0xfff) == 0xff)
                return put(out, n, "zext.b");
            return put(out, n, "andi");
        default: break;
        }
        break;
    case 0x1b:
        switch (f3) {
        case 0: return put(out, n, "addiw");
        case 1: return put(out, n, "slliw");
        case 5: return put(out, n, (f7 & 0x20) ? "sraiw" : "srliw");
        default: break;
        }
        break;
    case 0x33:
        if (f7 == 1) {
            switch (f3) {
            case 0: return put(out, n, "mul");
            case 1: return put(out, n, "mulh");
            case 2: return put(out, n, "mulhsu");
            case 3: return put(out, n, "mulhu");
            case 4: return put(out, n, "div");
            case 5: return put(out, n, "divu");
            case 6: return put(out, n, "rem");
            case 7: return put(out, n, "remu");
            default: break;
            }
        } else {
            switch (f3) {
            case 0: return put(out, n, (f7 & 0x20) ? "sub" : "add");
            case 1: return put(out, n, "sll");
            case 2: return put(out, n, "slt");
            case 3: return put(out, n, "sltu");
            case 4: return put(out, n, "xor");
            case 5: return put(out, n, (f7 & 0x20) ? "sra" : "srl");
            case 6: return put(out, n, "or");
            case 7: return put(out, n, "and");
            default: break;
            }
        }
        break;
    case 0x3b:
        if (f7 == 1) {
            switch (f3) {
            case 0: return put(out, n, "mulw");
            case 4: return put(out, n, "divw");
            case 5: return put(out, n, "divuw");
            case 6: return put(out, n, "remw");
            case 7: return put(out, n, "remuw");
            default: break;
            }
        } else {
            switch (f3) {
            case 0: return put(out, n, (f7 & 0x20) ? "subw" : "addw");
            case 1: return put(out, n, "sllw");
            case 5: return put(out, n, (f7 & 0x20) ? "sraw" : "srlw");
            default: break;
            }
        }
        break;
    case 0x0f:
        return put(out, n, f3 == 1 ? "fence.i" : "fence");
    case 0x73: {
        unsigned csr = i >> 20;
        if (f3 == 0) {
            if (i == 0x00000073u) return put(out, n, "ecall");
            if (i == 0x00100073u) return put(out, n, "ebreak");
            if (i == 0x30200073u) return put(out, n, "mret");
            if (i == 0x10200073u) return put(out, n, "sret");
            if (i == 0x7b200073u) return put(out, n, "dret");
            if (i == 0x10500073u) return put(out, n, "wfi");
            if (f7 == 0x09) return put(out, n, "sfence.vma");
            return put(out, n, "system");
        }
        if (f3 == 1)
            return put(out, n, rd ? "csrrw" : "csrw");
        if (f3 == 2) {
            if (rs1 == 0) {
                if (csr == 0xc00) return put(out, n, "rdcycle");
                if (csr == 0xc01) return put(out, n, "rdtime");
                if (csr == 0xc02) return put(out, n, "rdinstret");
                return put(out, n, "csrr");
            }
            return put(out, n, rd ? "csrrs" : "csrs");
        }
        if (f3 == 3)
            return put(out, n, rd ? "csrrc" : "csrc");
        if (f3 == 5)
            return put(out, n, rd ? "csrrwi" : "csrwi");
        if (f3 == 6)
            return put(out, n, rd ? "csrrsi" : "csrsi");
        if (f3 == 7)
            return put(out, n, rd ? "csrrci" : "csrci");
        break;
    }
    case 0x07:
        switch (f3) {
        case 2: return put(out, n, "flw");
        case 3: return put(out, n, "fld");
        default: break;
        }
        break;
    case 0x27:
        switch (f3) {
        case 2: return put(out, n, "fsw");
        case 3: return put(out, n, "fsd");
        default: break;
        }
        break;
    case 0x2f: {
        unsigned f5 = (i >> 27) & 0x1fu;
        int wd = (f3 == 2);
        switch (f5) {
        case 0x02: return put(out, n, wd ? "lr.w" : "lr.d");
        case 0x03: return put(out, n, wd ? "sc.w" : "sc.d");
        case 0x01: return put(out, n, wd ? "amoswap.w" : "amoswap.d");
        case 0x00: return put(out, n, wd ? "amoadd.w" : "amoadd.d");
        case 0x04: return put(out, n, wd ? "amoxor.w" : "amoxor.d");
        case 0x0c: return put(out, n, wd ? "amoand.w" : "amoand.d");
        case 0x08: return put(out, n, wd ? "amoor.w" : "amoor.d");
        case 0x10: return put(out, n, wd ? "amomin.w" : "amomin.d");
        case 0x14: return put(out, n, wd ? "amomax.w" : "amomax.d");
        case 0x18: return put(out, n, wd ? "amominu.w" : "amominu.d");
        case 0x1c: return put(out, n, wd ? "amomaxu.w" : "amomaxu.d");
        default: break;
        }
        break;
    }
    default:
        break;
    }
    return put(out, n, "unknown");
}

int riscv_disasm_mnemonic(uint32_t insn, char *out, size_t n)
{
    if ((insn & 3u) != 3u)
        return disasm_c((uint16_t)insn, out, n);
    return disasm_32(insn, out, n);
}

static int64_t sext64(uint64_t v, int bits)
{
    int sh = 64 - bits;
    return (int64_t)(v << sh) >> sh;
}

static unsigned creg(unsigned r)
{
    return 8u + (r & 7u);
}

static void set_rs1(riscv_operands_t *o, unsigned r)
{
    o->has_rs1 = 1;
    o->rs1 = r;
}

static void set_rs2(riscv_operands_t *o, unsigned r)
{
    o->has_rs2 = 1;
    o->rs2 = r;
}

static void set_rd(riscv_operands_t *o, unsigned r)
{
    o->has_rd = 1;
    o->rd = r;
}

static void set_imm(riscv_operands_t *o, int64_t imm)
{
    o->has_imm = 1;
    o->imm = imm;
}

static int decode_c_ops(uint16_t c, riscv_operands_t *o)
{
    unsigned op = c & 3u;
    unsigned f3 = (c >> 13) & 7u;
    unsigned rd = (c >> 7) & 0x1fu;
    unsigned rs2 = (c >> 2) & 0x1fu;
    unsigned bit12 = (c >> 12) & 1u;
    unsigned rds = creg((c >> 2) & 7u);
    unsigned rs1s = creg((c >> 7) & 7u);
    int64_t nimm5 = sext64(((uint64_t)bit12 << 5) | ((c >> 2) & 0x1fu), 6);

    if (op == 0u) {
        switch (f3) {
        case 0: /* c.addi4spn */
            set_rd(o, rds);
            set_rs1(o, 2);
            set_imm(o, (int64_t)(((c >> 11) & 3u) << 4 |
                                 ((c >> 7) & 0xfu) << 6 |
                                 ((c >> 6) & 1u) << 2 |
                                 ((c >> 5) & 1u) << 3));
            return 0;
        case 1: /* c.fld */
        case 2: /* c.lw */
        case 3: /* c.ld */
            set_rd(o, rds);
            set_rs1(o, rs1s);
            if (f3 == 2)
                set_imm(o, (int64_t)(((c >> 10) & 7u) << 3 |
                                     ((c >> 6) & 1u) << 2 |
                                     ((c >> 5) & 1u) << 6));
            else
                set_imm(o, (int64_t)(((c >> 10) & 7u) << 3 |
                                     ((c >> 5) & 3u) << 6));
            return 0;
        case 5: /* c.fsd */
        case 6: /* c.sw */
        case 7: /* c.sd */
            set_rs2(o, rds);
            set_rs1(o, rs1s);
            if (f3 == 6)
                set_imm(o, (int64_t)(((c >> 10) & 7u) << 3 |
                                     ((c >> 6) & 1u) << 2 |
                                     ((c >> 5) & 1u) << 6));
            else
                set_imm(o, (int64_t)(((c >> 10) & 7u) << 3 |
                                     ((c >> 5) & 3u) << 6));
            return 0;
        default:
            return -1;
        }
    }
    if (op == 1u) {
        switch (f3) {
        case 0: /* c.addi / c.nop */
            set_rd(o, rd);
            set_rs1(o, rd);
            set_imm(o, nimm5);
            return 0;
        case 1: /* c.addiw */
            set_rd(o, rd);
            set_rs1(o, rd);
            set_imm(o, nimm5);
            return 0;
        case 2: /* c.li */
            set_rd(o, rd);
            set_rs1(o, 0);
            set_imm(o, nimm5);
            return 0;
        case 3:
            if (rd == 2) { /* c.addi16sp */
                set_rd(o, 2);
                set_rs1(o, 2);
                set_imm(o, sext64(((uint64_t)bit12 << 9) |
                                  ((uint64_t)((c >> 6) & 1u) << 4) |
                                  ((uint64_t)((c >> 5) & 1u) << 6) |
                                  ((uint64_t)((c >> 3) & 3u) << 7) |
                                  ((uint64_t)((c >> 2) & 1u) << 5), 10));
            } else { /* c.lui */
                set_rd(o, rd);
                set_imm(o, sext64(((uint64_t)bit12 << 17) |
                                  ((uint64_t)((c >> 2) & 0x1fu) << 12), 18));
            }
            return 0;
        case 4: {
            unsigned f = (c >> 10) & 3u;
            unsigned f2 = (c >> 5) & 3u;
            set_rd(o, rs1s);
            set_rs1(o, rs1s);
            if (f == 0 || f == 1) { /* srli / srai */
                set_imm(o, (int64_t)(((uint64_t)bit12 << 5) | ((c >> 2) & 0x1fu)));
                return 0;
            }
            if (f == 2) { /* andi */
                set_imm(o, nimm5);
                return 0;
            }
            set_rs2(o, creg((c >> 2) & 7u));
            (void)f2;
            return 0;
        }
        case 5: /* c.j */
            set_imm(o, sext64(((uint64_t)bit12 << 11) |
                              ((uint64_t)((c >> 11) & 1u) << 4) |
                              ((uint64_t)((c >> 9) & 3u) << 8) |
                              ((uint64_t)((c >> 8) & 1u) << 10) |
                              ((uint64_t)((c >> 7) & 1u) << 6) |
                              ((uint64_t)((c >> 6) & 1u) << 7) |
                              ((uint64_t)((c >> 3) & 7u) << 1) |
                              ((uint64_t)((c >> 2) & 1u) << 5), 12));
            return 0;
        case 6: /* c.beqz */
        case 7: /* c.bnez */
            set_rs1(o, rs1s);
            set_rs2(o, 0);
            set_imm(o, sext64(((uint64_t)bit12 << 8) |
                              ((uint64_t)((c >> 10) & 3u) << 3) |
                              ((uint64_t)((c >> 5) & 3u) << 6) |
                              ((uint64_t)((c >> 3) & 3u) << 1) |
                              ((uint64_t)((c >> 2) & 1u) << 5), 9));
            return 0;
        default:
            return -1;
        }
    }
    if (op == 2u) {
        switch (f3) {
        case 0: /* c.slli */
            set_rd(o, rd);
            set_rs1(o, rd);
            set_imm(o, (int64_t)(((uint64_t)bit12 << 5) | ((c >> 2) & 0x1fu)));
            return 0;
        case 1: /* c.fldsp */
        case 2: /* c.lwsp */
        case 3: /* c.ldsp */
            set_rd(o, rd);
            set_rs1(o, 2);
            if (f3 == 2)
                set_imm(o, (int64_t)(((uint64_t)bit12 << 5) |
                                     ((c >> 4) & 7u) << 2 |
                                     ((c >> 2) & 3u) << 6));
            else
                set_imm(o, (int64_t)(((uint64_t)bit12 << 5) |
                                     ((c >> 5) & 3u) << 3 |
                                     ((c >> 2) & 7u) << 6));
            return 0;
        case 4:
            if (!bit12 && rs2 == 0) { /* c.jr / c.ret */
                set_rs1(o, rd);
                return 0;
            }
            if (!bit12 && rs2 != 0) { /* c.mv */
                set_rd(o, rd);
                set_rs1(o, 0);
                set_rs2(o, rs2);
                return 0;
            }
            if (bit12 && rd == 0 && rs2 == 0) /* c.ebreak */
                return 0;
            if (bit12 && rs2 == 0) { /* c.jalr */
                set_rd(o, 1);
                set_rs1(o, rd);
                return 0;
            }
            /* c.add */
            set_rd(o, rd);
            set_rs1(o, rd);
            set_rs2(o, rs2);
            return 0;
        case 5: /* c.fsdsp */
        case 6: /* c.swsp */
        case 7: /* c.sdsp */
            set_rs2(o, rs2);
            set_rs1(o, 2);
            if (f3 == 6)
                set_imm(o, (int64_t)(((c >> 9) & 0xfu) << 2 |
                                     ((c >> 7) & 3u) << 6));
            else
                set_imm(o, (int64_t)(((c >> 10) & 7u) << 3 |
                                     ((c >> 7) & 7u) << 6));
            return 0;
        default:
            return -1;
        }
    }
    return -1;
}

static int decode_32_ops(uint32_t i, riscv_operands_t *o)
{
    unsigned opc = OPCODE(i);
    unsigned f3 = FUNCT3(i);
    unsigned rd = RD(i);
    unsigned rs1 = RS1(i);
    unsigned rs2 = RS2(i);
    int64_t iimm = sext64((i >> 20) & 0xfffu, 12);
    int64_t simm = sext64(((i >> 25) << 5) | ((i >> 7) & 0x1fu), 12);
    int64_t bimm = sext64(((uint64_t)((i >> 31) & 1u) << 12) |
                          ((uint64_t)((i >> 7) & 1u) << 11) |
                          ((uint64_t)((i >> 25) & 0x3fu) << 5) |
                          ((uint64_t)((i >> 8) & 0xfu) << 1), 13);
    int64_t uimm = sext64((uint64_t)(i & 0xfffff000u), 32);
    int64_t jimm = sext64(((uint64_t)((i >> 31) & 1u) << 20) |
                          ((uint64_t)((i >> 12) & 0xffu) << 12) |
                          ((uint64_t)((i >> 20) & 1u) << 11) |
                          ((uint64_t)((i >> 21) & 0x3ffu) << 1), 21);

    switch (opc) {
    case 0x37: /* lui */
    case 0x17: /* auipc */
        set_rd(o, rd);
        set_imm(o, uimm);
        return 0;
    case 0x6f: /* jal */
        set_rd(o, rd);
        set_imm(o, jimm);
        return 0;
    case 0x67: /* jalr */
        set_rd(o, rd);
        set_rs1(o, rs1);
        set_imm(o, iimm);
        return 0;
    case 0x63:
        set_rs1(o, rs1);
        set_rs2(o, rs2);
        set_imm(o, bimm);
        return 0;
    case 0x03:
    case 0x07:
        set_rd(o, rd);
        set_rs1(o, rs1);
        set_imm(o, iimm);
        return 0;
    case 0x23:
    case 0x27:
        set_rs1(o, rs1);
        set_rs2(o, rs2);
        set_imm(o, simm);
        return 0;
    case 0x13:
    case 0x1b:
        set_rd(o, rd);
        set_rs1(o, rs1);
        if (f3 == 1 || f3 == 5)
            set_imm(o, (int64_t)((i >> 20) & 0x3fu));
        else
            set_imm(o, iimm);
        return 0;
    case 0x33:
    case 0x3b:
    case 0x2f:
        set_rd(o, rd);
        set_rs1(o, rs1);
        set_rs2(o, rs2);
        return 0;
    case 0x0f:
        set_imm(o, iimm);
        return 0;
    case 0x73:
        if (f3 == 0)
            return 0;
        set_rd(o, rd);
        o->has_csr = 1;
        o->csr = i >> 20;
        if (f3 >= 5) {
            set_imm(o, (int64_t)rs1);
        } else {
            set_rs1(o, rs1);
            set_imm(o, (int64_t)(i >> 20));
        }
        return 0;
    default:
        return -1;
    }
}

int riscv_decode_operands(uint32_t insn, riscv_operands_t *out)
{
    if (!out)
        return -1;
    memset(out, 0, sizeof(*out));
    out->insn = insn;
    if ((insn & 3u) != 3u) {
        out->compressed = 1;
        return decode_c_ops((uint16_t)insn, out);
    }
    return decode_32_ops(insn, out);
}
