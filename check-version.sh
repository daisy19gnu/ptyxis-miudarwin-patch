#!/bin/sh
#
# check-version.sh - Show current Ptyxis version and upstream tag page
#
# Usage: ./check-version.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT_DIR="$SCRIPT_DIR/miudarwin-port"
GITLAB_TAGS_URL="https://gitlab.gnome.org/chergert/ptyxis/-/tags"

# MIU Darwin has no ports Makefile; the version lives in distinfo, which is
# also the file the checksum is verified against.  Reading it from there keeps
# the two from drifting apart.
get_version() {
    sed -n 's/^SHA256 (ptyxis-\(.*\)\.tar\.xz).*/\1/p' "$PORT_DIR/distinfo"
}

CURRENT_VERSION="$(get_version)"
DISTINFO="$PORT_DIR/distinfo"

# stat(1) format differs between GNU (Linux) and BSD
DISTINFO_DATE="$(stat -c '%y' "$DISTINFO" 2>/dev/null \
             || stat -f '%Sm' "$DISTINFO" 2>/dev/null \
             || echo "(unknown)")"

printf 'Current version : %s\n' "$CURRENT_VERSION"
printf 'distinfo updated: %s\n' "$DISTINFO_DATE"
printf '\n'
printf 'Upstream tags   : %s\n' "$GITLAB_TAGS_URL"
printf '\n'
printf 'Next steps:\n'
printf '  1. Open the URL above and check for a newer stable tag.\n'
printf '  2. If a new version is available:\n'
printf '       ./build-ptyxis.sh <new-version>\n'
printf '  3. Re-check that both patches still apply before bumping the\n'
printf '     revision directory (patches/ptyxis-<version>-r1/).\n'
