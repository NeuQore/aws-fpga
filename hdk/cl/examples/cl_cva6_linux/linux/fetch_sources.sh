#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=sources.env.sh
source "$ROOT/sources.env.sh"

clone() {
  local ref="$1" dst="$2" url="$3"
  if [[ -d "$dst/.git" ]]; then
    echo "Skip existing $dst"
    return 0
  fi
  rm -rf "$dst"
  echo "Cloning $ref from $url -> $dst"
  git clone --depth 1 --branch "$ref" "$url" "$dst"
}

clone cva6 "$NEUQORE_LINUX" https://github.com/NeuQore/linux.git
clone cva6 "$NEUQORE_OPENSBI" https://github.com/NeuQore/opensbi.git
clone cva6 "$NEUQORE_BUSYBOX" https://github.com/NeuQore/busybox.git

echo "Sources:"
echo "  linux   $NEUQORE_LINUX"
echo "  opensbi $NEUQORE_OPENSBI"
echo "  busybox $NEUQORE_BUSYBOX"
