#!/usr/bin/env bash
set -euo pipefail

export AWS_FPGA_REPO_DIR="${AWS_FPGA_REPO_DIR:-/projects/prj1/sle-wajahat/aws-fpga}"
if [[ ! -r "${SDK_DIR:-}/userspace/include" ]]; then
  export SDK_DIR="$AWS_FPGA_REPO_DIR/sdk"
fi
export CL_DIR="${CL_DIR:-$AWS_FPGA_REPO_DIR/hdk/cl/examples/cl_cva6_trackers}"
SLOT="${SLOT:-0}"
IDLE_MS="${UART_IDLE_MS:-120000}"
MAX_MS="${UART_MAX_MS:-300000}"
WINDOW_START="${WINDOW_START:-2000}"
WINDOW_END="${WINDOW_END:-4000}"

BENCH_ROOT="${SLE_BENCHMARKS:-$CL_DIR/benchmarks}"
LOGDIR="${LOGDIR:-$CL_DIR/software/runtime/logs}"
TRACEDIR="${TRACEDIR:-$CL_DIR/software/runtime/traces}"
mkdir -p "$LOGDIR" "$TRACEDIR"

AGFI="${AGFI:-agfi-03d44036bdd40848f}"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <test_name> [more names...]"
  echo "example: WINDOW_START=2000 WINDOW_END=4000 $0 bpu_1_loop_branch"
  echo "Or: $CL_DIR/run.sh"
  exit 1
fi

cd "$AWS_FPGA_REPO_DIR"
# shellcheck disable=SC1091
source sdk_setup.sh >/dev/null

make -C "$CL_DIR/software/runtime"

if [[ "${SKIP_AGFI_LOAD:-0}" != "1" && -n "${AGFI:-}" ]]; then
  echo "== load AGFI $AGFI =="
  sudo fpga-load-local-image -S "$SLOT" -I "$AGFI"
fi

for name in "$@"; do
  bin="$BENCH_ROOT/tests/$name/${name}.bin"
  if [[ ! -f "$bin" ]]; then
    echo "== build $name =="
    make -C "$BENCH_ROOT/tests/$name"
  fi
  log="$LOGDIR/${name}.log"
  tdir="$TRACEDIR/$name"
  mkdir -p "$tdir"
  echo "== run $name window=[$WINDOW_START,$WINDOW_END) log=$log traces=$tdir =="
  sudo "$CL_DIR/software/runtime/run_cva6_trackers" \
    --bin "$bin" \
    --window-start "$WINDOW_START" \
    --window-end "$WINDOW_END" \
    --trace-dir "$tdir" \
    --uart-idle-ms "$IDLE_MS" --uart-max-ms "$MAX_MS" --log "$log"
  sudo chmod -R a+r "$log" "$tdir" 2>/dev/null || true
  dump="$BENCH_ROOT/tests/$name/${name}.dump"
  if [[ -f "$dump" ]]; then
    cp -f "$dump" "$tdir/${name}.dump"
    echo "== matching disassembly: $tdir/${name}.dump =="
  fi
done
