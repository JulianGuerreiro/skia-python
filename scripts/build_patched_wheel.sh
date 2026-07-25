#!/usr/bin/env bash
#
# Build a PATCHED skia-python wheel from a fresh checkout, natively on the host.
#
# Use this to produce an aarch64 wheel (the prebuilt x86_64 wheel cannot run on
# aarch64, and Skia cannot be cross-built reliably from an x86_64 host). It also
# works to rebuild on x86_64. It applies the upstream skia-python m138 build
# patches, then the two gd-renderer skparagraph patches, then builds Skia's
# static libs + the pybind extension + a wheel.
#
#   Run from the repo root:   bash scripts/build_patched_wheel.sh
#
# Requirements on the build host (must match the run target's arch):
#   - gn and ninja for THIS arch. NOTE: depot_tools/gn and depot_tools/ninja are
#     x86_64 binaries and will NOT run on aarch64 — install native ones:
#       Debian/Ubuntu: apt-get install ninja-build generate-ninja   (gn = generate-ninja;
#                      if unavailable, build gn from https://gn.googlesource.com/gn)
#       Fedora/RHEL:   dnf install ninja-build gn
#   - a C/C++ compiler (gcc/g++) and dev headers: fontconfig, freetype, mesa GL/EGL,
#     libglvnd (see scripts/build_Linux.sh for the full yum list).
#   - the target CPython (default: python3; override with PYTHON=/path/to/python).
#
# This assumes a FRESH checkout (patches not yet applied). Re-running on an
# already-patched tree will fail at the patch step — start from a clean clone.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PYTHON="${PYTHON:-python3}"
: "${CC:=gcc}"
: "${CXX:=g++}"

echo "== build host: arch=$(uname -m)  python=$("$PYTHON" -V 2>&1)  cc=$CC  cxx=$CXX =="

# --- 0. tool sanity (fail early with guidance) ---------------------------------
command -v gn    >/dev/null || { echo "ERROR: 'gn' not on PATH. See the header of this script (depot_tools' gn is x86_64 — install a native gn)."; exit 1; }
command -v ninja >/dev/null || { echo "ERROR: 'ninja' not on PATH. Install ninja-build for this arch."; exit 1; }
command -v "$CXX" >/dev/null || { echo "ERROR: C++ compiler '$CXX' not found."; exit 1; }

# --- 1. skia submodule at the pinned commit ------------------------------------
echo "== [1/6] checkout skia submodule (pinned m138) =="
git submodule update --init --recursive skia

cd skia

# --- 2. upstream skia-python build patches (order matters) ----------------------
# minimize-download must come before git-sync-deps so only the reduced set of
# third_party externals is fetched.
echo "== [2/6] apply upstream skia-python m138 build patches =="
patch -p1 < ../patch/skia-m138-minimize-download.patch
patch -p1 < ../patch/skia-m132-colrv1-freetype.diff
patch -p1 < ../patch/skia-m132-egl-runtime.diff

# --- 3. fetch third-party externals --------------------------------------------
echo "== [3/6] git-sync-deps (downloads ~hundreds of MB) =="
"$PYTHON" tools/git-sync-deps

# --- 4. the two gd-renderer skparagraph patches (cr-parity) --------------------
echo "== [4/6] apply gd-renderer skparagraph patches =="
git apply ../patch/gd-renderer-skparagraph-hinting.diff
git apply ../patch/gd-renderer-skparagraph-lineheight.diff

# --- 5. configure + build Skia static libs -------------------------------------
# No target_cpu is set: gn defaults to the host arch, so on aarch64 this builds
# arm64 natively. Same args as scripts/build_Linux.sh.
echo "== [5/6] gn gen + ninja (this is the long part) =="
gn gen out/Release --args='
is_official_build=true
skia_enable_svg=true
skia_use_vulkan=true
skia_use_system_libjpeg_turbo=false
skia_use_system_libwebp=false
skia_use_system_libpng=false
skia_use_system_icu=false
skia_use_system_harfbuzz=false
skia_use_system_freetype2=false
extra_cflags_cc=["-frtti"]
extra_ldflags=["-lrt"]
'
ninja -C out/Release

cd ..

# --- 6. build the pybind extension + wheel -------------------------------------
# Remove any stale extension .so first: setuptools does NOT notice that the static
# libs changed, so it would skip the relink otherwise.
echo "== [6/6] build extension + wheel =="
rm -f build/lib.*/skia.*.so
CC="$CC" CXX="$CXX" LDSHARED="$CXX -shared" LDCXXSHARED="$CXX -shared" \
    "$PYTHON" setup.py bdist_wheel

echo
echo "== DONE. Patched wheel(s): =="
ls -la dist/*.whl
echo
echo "Install it:  $PYTHON -m pip install dist/skia_python-*-linux_$(uname -m).whl"
echo "Verify the line-height patch (should print 19.5, not 20.0):"
echo "  $PYTHON - <<'EOF'"
echo "  import skia"
echo "  fc=skia.textlayout.FontCollection(); fc.setDefaultFontManager(skia.FontMgr())"
echo "  ts=skia.textlayout.TextStyle(); ts.setFontSize(13); ts.setHeightOverride(True)"
echo "  ts.setHalfLeading(True); ts.setHeight(1.5)"
echo "  b=skia.textlayout.ParagraphBuilder(skia.textlayout.ParagraphStyle(), fc, skia.Unicode.ICU_Make())"
echo "  b.pushStyle(ts); b.addText('Ag\\nAg'); p=b.Build(); p.layout(1e6); print(p.Height/2)"
echo "  EOF"
