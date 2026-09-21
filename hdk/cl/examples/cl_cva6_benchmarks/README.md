# CL_CVA6_BENCHMARKS — same F2 AGFI as cl_cva6_linux, different software

Sibling of [`cl_cva6_linux`](../cl_cva6_linux/README.md). **Hardware and AFI are unchanged.** This example only changes what you load into HBM: bare-metal kernels from [sle-benchmarks](https://github.com/SilverLining-EDA/sle-benchmarks).

## Status

| | |
|--|--|
| AFI / AGFI | **Same as cl_cva6_linux:** `afi-06a08d518aae438a1` / **`agfi-0248c1f84010b03e9`** (`us-east-1`) |
| RTL | Copy of `cl_cva6_linux` (MAGIC `0xC6A66401`, Device ID `0xF0C7`) |
| Benchmarks | git submodule `benchmarks/` → `git@github.com:SilverLining-EDA/sle-benchmarks.git` |
| Host loader | `software/runtime/run_cva6_benchmark --bin <test>.bin` |

Do **not** rebuild a DCP for this directory unless you intend a new AFI. Load the existing linux AGFI.

## Environment

```bash
export AWS_FPGA_REPO_DIR=/projects/prj1/sle-wajahat/aws-fpga
export CVA6_REPO_DIR=/projects/prj1/sle-wajahat/cva6
export CL_DIR=$AWS_FPGA_REPO_DIR/hdk/cl/examples/cl_cva6_benchmarks
export AWS_DEFAULT_REGION=us-east-1
cd $AWS_FPGA_REPO_DIR
source sdk_setup.sh
```

## Fetch and build kernels

```bash
cd $CL_DIR
git submodule update --init benchmarks
sudo apt-get install -y gcc-riscv64-unknown-elf
make -C benchmarks                    # all tests → tests/<name>/<name>.bin
```

## Load AFI and run one test

```bash
sudo fpga-load-local-image -S 0 -I agfi-0248c1f84010b03e9
make -C $CL_DIR/software/runtime
chmod +x $CL_DIR/software/runtime/run_benchmark.sh
$CL_DIR/software/runtime/run_benchmark.sh bpu_1_loop_branch
```

Or by hand:

```bash
sudo $CL_DIR/software/runtime/run_cva6_benchmark \
  --bin $CL_DIR/benchmarks/tests/coremark/coremark.bin \
  --uart-idle-ms 60000
```

Host load remap is the same as linux: CVA6 `0x80000000` is PCIS/BAR4 offset `0x0010_0000_0000`. UART is output-only on OCL.

## Tests

See [`benchmarks/README.md`](benchmarks/README.md). Names that need RVV, IMEXT, QSPI, or SDIO print `=== SKIP ===` on this CL.

## Layout

```
cl_cva6_benchmarks/
  design/          same RTL as cl_cva6_linux (reference; AGFI already built)
  software/        run_cva6_benchmark + run_benchmark.sh
  firmware/        hello-world smoke image
  benchmarks/      sle-benchmarks submodule
  docs/            diagrams from cl_cva6_linux
```
