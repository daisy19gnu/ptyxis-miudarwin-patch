#!/bin/sh
#
# build-ptyxis.sh - Fetch, patch and cross build Ptyxis for MIU Darwin
#
# Usage: ./build-ptyxis.sh [version]
#        MIU_TREE=/path/to/MIU-Darwin ./build-ptyxis.sh 50.1
#
# The OpenBSD sibling of this script builds over ssh, because the target is a
# real OpenBSD machine.  MIU Darwin is cross compiled from the same host that
# runs this script, so there is no remote step; what it needs instead is the
# MIU Darwin tree, which supplies the meson cross file and the already built
# GTK4 / libadwaita / VTE.
#
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT_DIR="$SCRIPT_DIR/miudarwin-port"

VERSION="${1:-$(sed -n 's/^SHA256 (ptyxis-\(.*\)\.tar\.xz).*/\1/p' "$PORT_DIR/distinfo")}"
SERIES="$(printf '%s' "$VERSION" | cut -d. -f1)"
TARBALL="ptyxis-$VERSION.tar.xz"
URL="https://download.gnome.org/sources/ptyxis/$SERIES/$TARBALL"

MIU_TREE="${MIU_TREE:-}"
if [ -z "$MIU_TREE" ] || [ ! -d "$MIU_TREE/userland/ptyxis" ]; then
    echo "MIU_TREE を MIU Darwin の作業ツリーに向けてください。" >&2
    echo "  例: MIU_TREE=\$HOME/MIU-Darwin ./build-ptyxis.sh $VERSION" >&2
    exit 2
fi
CROSS="$MIU_TREE/userland/ptyxis/miu-config/miu-cross.ini"
[ -f "$CROSS" ] || { echo "クロスファイルが無い: $CROSS" >&2; exit 2; }

WORK="${WORK:-$SCRIPT_DIR/.build}"
mkdir -p "$WORK"
cd "$WORK"

echo "[1/4] 取得 $URL"
[ -f "$TARBALL" ] || curl -fLO "$URL"

#
# 取ってきた物が本物か確かめてから開く。開いてから気付いても遅い。
# OpenBSD の distinfo は base64 だが、ここは hex なので sha256sum で足りる。
#
echo "[2/4] 検める"
( cd "$PORT_DIR" && sha256sum -c distinfo ) 2>/dev/null \
  || ( cd "$WORK" && sha256sum -c "$PORT_DIR/distinfo" )

rm -rf "ptyxis-$VERSION"
tar xf "$TARBALL"
cd "ptyxis-$VERSION"

echo "[3/4] パッチを当てる"
for p in "$PORT_DIR/patches"/patch-*; do
    [ -f "$p" ] || continue
    printf '  %s\n' "$(basename "$p")"
    patch -p0 < "$p"
done

echo "[4/4] 組む"
meson setup build --cross-file "$CROSS" --prefix=/usr --libdir=lib
ninja -C build

echo
echo "できました:"
ls -l build/src/ptyxis build/agent/ptyxis-agent 2>/dev/null || true
echo
echo "イメージへ配るには MIU Darwin ツリー側で:"
echo "  scripts/deploy-ptyxis.sh"
