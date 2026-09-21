#!/usr/bin/env bash
# Load the latest trackers AGFI (agfi-03d44036bdd40848f / afi-0351f913d541da257)
# and dump instr/icache/dcache/events/l1 CSVs.
#
#   ./run.sh                         # bpu_1_loop_branch, window [2000, 4000)
#   ./run.sh bpu_1_loop_branch
#   WINDOW_START=2000 WINDOW_END=2500 ./run.sh bpu_1_loop_branch
#   SKIP_AGFI_LOAD=1 ./run.sh ...    # FPGA already loaded
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
export AWS_FPGA_REPO_DIR="${AWS_FPGA_REPO_DIR:-/projects/prj1/sle-wajahat/aws-fpga}"
export CL_DIR="${CL_DIR:-$ROOT}"
export AGFI="${AGFI:-agfi-03d44036bdd40848f}"
export WINDOW_START="${WINDOW_START:-0}"
export WINDOW_END="${WINDOW_END:-4000}"
SLOT="${SLOT:-0}"

if [[ $# -eq 0 ]]; then
  set -- bpu_1_loop_branch
fi

exec "$CL_DIR/software/runtime/run_benchmark.sh" "$@"
