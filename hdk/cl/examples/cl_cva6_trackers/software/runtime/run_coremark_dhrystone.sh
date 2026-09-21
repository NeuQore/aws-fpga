#!/usr/bin/env bash
# Run coremark + dhrystone on cl_cva6_trackers with a user-defined cycle window.
set -euo pipefail

export AWS_FPGA_REPO_DIR="${AWS_FPGA_REPO_DIR:-/projects/prj1/sle-wajahat/aws-fpga}"
export SDK_DIR="${SDK_DIR:-$AWS_FPGA_REPO_DIR/sdk}"
export CL_DIR="${CL_DIR:-$AWS_FPGA_REPO_DIR/hdk/cl/examples/cl_cva6_trackers}"
export SLE_BENCHMARKS="${SLE_BENCHMARKS:-$CL_DIR/benchmarks}"
export WINDOW_START="${WINDOW_START:-2000}"
export WINDOW_END="${WINDOW_END:-4000}"

cd "$CL_DIR/software/runtime"
chmod +x ./run_benchmark.sh
./run_benchmark.sh coremark dhrystone
echo "logs:"
ls -l logs/coremark.log logs/dhrystone.log
echo "traces:"
ls -l traces/coremark traces/dhrystone
