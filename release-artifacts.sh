#!/usr/bin/env bash
#
# release-artifacts.sh — build prebuilt adeb rootfs images and publish them as
# GitHub Release assets, so that `adeb prepare` / `adeb prepare --full` can
# DOWNLOAD the rootfs instead of building it locally every time.
#
# Hands-off: run it once with a single Android device connected (adb root
# working) and `gh` authenticated, then walk away. It will:
#   1. build the BASE image      -> androdeb-fs-minimal.tgz.zip   (fast)
#   2. build the FULL image      -> androdeb-fs.tgz.zip           (slow*)
#   3. publish both to the GitHub Release for tag VERSION (v0.99h).
#
# *FULL builds BCC from source. On an x86 host that runs under qemu-user
#  emulation and can take tens of minutes — but it is fully automated.
#
# Usage:
#   ./release-artifacts.sh [OUTDIR]
# Env overrides:
#   TAG=v0.99h        release tag (default: VERSION from ./androdeb)
#   REPO=owner/name   target repo (default: origin's GitHub slug)
#   SKIP_FULL=1       build/publish only the base image
#   SKIP_PUBLISH=1    build artifacts but do not touch GitHub
#
set -euo pipefail

SPATH="$(cd "$(dirname "$0")" && pwd)"
cd "$SPATH"

OUTDIR="${1:-$SPATH/dist}"
TAG="${TAG:-$(grep -m1 '^VERSION=' androdeb | cut -d= -f2)}"
REPO="${REPO:-$(git config --get remote.origin.url \
        | sed -e 's#.*[:/]\([^/]*/[^/]*\)$#\1#' -e 's/\.git$//')}"
LOG="$OUTDIR/build.log"

BASE_ZIP="$OUTDIR/androdeb-fs-minimal.tgz.zip"
FULL_ZIP="$OUTDIR/androdeb-fs.tgz.zip"

log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[!]\033[0m %s\n' "$*" >&2; exit 1; }

mkdir -p "$OUTDIR"
: > "$LOG"

log "Output dir : $OUTDIR"
log "Release tag: $TAG"
log "Repo       : $REPO"
log "Build log  : $LOG"

# ---- prerequisites ----------------------------------------------------------
command -v zip >/dev/null || die "zip not found (required by adeb --buildtar)"
if ! adb get-state >/dev/null 2>&1; then
    echo "---- adb devices ----" >&2
    adb devices -l 2>&1 >&2 || true
    die "no adb device online (reconnect USB / re-approve the adb prompt, or 'adb connect <ip>')"
fi
if [ -z "${SKIP_PUBLISH:-}" ]; then
    command -v gh >/dev/null || die "gh not found (install it or set SKIP_PUBLISH=1)"
    gh auth status >/dev/null 2>&1 || die "gh not authenticated (run: gh auth login)"
fi

# ---- build BASE -------------------------------------------------------------
log "Building BASE image (this is the fast one)…"
./adeb prepare --build --buildtar "$OUTDIR" >>"$LOG" 2>&1 \
    || { tail -n 40 "$LOG"; die "base build failed (see $LOG)"; }
[ -f "$BASE_ZIP" ] || { tail -n 40 "$LOG"; die "base artifact missing: $BASE_ZIP"; }
ok "Base artifact ready: $BASE_ZIP ($(du -h "$BASE_ZIP" | cut -f1))"

ASSETS=("$BASE_ZIP")

# ---- build FULL -------------------------------------------------------------
if [ -z "${SKIP_FULL:-}" ]; then
    log "Building FULL image (BCC compiled from source; slow under emulation)…"
    ./adeb prepare --full --build --buildtar "$OUTDIR" >>"$LOG" 2>&1 \
        || { tail -n 40 "$LOG"; die "full build failed (see $LOG)"; }
    [ -f "$FULL_ZIP" ] || { tail -n 40 "$LOG"; die "full artifact missing: $FULL_ZIP"; }
    ok "Full artifact ready: $FULL_ZIP ($(du -h "$FULL_ZIP" | cut -f1))"
    ASSETS+=("$FULL_ZIP")
else
    log "SKIP_FULL set — skipping full image."
fi

# ---- publish ----------------------------------------------------------------
if [ -n "${SKIP_PUBLISH:-}" ]; then
    ok "SKIP_PUBLISH set — artifacts left in $OUTDIR, nothing pushed."
    exit 0
fi

log "Publishing to GitHub Release '$TAG' on $REPO …"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    log "Release $TAG already exists — uploading assets (--clobber)…"
    gh release upload "$TAG" "${ASSETS[@]}" --repo "$REPO" --clobber
else
    gh release create "$TAG" "${ASSETS[@]}" --repo "$REPO" \
        --title "adeb $TAG — prebuilt arm64/bookworm rootfs" \
        --notes "Prebuilt ARM64 Debian bookworm rootfs images for \`adeb prepare\`.

* \`androdeb-fs-minimal.tgz.zip\` — base image → \`adeb prepare\`
* \`androdeb-fs.tgz.zip\` — full image (compilers, tracers, BCC) → \`adeb prepare --full\`

Built on a real aarch64 device. Other architectures/distros still need \`--build\`."
fi

ok "DONE. Now \`adeb prepare\` (base) and \`adeb prepare --full\` will download instead of build."
