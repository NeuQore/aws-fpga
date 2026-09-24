#!/usr/bin/env bash
set -euo pipefail

REPO=/projects/prj1/sle-wajahat/aws-fpga
CL_DIR=$REPO/hdk/cl/examples/cl_cva6_linux
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export SDK_DIR="$REPO/sdk"
export LD_LIBRARY_PATH="${SDK_DIR}/lib/so:${LD_LIBRARY_PATH:-}"

AGFI="${AGFI:-agfi-0248c1f84010b03e9}"
BIN="$CL_DIR/linux/out/cl_cva6_linux.bin"
LOG="$CL_DIR/linux/out/last_boot.log"
LOADER="$CL_DIR/software/runtime/hello_cva6_linux"
if [[ ! -f "$BIN" ]]; then
  echo "Missing $BIN; run $CL_DIR/linux/build_linux.sh first" >&2
  exit 1
fi
make -C "$CL_DIR/software/runtime"

echo "== $(date -Is) load AGFI $AGFI =="
sudo fpga-load-local-image -S 0 -I "$AGFI"

echo "== $(date -Is) boot $BIN =="
# Line-buffer loader stdout/stderr so tmux + tee show output while boot runs
stdbuf -oL -eL sudo "$LOADER" --bin "$BIN" --uart-idle-ms "${UART_IDLE_MS:-600000}" 2>&1 | tee "$LOG"
