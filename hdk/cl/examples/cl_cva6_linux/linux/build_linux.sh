#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=sources.env.sh
source "$ROOT/sources.env.sh"
OUT="${OUT_DIR:-$ROOT/out}"
JOBS="${JOBS:-$(nproc)}"
CROSS_COMPILE="${CROSS_COMPILE:-riscv64-linux-gnu-}"

LINUX="$NEUQORE_LINUX"
OPENSBI="$NEUQORE_OPENSBI"
BUSYBOX="$NEUQORE_BUSYBOX"
LINUX_OUT="$OUT/linux"
OPENSBI_OUT="$OUT/opensbi"
BUSYBOX_OUT="$OUT/busybox"
ROOTFS="$OUT/rootfs"
DTB="$OUT/cl_cva6_linux.dtb"

for dir in "$LINUX" "$OPENSBI" "$BUSYBOX"; do
  [[ -d "$dir" ]] || {
    echo "Missing $dir; run $ROOT/fetch_sources.sh first" >&2
    exit 1
  }
done
command -v "${CROSS_COMPILE}gcc" >/dev/null || {
  echo "Missing ${CROSS_COMPILE}gcc (install gcc-riscv64-linux-gnu)" >&2
  exit 1
}
command -v dtc >/dev/null || {
  echo "Missing dtc (install device-tree-compiler)" >&2
  exit 1
}

mkdir -p "$OUT" "$LINUX_OUT" "$OPENSBI_OUT" "$BUSYBOX_OUT" "$ROOTFS"

# #region agent log
_dbg() {
  local hyp="$1" msg="$2" extra="${3-}"
  [[ -n "$extra" ]] || extra='{}'
  python3 -c '
import json, sys, time
open("/projects/prj1/sle-wajahat/.cursor/debug-76b74b.log", "a").write(json.dumps({
  "sessionId": "76b74b",
  "hypothesisId": sys.argv[1],
  "location": "build_linux.sh",
  "message": sys.argv[2],
  "data": json.loads(sys.argv[3]),
  "timestamp": int(time.time() * 1000),
  "runId": "busybox-build",
}) + "\n")
' "$hyp" "$msg" "$extra" || true
}
_dbg_cfg() {
  python3 -c '
import json, re, sys, time
path, hyp, msg = sys.argv[1], sys.argv[2], sys.argv[3]
keys = ["CONFIG_SHA1_HWACCEL", "CONFIG_SHA256_HWACCEL", "CONFIG_STATIC", "CONFIG_TC"]
text = open(path).read() if __import__("os").path.exists(path) else ""
vals = {}
for k in keys:
    m = re.search(r"^" + k + r"=.*$", text, re.M)
    n = re.search(r"^# " + k + r" is not set$", text, re.M)
    vals[k] = m.group(0) if m else (n.group(0) if n else "missing")
open("/projects/prj1/sle-wajahat/.cursor/debug-76b74b.log", "a").write(json.dumps({
  "sessionId": "76b74b",
  "hypothesisId": hyp,
  "location": "build_linux.sh",
  "message": msg,
  "data": vals,
  "timestamp": int(time.time() * 1000),
  "runId": "busybox-build",
}) + "\n")
' "$1" "$2" "$3" || true
}
# #endregion

echo "== Device tree =="
dtc -I dts -O dtb -o "$DTB" "$ROOT/cl_cva6_linux.dts"

echo "== BusyBox static initramfs =="
# glibc is built with the A extension. HBM never completes LR/SC, so a
# glibc busybox hangs in the first userspace lock. Link the no-A musl instead.
MUSL_GCC="$OUT/musl/bin/riscv64-musl-gcc"
BB_CC=()
if [[ -x "$MUSL_GCC" ]]; then
  BB_CC=(CC="$MUSL_GCC")
fi
make -C "$BUSYBOX" O="$BUSYBOX_OUT" ARCH=riscv \
  CROSS_COMPILE="$CROSS_COMPILE" "${BB_CC[@]}" cl_cva6_f2_defconfig
# #region agent log
_dbg_cfg "$BUSYBOX_OUT/.config" "A" "after_cl_cva6_f2_defconfig"
# #endregion
make -C "$BUSYBOX" O="$BUSYBOX_OUT" ARCH=riscv \
  CROSS_COMPILE="$CROSS_COMPILE" "${BB_CC[@]}" -j"$JOBS"
