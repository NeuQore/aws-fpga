# CVA6 on AWS F2 — example CLs and NeuQore repos

These custom logic (CL) examples run the [CVA6](https://github.com/openhwgroup/cva6) RISC-V core on EC2 **F2** (`us-east-1` is the primary region for the prebuilt images below). They share the AWS Shell bring-up pattern: **AppPF BAR0** (OCL registers + UART drain) and **AppPF BAR4** (PCIS burst into HBM while `cpu_run=0`). There is **no XDMA** on F2 — do not use `fpga_dma` for HBM loads.

**HDK tree:** [NeuQore/aws-fpga](https://github.com/NeuQore/aws-fpga), branch **`cva6`** (`hdk/cl/examples/cl_cva6_*`).  
**CVA6 RTL fork:** [NeuQore/cva6](https://github.com/NeuQore/cva6), branch **`f2-cva6`** (tracker and F2-specific patches). Point Vivado at `$CVA6_REPO_DIR`; RTL is not vendored inside the CL directories.

## Two FPGA images (do not mix loaders)

| Family | MAGIC | PCIe device | AGFI (`us-east-1`) | Use for |
|--------|-------|-------------|---------------------|---------|
| **Linux / benchmarks / llama** | `0xC6A66401` | `0xF0C7` | **`agfi-0248c1f84010b03e9`** | [`cl_cva6_linux`](cl_cva6_linux/README.md), [`cl_cva6_benchmarks`](cl_cva6_benchmarks/README.md), [`cl_cva6_llama`](cl_cva6_llama/README.md) |
| **Cycle-window trackers** | `0xC6A66402` | `0xF0C8` | **`agfi-03d44036bdd40848f`** | [`cl_cva6_trackers`](cl_cva6_trackers/README.md) only |

Loading the wrong AGFI makes host tools fail the MAGIC check or behave as if registers/trace BRAMs do not exist. Trackers reuse benchmark **kernels** but must use [`cl_cva6_trackers/run.sh`](cl_cva6_trackers/run.sh) (or set `AGFI=agfi-03d44036bdd40848f`), not `benchmarks/tests/_run_one.sh` (linux AGFI default).

## Example directories

| Directory | Role |
|-----------|------|
| [`cl_cva6`](cl_cva6/README.md) | RV32 baseline (reference vs linux); not the image used for Linux or benchmarks |
| [`cl_cva6_linux`](cl_cva6_linux/README.md) | RV64 SoC + Linux/OpenSBI/BusyBox bring-up handbook |
| [`cl_cva6_benchmarks`](cl_cva6_benchmarks/README.md) | Same AGFI as linux; bare-metal kernels from NeuQore/benchmarks |
| [`cl_cva6_llama`](cl_cva6_llama/README.md) | Same AGFI as linux; interactive llama.cpp via HBM mailbox |
| [`cl_cva6_trackers`](cl_cva6_trackers/README.md) | Separate AGFI; RVFI + AXI + L1 trace CSVs in a CPU-cycle window |

Software-only siblings (`cl_cva6_benchmarks`, `cl_cva6_llama`) keep a **`design/`** copy of the linux RTL for reference; **do not rebuild a DCP** unless you intend a new AFI.

## External repositories (branch **`cva6`** unless noted)

| Repo | Purpose |
|------|---------|
| [NeuQore/benchmarks](https://github.com/NeuQore/benchmarks) | Bare-metal tests (`make`, per-test `run.sh`); vendored under `cl_cva6_benchmarks/benchmarks/` in aws-fpga |
| [NeuQore/llama.cpp](https://github.com/NeuQore/llama.cpp) | F2 cross-build + `setup.sh` for llama |
| [NeuQore/linux](https://github.com/NeuQore/linux) | Linux v6.12 + `cl_cva6_f2` fragment |
| [NeuQore/opensbi](https://github.com/NeuQore/opensbi) | OpenSBI v1.6 + F2 single-hart patches |
| [NeuQore/busybox](https://github.com/NeuQore/busybox) | BusyBox 1.37.0 + `cl_cva6_f2_defconfig` (static initramfs, not Buildroot) |

Firmware paths are configured in [`cl_cva6_linux/linux/sources.env.sh`](cl_cva6_linux/linux/sources.env.sh) (`NEUQORE_SRC_ROOT`, default sibling checkouts under `/projects/prj1/sle-wajahat`).

## Typical workspace layout

```text
/projects/prj1/sle-wajahat/
  aws-fpga/          NeuQore/aws-fpga @ cva6
  cva6/              NeuQore/cva6 @ f2-cva6
  sle-benchmarks/    NeuQore/benchmarks @ cva6  (optional; also vendored in CL)
  llama.cpp/         NeuQore/llama.cpp @ cva6
  linux/ opensbi/ busybox/   NeuQore forks @ cva6
```

### Environment (all examples)

```bash
export AWS_FPGA_REPO_DIR=/projects/prj1/sle-wajahat/aws-fpga
export CVA6_REPO_DIR=/projects/prj1/sle-wajahat/cva6
export AWS_DEFAULT_REGION=us-east-1
cd $AWS_FPGA_REPO_DIR
source hdk_setup.sh
source sdk_setup.sh
```

Set **`CL_DIR`** to the example you are using **before** relying on paths in that example’s README.

## Upstream AWS HDK

Package-only and other upstream HDK fixes may live on [aws/aws-fpga](https://github.com/aws/aws-fpga) branch **`f2`** separately from the NeuQore **`cva6`** CL ecosystem branch.
