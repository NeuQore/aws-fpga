#!/usr/bin/env bash
# Load cl_cva6_linux AGFI and run coremark + dhrystone, writing one log each.
set -euo pipefail

export AWS_FPGA_REPO_DIR="${AWS_FPGA_REPO_DIR:-/projects/prj1/sle-wajahat/aws-fpga}"
export SDK_DIR="${SDK_DIR:-$AWS_FPGA_REPO_DIR/sdk}"
export CL_DIR="${CL_DIR:-$AWS_FPGA_REPO_DIR/hdk/cl/examples/cl_cva6_benchmarks}"
export SLE_BENCHMARKS="${SLE_BENCHMARKS:-/projects/prj1/sle-wajahat/sle-benchmarks}"
export AGFI="${AGFI:-agfi-0248c1f84010b03e9}"

cd "$CL_DIR/software/runtime"
chmod +x ./run_benchmark.sh
./run_benchmark.sh coremark dhrystone
echo "logs:"
ls -l logs/coremark.log logs/dhrystone.log
