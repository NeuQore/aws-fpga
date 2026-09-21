#!/usr/bin/env bash
set -euo pipefail

CL_DIR="${CL_DIR:-/projects/prj1/sle-wajahat/aws-fpga/hdk/cl/examples/cl_cva6_linux}"
cd "$CL_DIR/linux"

echo "== packages =="
sudo apt-get install -y \
  gcc-riscv64-linux-gnu device-tree-compiler \
  build-essential bc bison flex libssl-dev libelf-dev

echo "== fetch sources =="
./fetch_sources.sh

echo "== build OpenSBI + Linux + BusyBox =="
./build_linux.sh

echo "== rebuild host loader =="
make -C "$CL_DIR/software/runtime"

echo "== boot Linux on FPGA =="
sudo "$CL_DIR/software/runtime/hello_cva6_linux" \
  --bin "$CL_DIR/linux/out/cl_cva6_linux.bin" \
  --uart-idle-ms 120000
