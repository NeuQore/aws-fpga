# NeuQore firmware repos (sibling to aws-fpga). Override for other layouts.
NEUQORE_SRC_ROOT="${NEUQORE_SRC_ROOT:-/projects/prj1/sle-wajahat}"
export NEUQORE_LINUX="${NEUQORE_LINUX:-$NEUQORE_SRC_ROOT/linux}"
export NEUQORE_OPENSBI="${NEUQORE_OPENSBI:-$NEUQORE_SRC_ROOT/opensbi}"
export NEUQORE_BUSYBOX="${NEUQORE_BUSYBOX:-$NEUQORE_SRC_ROOT/busybox}"
