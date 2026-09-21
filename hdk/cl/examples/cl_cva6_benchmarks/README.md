# CL_CVA6_BENCHMARKS — same F2 AGFI as cl_cva6_linux, different software

Sibling of [`cl_cva6_linux`](../cl_cva6_linux/README.md). **Hardware and AFI are unchanged.** This example only changes what you load into HBM: bare-metal kernels from [NeuQore/benchmarks](https://github.com/NeuQore/benchmarks).

Ecosystem index: [CVA6_F2_README.md](../CVA6_F2_README.md).

## Status

| | |
|--|--|
| AFI / AGFI | **Same as cl_cva6_linux:** `afi-06a08d518aae438a1` / **`agfi-0248c1f84010b03e9`** (`us-east-1`) |
| RTL | Same as `cl_cva6_linux` (MAGIC `0xC6A66401`, Device ID `0xF0C7`) |
| Benchmarks | **Vendored** tree at `benchmarks/` (copy of NeuQore/benchmarks **`cva6`**; not a git submodule) |
| Host loader | `software/runtime/run_cva6_benchmark --bin <test>.bin` |

Do **not** rebuild a DCP for this directory unless you intend a new AFI. Load the existing linux AGFI.

For cycle-window traces, use [`cl_cva6_trackers`](../cl_cva6_trackers/README.md) and AGFI **`agfi-03d44036bdd40848f`** — not this AGFI.

## Environment

```bash
export AWS_FPGA_REPO_DIR=/projects/prj1/sle-wajahat/aws-fpga
export CVA6_REPO_DIR=/projects/prj1/sle-wajahat/cva6
export CL_DIR=$AWS_FPGA_REPO_DIR/hdk/cl/examples/cl_cva6_benchmarks
export AWS_DEFAULT_REGION=us-east-1
cd $AWS_FPGA_REPO_DIR
source sdk_setup.sh
```

## Build kernels

The vendored tree is ready to build. To refresh from a standalone clone:

```bash
git clone -b cva6 https://github.com/NeuQore/benchmarks.git /projects/prj1/sle-wajahat/sle-benchmarks
# optional: rsync into $CL_DIR/benchmarks/
```

```bash
sudo apt-get install -y gcc-riscv64-unknown-elf
make -C $CL_DIR/benchmarks                    # all tests → tests/<name>/<name>.bin
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

Per-test `run.sh` scripts live under `benchmarks/tests/<name>/` and default to this AGFI.

## Tests

See [`benchmarks/README.md`](benchmarks/README.md). Names that need RVV, IMEXT, QSPI, or SDIO print `=== SKIP ===` on this CL.

## Layout

```
cl_cva6_benchmarks/
  design/          same RTL as cl_cva6_linux (reference; AGFI already built)
  software/        run_cva6_benchmark + run_benchmark.sh
  firmware/        hello-world smoke image
  benchmarks/      NeuQore/benchmarks (vendored)
  docs/            diagrams from cl_cva6_linux
```
