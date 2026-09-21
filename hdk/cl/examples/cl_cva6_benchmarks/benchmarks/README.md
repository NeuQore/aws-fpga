# SLE RISC-V benchmarks for AWS F2 CVA6

Bare-metal kernels for [`cl_cva6_benchmarks`](https://github.com/SilverLining-EDA/aws-fpga) on AWS F2. They load through AppPF BAR4 into HBM at CVA6 `0x80000000` and print `=== START/STOP ===` markers on the host UART.

ISA: **RV64IMAFDC** (`cv64a6_imafdc_sv39`). Same AGFI as `cl_cva6_linux`: `agfi-0248c1f84010b03e9`.

## Build

```bash
sudo apt-get install -y gcc-riscv64-unknown-elf
make                          # all tests
make -C tests/bpu_1_loop_branch
```

Each test produces `tests/<name>/<name>.bin`.

## What runs vs what is a skip stub

| Name | Source |
|------|--------|
| `bpu_*`, `retire_test`, `l1_cache_test_32kb`, `lrsc*`, `test_*_store2load_overlap`, `power_virus`, `ipi`, `uart_baud`, `ncore_mem_access` | Original kernels in this repo |
| `coremark` | [EEMBC CoreMark](https://github.com/eembc/coremark) (Apache-2.0), F2 UART/`rdcycle` port |
| `dhrystone` | Compact original integer mix (not Weicker's ACM source) |
| `hmmer`, `libquantum`, `mcf` | Small original kernels of the same *type* as those SPEC workloads, not SPEC CPU |
| `fp16_dotp_rvv`, `int8_dotp_rvv` | Skip — this CVA6 config has no RVV |
| `int8_dotp_imext`, `mxfp4_dotp_imext_ar`, `imext_kernels` | Skip — no IMEXT on this FPGA CL |
| `qspi`, `sdio_sdhc` | Skip — no QSPI/SDIO in `cl_cva6_linux` |

## UART contract

```
=== START <name> ===
...
=== STOP <name> cycles=<n> ===
```

Skip stubs print `=== SKIP <name> : <reason> ===`.
