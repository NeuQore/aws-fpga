# CL_CVA6_LLAMA — interactive llama.cpp on the same F2 AGFI

Sibling of [`cl_cva6_benchmarks`](../cl_cva6_benchmarks/README.md) and [`cl_cva6_linux`](../cl_cva6_linux/README.md). **Hardware and AFI are unchanged.** This example only changes the host loader and the HBM image (`llama.bin` from [sle-benchmarks `tests/llama`](https://github.com/SilverLining-EDA/sle-benchmarks/blob/main/tests/llama/README.md)).

## Status

| | |
|--|--|
| AFI / AGFI | **Same as cl_cva6_linux:** `afi-06a08d518aae438a1` / **`agfi-0248c1f84010b03e9`** (`us-east-1`) |
| RTL | Copy of `cl_cva6_linux` (MAGIC `0xC6A66401`) — do **not** rebuild a DCP |
| Host | `software/runtime/run_cva6_llama` — logo, live UART, stdin prompts |
| Image | `sle-benchmarks/tests/llama/llama.bin` |

## Why a mailbox instead of UART RX

`host_uart` on this AGFI is **CVA6 → host only**. PCIS/BAR4 also cannot write HBM while `cpu_run=1`. So each prompt is:

1. You type on the host (realtime stdin).
2. Host holds CVA6 in reset (`CTRL=0`).
3. Host writes the prompt into an HBM mailbox at CVA6 `0xBFE80000`.
4. Host releases reset. CVA6 reloads the embedded GGUF, prints the logo, generates, then prints `>>> ` and waits.

Decode at 62.5 MHz is slow; TinyStories-class GGUF only.

## Step by step

Toolchains: [`llama.cpp/setup.sh`](https://github.com/SilverLining-EDA/llama.cpp/blob/master/setup.sh).

```bash
export AWS_FPGA_REPO_DIR=/projects/prj1/sle-wajahat/aws-fpga
export CL_DIR=$AWS_FPGA_REPO_DIR/hdk/cl/examples/cl_cva6_llama
cd $AWS_FPGA_REPO_DIR
source sdk_setup.sh

# 1. Toolchains + GGUF + llama.bin
cd /projects/prj1/sle-wajahat/llama.cpp && ./setup.sh
source /projects/prj1/sle-wajahat/tools/cva6-env.sh
cd /projects/prj1/sle-wajahat/sle-benchmarks/tests/llama
# place model.gguf first (see tests/llama/README.md)
make

# 2. Interactive session (loads AGFI unless SKIP_AGFI_LOAD=1)
cd $CL_DIR/software/runtime
chmod +x run_llama.sh
./run_llama.sh
# SKIP_AGFI_LOAD=1 ./run_llama.sh
```

After CVA6 prints `>>> `, type a prompt and press Enter. `/bye` or Ctrl-D ends the session.

```
llama.cpp  —  CVA6 on AWS F2
     /\_____/\
    ...
>>> Hello
<generated tokens>
>>>
```

Keep prompts short. Dummy GGUF vocab only tokenizes `Hello` reliably. UART log: `software/runtime/llama_session.log`.

## Layout

```
cl_cva6_llama/
  design/     same RTL as cl_cva6_linux (reference; AGFI already built)
  software/   run_cva6_llama + run_llama.sh
  firmware/   hello-world smoke image
```
