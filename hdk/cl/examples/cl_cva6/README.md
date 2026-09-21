# CL_CVA6 — RV32 CVA6 baseline on AWS F2

Reference sibling of [`cl_cva6_linux`](../cl_cva6_linux/README.md). The **production** F2 image for Linux, benchmarks, and llama is **RV64** on the linux AGFI (`MAGIC 0xC6A66401`, device `0xF0C7`). This directory documents the **RV32** bring-up path (`TARGET_CFG=cv32a6_ima_sv32_fpga`, `MAGIC 0xC6A60001`, device `0xF0C6`).

See the comparison table in [cl_cva6_linux — What changed vs cl_cva6](../cl_cva6_linux/README.md#what-changed-vs-cl_cva6) and the ecosystem index [CVA6_F2_README.md](../CVA6_F2_README.md).

## Repositories

| | |
|--|--|
| HDK / this CL | [NeuQore/aws-fpga](https://github.com/NeuQore/aws-fpga) branch **`cva6`** |
| CVA6 RTL | [NeuQore/cva6](https://github.com/NeuQore/cva6) branch **`f2-cva6`** at `$CVA6_REPO_DIR` |

Vivado pulls RTL via `gen_cva6_sources.py` from `$CVA6_REPO_DIR` (same as linux/trackers). Initialize CVA6 submodules once — see [cl_cva6_linux — CVA6 submodules](../cl_cva6_linux/README.md#0-cva6-submodules-once).

## Environment

```bash
export AWS_FPGA_REPO_DIR=/projects/prj1/sle-wajahat/aws-fpga
export CVA6_REPO_DIR=/projects/prj1/sle-wajahat/cva6
export CL_DIR=$AWS_FPGA_REPO_DIR/hdk/cl/examples/cl_cva6
export TARGET_CFG=cv32a6_ima_sv32_fpga
export AWS_DEFAULT_REGION=us-east-1
cd $AWS_FPGA_REPO_DIR
source hdk_setup.sh
source sdk_setup.sh
```

## Host flow (same pattern as linux)

1. Peek `MAGIC` (`0xC6A60001` for a cl_cva6 bitstream — **not** valid on the linux AGFI).
2. `CTRL.cpu_run = 0`, wait for HBM ready.
3. Burst firmware via BAR4 at PCIS offset `0x0010_0000_0000` (CVA6 `0x80000000`).
4. `CTRL.cpu_run = 1`, drain UART on BAR0.

Firmware uses **`ilp32`** (`riscv64-unknown-elf-gcc` with `-march=rv32imac_zicsr -mabi=ilp32`).

## Layout

```text
cl_cva6/
  build/           DCP flow artifacts (when built)
  firmware/        hello-world smoke (RV32)
  software/        host loader (when present)
```

For new work on F2, start from **`cl_cva6_linux`** or the software-only examples under [CVA6_F2_README.md](../CVA6_F2_README.md).