# #region agent log
_dbg "A" "busybox_make_ok" "$(python3 -c 'import json,os; p="'"$BUSYBOX_OUT"'"; print(json.dumps({"hash_o":os.path.exists(p+"/libbb/hash_md5_sha.o"),"enable_sha1_hwaccel":open(p+"/include/autoconf.h").read().count("#define ENABLE_SHA1_HWACCEL 1")}))')"
# #endregion
make -C "$BUSYBOX" O="$BUSYBOX_OUT" ARCH=riscv \
  CROSS_COMPILE="$CROSS_COMPILE" "${BB_CC[@]}" CONFIG_PREFIX="$ROOTFS" install
install -m 0755 "$ROOT/init" "$ROOTFS/init"
mkdir -p "$ROOTFS"/{dev,proc,sys,tmp}
# Device nodes cannot be created on this filesystem. The kernel opens
# /dev/console before /init (and before devtmpfs), so list them for gen_init_cpio.
DEVNODES="$OUT/devnodes.list"
cat > "$DEVNODES" <<'EOF'
nod /dev/console 622 0 0 c 5 1
nod /dev/null 666 0 0 c 1 3
EOF

echo "== Linux kernel + embedded initramfs =="
make -C "$LINUX" O="$LINUX_OUT" ARCH=riscv \
  CROSS_COMPILE="$CROSS_COMPILE" defconfig
"$LINUX/scripts/kconfig/merge_config.sh" -m -O "$LINUX_OUT" \
  "$LINUX_OUT/.config" "$ROOT/kernel.config.fragment"
{
  echo "CONFIG_INITRAMFS_SOURCE=\"$ROOTFS $DEVNODES\""
  echo 'CONFIG_INITRAMFS_ROOT_UID=0'
  echo 'CONFIG_INITRAMFS_ROOT_GID=0'
} >> "$LINUX_OUT/.config"
make -C "$LINUX" O="$LINUX_OUT" ARCH=riscv \
  CROSS_COMPILE="$CROSS_COMPILE" olddefconfig
make -C "$LINUX" O="$LINUX_OUT" ARCH=riscv \
  CROSS_COMPILE="$CROSS_COMPILE" syncconfig
grep -q '^CONFIG_CVA6_F2_NO_AMO=y$' "$LINUX_OUT/.config" || {
  echo "F2 Linux build requires CONFIG_CVA6_F2_NO_AMO=y" >&2
  exit 1
}
# #region agent log
python3 -c '
import json, re, time
path = "'"$LINUX_OUT"'/.config"
text = open(path).read()
def cfg(k):
    m = re.search(r"^" + k + r"=(.*)$", text, re.M)
    return m.group(1) if m else None
open("/projects/prj1/sle-wajahat/.cursor/debug-d59eb7.log", "a").write(json.dumps({
  "sessionId": "d59eb7",
  "hypothesisId": "H1",
  "location": "build_linux.sh",
  "message": "pre_image_config",
  "data": {
    "PGTABLE_LEVELS": cfg("CONFIG_PGTABLE_LEVELS"),
    "CVA6_F2_NO_AMO": cfg("CONFIG_CVA6_F2_NO_AMO"),
    "note": "Sv39 on F2 via CVA6_F2_NO_AMO satp_mode + no4lvl, not CONFIG_PGTABLE_LEVELS=3",
  },
  "timestamp": int(time.time() * 1000),
  "runId": "build",
}) + "\n")
' || true
# #endregion
make -C "$LINUX" O="$LINUX_OUT" ARCH=riscv \
  CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" Image

echo "== OpenSBI fw_payload =="
# #region agent log
_dbg "F" "opensbi_make" '{"hartid_patch":1}'
# #endregion
make -C "$OPENSBI" O="$OPENSBI_OUT" PLATFORM=generic \
  CROSS_COMPILE="$CROSS_COMPILE" \
  FW_PAYLOAD_PATH="$LINUX_OUT/arch/riscv/boot/Image" \
  FW_FDT_PATH="$DTB" \
  FW_TEXT_START=0x80000000 \
  -j"$JOBS"

cp "$OPENSBI_OUT/platform/generic/firmware/fw_payload.bin" \
  "$OUT/cl_cva6_linux.bin"

echo
echo "Boot image: $OUT/cl_cva6_linux.bin"
ls -lh "$OUT/cl_cva6_linux.bin" "$DTB" \
  "$LINUX_OUT/arch/riscv/boot/Image"
