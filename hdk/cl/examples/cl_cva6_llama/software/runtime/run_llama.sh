#!/usr/bin/env bash
set -euo pipefail

export AWS_FPGA_REPO_DIR="${AWS_FPGA_REPO_DIR:-/projects/prj1/sle-wajahat/aws-fpga}"
if [[ ! -r "${SDK_DIR:-}/userspace/include" ]]; then
  export SDK_DIR="$AWS_FPGA_REPO_DIR/sdk"
fi
export CL_DIR="${CL_DIR:-$AWS_FPGA_REPO_DIR/hdk/cl/examples/cl_cva6_llama}"
AGFI="${AGFI:-agfi-0248c1f84010b03e9}"
SLOT="${SLOT:-0}"
SO="${SDK_DIR}/userspace/lib/so"
SLE_BENCHMARKS="${SLE_BENCHMARKS:-/projects/prj1/sle-wajahat/sle-benchmarks}"
BIN="${1:-$SLE_BENCHMARKS/tests/llama/llama.bin}"
NPRED="${NPREDICT:-32}"
LOG="${LOG:-$CL_DIR/software/runtime/llama_session.log}"

cd "$AWS_FPGA_REPO_DIR"
# shellcheck disable=SC1091
source sdk_setup.sh >/dev/null

if [[ ! -f "$BIN" ]]; then
  echo "== build llama.bin =="
  make -C "$SLE_BENCHMARKS/tests/llama"
  BIN="$SLE_BENCHMARKS/tests/llama/llama.bin"
fi

echo "== build host loader =="
make -C "$CL_DIR/software/runtime"

if [[ "${SKIP_AGFI_LOAD:-0}" != "1" ]]; then
  echo "== load AGFI $AGFI =="
  sudo fpga-load-local-image -S "$SLOT" -I "$AGFI"
fi

echo "== interactive llama (bin=$BIN) =="
echo "Type a prompt after CVA6 prints >>>   /bye to quit."
sudo env LD_LIBRARY_PATH="$SO${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$CL_DIR/software/runtime/run_cva6_llama" --bin "$BIN" --n "$NPRED" --log "$LOG"
sudo chmod a+r "$LOG" 2>/dev/null || true
