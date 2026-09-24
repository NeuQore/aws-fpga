#!/usr/bin/env bash
# Boot cl_cva6_linux.bin on the *trackers* AGFI (RVFI + events + L1) for MMU/debug visibility.
# Uses the same HBM @ 0x80000000 load path as cl_cva6_linux; MAGIC is 0xC6A66402 on this CL.
#
#   ./boot_linux.sh
#   WINDOW_END=0 STOP_ON_EXCP=0 ./boot_linux.sh   # default: full kernel window after OpenSBI
#   STOP_ON_EXCP=1 ./boot_linux.sh              # freezes at first trap (~OpenSBI only)
#   SKIP_AGFI_LOAD=1 ./boot_linux.sh
set -euo pipefail

CL_DIR="$(cd "$(dirname "$0")" && pwd)"
# Sibling checkout — do not use env AWS_FPGA_REPO_DIR (sdk_setup may point at /home/ubuntu/…).
LINUX_DIR="$(cd "$CL_DIR/../cl_cva6_linux" && pwd)"
export AWS_FPGA_REPO_DIR="$(cd "$CL_DIR/../../../.." && pwd)"
BIN="${LINUX_BIN:-$LINUX_DIR/linux/out/cl_cva6_linux.bin}"

export SDK_DIR="$AWS_FPGA_REPO_DIR/sdk"
export LD_LIBRARY_PATH="${SDK_DIR}/lib/so:${LD_LIBRARY_PATH:-}"

AGFI="${AGFI:-agfi-03d44036bdd40848f}"
SLOT="${SLOT:-0}"
WINDOW_START="${WINDOW_START:-0}"
# 0 = no cycle upper bound (host programs TRACE_END=UINT64_MAX; BRAM still caps at 1024 rows)
WINDOW_END="${WINDOW_END:-0}"
# CSVs are written only after UART drain ends (idle = ms with no UART bytes).
UART_IDLE_MS="${UART_IDLE_MS:-120000}"
UART_MAX_MS="${UART_MAX_MS:-600000}"
# After OpenSBI banner, host uses this idle cap (was 20s — too short post-MMU @234).
POST_OPENSBI_IDLE_MS="${POST_OPENSBI_IDLE_MS:-120000}"
STOP_ON_EXCP="${STOP_ON_EXCP:-0}"
# CLEAR FIFOs when this UART substring appears (post-SATP probe in head.S)
TRACE_UART_TRIGGER="${TRACE_UART_TRIGGER:-001!>}"

LOGDIR="${LOGDIR:-$CL_DIR/software/runtime/logs}"
TRACEDIR="${TRACEDIR:-$CL_DIR/software/runtime/traces/linux_boot}"
LOG="$LOGDIR/linux_boot.log"
TEE_LOG="$LOGDIR/linux_boot_console.log"
mkdir -p "$LOGDIR" "$TRACEDIR"

if [[ ! -f "$BIN" ]]; then
  echo "Missing $BIN; run $LINUX_DIR/linux/build_linux.sh first" >&2
  exit 1
fi

cd "$AWS_FPGA_REPO_DIR"
# shellcheck disable=SC1091
source sdk_setup.sh >/dev/null
make -C "$CL_DIR/software/runtime"

if [[ "${SKIP_AGFI_LOAD:-0}" != "1" ]]; then
  echo "== $(date -Is) load trackers AGFI $AGFI (not cl_cva6_linux agfi-0248…) =="
  sudo fpga-load-local-image -S "$SLOT" -I "$AGFI"
fi

EXTRA=()
if [[ "$STOP_ON_EXCP" == "1" ]]; then
  EXTRA+=(--stop-on-exception)
fi

echo "== $(date -Is) Linux boot bin=$BIN window=[$WINDOW_START,$WINDOW_END) trigger=$TRACE_UART_TRIGGER =="
stdbuf -oL -eL sudo "$CL_DIR/software/runtime/run_cva6_trackers" \
  --bin "$BIN" \
  --linux-boot \
  --linux-boot-trace-trigger "$TRACE_UART_TRIGGER" \
  --post-opensbi-idle-ms "$POST_OPENSBI_IDLE_MS" \
  --window-start "$WINDOW_START" \
  --window-end "$WINDOW_END" \
  --trace-dir "$TRACEDIR" \
  --uart-idle-ms "$UART_IDLE_MS" \
  --uart-max-ms "$UART_MAX_MS" \
  --log "$LOG" \
  "${EXTRA[@]}" 2>&1 | tee "$TEE_LOG"

sudo chmod -R a+r "$LOG" "$TEE_LOG" "$TRACEDIR" 2>/dev/null || true

echo ""
echo "UART:    $LOG  (and $TEE_LOG)"
echo "Traces:  $TRACEDIR/instr.csv icache.csv dcache.csv events.csv l1.csv"
echo "Waits up to ${UART_MAX_MS}ms total, ${POST_OPENSBI_IDLE_MS}ms idle after OpenSBI (override with env)."
echo "After JKBPTUV001!>@234… wait for 'Linux version' or 'dumping traces' (or Ctrl+C)."
echo "Trace re-arm when UART contains: $TRACE_UART_TRIGGER"
echo "Shorter dump after OpenSBI only: POST_OPENSBI_IDLE_MS=20000 ./boot_linux.sh"
