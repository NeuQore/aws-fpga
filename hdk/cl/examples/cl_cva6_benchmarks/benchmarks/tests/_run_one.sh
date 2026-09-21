#!/usr/bin/env bash
# Shared FPGA run helper. Invoked as: tests/_run_one.sh <test_name>
set -euo pipefail

NAME="${1:?usage: $0 <test_name>}"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
DIR="$TESTS_DIR/$NAME"
ROOT="$(cd "$TESTS_DIR/.." && pwd)"

export AWS_FPGA_REPO_DIR="${AWS_FPGA_REPO_DIR:-/projects/prj1/sle-wajahat/aws-fpga}"
export SDK_DIR="${SDK_DIR:-$AWS_FPGA_REPO_DIR/sdk}"
export CL_DIR="${CL_DIR:-$AWS_FPGA_REPO_DIR/hdk/cl/examples/cl_cva6_benchmarks}"
AGFI="${AGFI:-agfi-0248c1f84010b03e9}"
SLOT="${SLOT:-0}"
IDLE_MS="${UART_IDLE_MS:-30000}"
LOADER="$CL_DIR/software/runtime/run_cva6_benchmark"
LOG="$DIR/${NAME}.log"
SO="${SDK_DIR}/userspace/lib/so"

if [[ ! -d "$DIR" ]]; then
  echo "ERROR: no test directory $DIR" >&2
  exit 1
fi

echo "== build $NAME =="
make -C "$DIR"

if [[ ! -x "$LOADER" ]]; then
  make -C "$CL_DIR/software/runtime"
fi

if [[ "${SKIP_AGFI_LOAD:-0}" != "1" ]]; then
  echo "== load AGFI $AGFI =="
  sudo fpga-load-local-image -S "$SLOT" -I "$AGFI"
fi

echo "== run $NAME (UART+host log: $LOG) =="
sudo env LD_LIBRARY_PATH="$SO${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$LOADER" --bin "$DIR/${NAME}.bin" --uart-idle-ms "$IDLE_MS" --log "$LOG"
sudo chmod a+r "$LOG" 2>/dev/null || true
echo "== wrote $LOG =="
