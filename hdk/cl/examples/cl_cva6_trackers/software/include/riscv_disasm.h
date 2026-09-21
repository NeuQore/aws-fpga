#pragma once

#include <stddef.h>
#include <stdint.h>

#define RISCV_IMAGE_BASE 0x80000000ULL

typedef struct riscv_operands {
    uint32_t insn;
    int compressed;
    int has_rs1;
    int has_rs2;
    int has_rd;
    int has_imm;
    int has_csr;
    unsigned rs1;
    unsigned rs2;
    unsigned rd;
    int64_t imm;
    unsigned csr;
} riscv_operands_t;

/* Fetch a 16- or 32-bit little-endian insn at pc from a raw image loaded at base. */
int riscv_fetch_insn(const uint8_t *image, size_t len, uint64_t base,
                     uint64_t pc, uint32_t *insn, int *compressed);

/* Decode insn (compressed if bits[1:0] != 2'b11) into a RISC-V mnemonic. */
int riscv_disasm_mnemonic(uint32_t insn, char *out, size_t n);

/* Architectural rs1/rs2/rd, signed immediate, and CSR address. */
int riscv_decode_operands(uint32_t insn, riscv_operands_t *out);
