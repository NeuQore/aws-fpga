#!/usr/bin/env bash
set -euo pipefail

export AWS_FPGA_REPO_DIR="${AWS_FPGA_REPO_DIR:-/projects/prj1/sle-wajahat/aws-fpga}"
if [[ ! -r "${SDK_DIR:-}/userspace/include" ]]; then
  export SDK_DIR="$AWS_FPGA_REPO_DIR/sdk"
fi
export CL_DIR="${CL_DIR:-$AWS_FPGA_REPO_DIR/hdk/cl/examples/cl_cva6_benchmarks}"
AGFI="${AGFI:-agfi-0248c1f84010b03e9}"
SLOT="${SLOT:-0}"
IDLE_MS="${UART_IDLE_MS:-120000}"
MAX_MS="${UART_MAX_MS:-300000}"

BENCH_ROOT="${SLE_BENCHMARKS:-$CL_DIR/benchmarks}"
LOGDIR="${LOGDIR:-$CL_DIR/software/runtime/logs}"
mkdir -p "$LOGDIR"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <test_name> [more names...]"
  echo "example: $0 bpu_1_loop_branch coremark"
  exit 1
fi

cd "$AWS_FPGA_REPO_DIR"
# shellcheck disable=SC1091
source sdk_setup.sh >/dev/null

make -C "$CL_DIR/software/runtime"

echo "== load AGFI $AGFI (same as cl_cva6_linux) =="
sudo fpga-load-local-image -S "$SLOT" -I "$AGFI"

for name in "$@"; do
  bin="$BENCH_ROOT/tests/$name/${name}.bin"
  if [[ ! -f "$bin" ]]; then
    echo "== build $name =="
    make -C "$BENCH_ROOT/tests/$name"
  fi
  log="$LOGDIR/${name}.log"
  echo "== run $name (log $log) =="
  sudo "$CL_DIR/software/runtime/run_cva6_benchmark" \
    --bin "$bin" --uart-idle-ms "$IDLE_MS" --uart-max-ms "$MAX_MS" --log "$log"
  sudo chmod a+r "$log" 2>/dev/null || true
done
